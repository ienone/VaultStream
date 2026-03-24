from __future__ import annotations

import asyncio
import hashlib
import math
import re
from dataclasses import dataclass
from datetime import datetime
from typing import Optional

from sqlalchemy import and_, or_, select, text
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.database import AsyncSessionLocal
from app.core.logging import logger
from app.models import (
    Content,
    ContentEmbedding,
    ContentStatus,
    DiscoveryState,
    Platform,
)
from app.services.settings_service import get_setting_value


@dataclass
class SemanticSearchHit:
    content: Content
    score: float
    match_source: str  # vector | fts | hybrid


class EmbeddingService:
    """
    语义索引与混合检索服务。

    设计原则：
    - 没有外部 embedding 配置时自动降级到本地确定性向量，保证功能可用；
    - 索引和搜索接口可独立使用，便于任务/脚本/API 复用。
    """

    _RRF_K = 60
    _LOCAL_DIM = 256
    _MAX_BODY_CHARS = 4000
    _DEFAULT_MODEL = "gemini-embedding-2-preview"
    _DEFAULT_OUTPUT_DIMENSIONALITY = 1536
    _DOCUMENT_TASK_TYPE = "RETRIEVAL_DOCUMENT"
    _QUERY_TASK_TYPE = "RETRIEVAL_QUERY"

    async def embed_content(self, content: Content) -> list[float]:
        text_payload = self._build_content_text(content)
        return await self._embed_text(text_payload, task_type=self._DOCUMENT_TASK_TYPE)

    async def embed_query(self, query: str) -> list[float]:
        return await self._embed_text(query, task_type=self._QUERY_TASK_TYPE)

    async def index_content(self, content_id: int, *, session: Optional[AsyncSession] = None) -> bool:
        if session is not None:
            return await self._index_content_impl(content_id, session, own_session=False)

        async with AsyncSessionLocal() as local_session:
            return await self._index_content_impl(content_id, local_session, own_session=True)

    async def search(
        self,
        *,
        query: str,
        top_k: int = 20,
        platform: Optional[str] = None,
        date_from: Optional[datetime] = None,
        date_to: Optional[datetime] = None,
        session: Optional[AsyncSession] = None,
    ) -> list[SemanticSearchHit]:
        if not query.strip():
            return []

        if session is not None:
            return await self._search_impl(
                query=query,
                top_k=top_k,
                platform=platform,
                date_from=date_from,
                date_to=date_to,
                session=session,
            )

        async with AsyncSessionLocal() as local_session:
            return await self._search_impl(
                query=query,
                top_k=top_k,
                platform=platform,
                date_from=date_from,
                date_to=date_to,
                session=local_session,
            )

    async def _index_content_impl(
        self,
        content_id: int,
        session: AsyncSession,
        *,
        own_session: bool,
    ) -> bool:
        content = (
            await session.execute(
                select(Content).where(
                    Content.id == content_id,
                    Content.status == ContentStatus.PARSE_SUCCESS,
                )
            )
        ).scalar_one_or_none()
        if content is None:
            return False

        payload = self._build_content_text(content)
        if not payload:
            return False

        text_hash = self._hash_text(payload)
        model_signature = await self._get_document_embedding_signature()
        existing = (
            await session.execute(
                select(ContentEmbedding).where(ContentEmbedding.content_id == content_id)
            )
        ).scalar_one_or_none()

        if existing and existing.text_hash == text_hash and existing.embedding_model == model_signature:
            return False

        vector = await self._embed_text(payload, task_type=self._DOCUMENT_TASK_TYPE)
        record = existing or ContentEmbedding(content_id=content_id)
        record.embedding_model = model_signature
        record.embedding = vector
        record.text_hash = text_hash
        record.source_text = payload[:4000]
        record.indexed_at = datetime.utcnow()

        if existing is None:
            session.add(record)

        if own_session:
            await session.commit()
        else:
            await session.flush()
        return True

    async def _search_impl(
        self,
        *,
        query: str,
        top_k: int,
        platform: Optional[str],
        date_from: Optional[datetime],
        date_to: Optional[datetime],
        session: AsyncSession,
    ) -> list[SemanticSearchHit]:
        filters = self._build_content_filters(platform=platform, date_from=date_from, date_to=date_to)
        candidate_limit = max(50, top_k * 6)

        query_vec = await self.embed_query(query)
        vector_ranked = await self._vector_rank_ids(
            session=session,
            query_vec=query_vec,
            filters=filters,
            limit=candidate_limit,
        )
        vector_ids = [cid for cid, _ in vector_ranked]
        vector_score_map = {cid: score for cid, score in vector_ranked}

        fts_ids = await self._fts_rank_ids(
            session=session,
            query=query,
            filters=filters,
            limit=candidate_limit,
        )

        merged = self._rrf_merge(vector_ids=vector_ids, fts_ids=fts_ids, top_k=top_k)
        if not merged:
            return []

        merged_ids = [cid for cid, _ in merged]
        contents = (
            await session.execute(select(Content).where(Content.id.in_(merged_ids)))
        ).scalars().all()
        content_map = {c.id: c for c in contents}

        results: list[SemanticSearchHit] = []
        for content_id, rrf_score in merged:
            content = content_map.get(content_id)
            if content is None:
                continue

            in_vector = content_id in vector_score_map
            in_fts = content_id in set(fts_ids)
            if in_vector and in_fts:
                source = "hybrid"
            elif in_vector:
                source = "vector"
            else:
                source = "fts"

            # 对外 score 使用融合分数；如果仅向量召回则保留较直观相似度下界
            score = float(rrf_score if source != "vector" else max(rrf_score, vector_score_map[content_id]))
            results.append(SemanticSearchHit(content=content, score=score, match_source=source))
        return results

    async def _vector_rank_ids(
        self,
        *,
        session: AsyncSession,
        query_vec: list[float],
        filters: list,
        limit: int,
    ) -> list[tuple[int, float]]:
        # 补充模型维度隔离墙：防止模型更替后新老向量维度不一致导致的错误截断或计算垃圾分数
        current_model = await self._get_document_embedding_signature()
        model_filters = list(filters)
        model_filters.append(ContentEmbedding.embedding_model == current_model)
        
        rows = (
            await session.execute(
                select(ContentEmbedding.content_id, ContentEmbedding.embedding)
                .join(Content, Content.id == ContentEmbedding.content_id)
                .where(and_(*model_filters))
            )
        ).all()

        if not rows:
            return []

        import numpy as np
        
        q = np.array(query_vec, dtype=np.float32)
        doc_ids = np.array([row.content_id for row in rows])
        
        # 安全转换：提取出纯净的、同维度的向量数组
        vec_list = [self._coerce_vector(row.embedding) for row in rows]
        valid_indices = [i for i, vec in enumerate(vec_list) if len(vec) == len(q) and len(vec) > 0]
        
        if not valid_indices:
            return []
            
        filtered_ids = doc_ids[valid_indices]
        filtered_vecs = np.array([vec_list[i] for i in valid_indices], dtype=np.float32)


        scores = np.dot(filtered_vecs, q)

        top_indices = np.argsort(scores)[::-1][:limit]
        
        return [(int(filtered_ids[i]), float(scores[i])) for i in top_indices]

    async def _fts_rank_ids(
        self,
        *,
        session: AsyncSession,
        query: str,
        filters: list,
        limit: int,
    ) -> list[int]:
        try:
            fts_rows = (
                await session.execute(
                    text(
                        "SELECT content_id FROM contents_fts "
                        "WHERE contents_fts MATCH :q "
                        "LIMIT :limit"
                    ),
                    {"q": query, "limit": int(limit)},
                )
            ).all()
            raw_ids = [int(row[0]) for row in fts_rows]
            if not raw_ids:
                return []

            filtered_ids = (
                await session.execute(
                    select(Content.id).where(Content.id.in_(raw_ids), and_(*filters))
                )
            ).scalars().all()
            filtered_set = set(int(cid) for cid in filtered_ids)
            return [cid for cid in raw_ids if cid in filtered_set]
        except Exception:
            logger.debug("FTS query unavailable, fallback to LIKE ranking")

        like_expr = f"%{query}%"
        fallback_ids = (
            await session.execute(
                select(Content.id)
                .where(
                    and_(
                        *filters,
                        or_(
                            Content.title.ilike(like_expr),
                            Content.summary.ilike(like_expr),
                            Content.body.ilike(like_expr),
                        ),
                    )
                )
                .order_by(Content.created_at.desc())
                .limit(limit)
            )
        ).scalars().all()
        return [int(cid) for cid in fallback_ids]

    def _rrf_merge(self, *, vector_ids: list[int], fts_ids: list[int], top_k: int) -> list[tuple[int, float]]:
        scores: dict[int, float] = {}

        for rank, cid in enumerate(vector_ids, start=1):
            scores[cid] = scores.get(cid, 0.0) + 1.0 / (self._RRF_K + rank)
        for rank, cid in enumerate(fts_ids, start=1):
            scores[cid] = scores.get(cid, 0.0) + 1.0 / (self._RRF_K + rank)

        merged = sorted(scores.items(), key=lambda item: item[1], reverse=True)
        return merged[:top_k]

    def _build_content_filters(
        self,
        *,
        platform: Optional[str],
        date_from: Optional[datetime],
        date_to: Optional[datetime],
    ) -> list:
        filters = [
            Content.status == ContentStatus.PARSE_SUCCESS,
            or_(
                Content.discovery_state.is_(None),
                Content.discovery_state == DiscoveryState.PROMOTED,
            ),
        ]
        if platform:
            filters.append(Content.platform == Platform(platform))
        if date_from is not None:
            filters.append(Content.created_at >= date_from)
        if date_to is not None:
            filters.append(Content.created_at <= date_to)
        return filters

    def _build_content_text(self, content: Content) -> str:
        tags = content.tags or []
        if not isinstance(tags, list):
            tags = []

        body = (content.body or "").strip()
        if len(body) > self._MAX_BODY_CHARS:
            body = body[: self._MAX_BODY_CHARS]

        parts = [
            (content.title or "").strip(),
            (content.summary or "").strip(),
            body,
            f"作者: {(content.author_name or '').strip()}",
            f"标签: {' '.join([str(t) for t in tags if str(t).strip()])}",
        ]
        
        # 融合 Agent 提纯的隐藏向量数据
        if isinstance(content.context_data, dict):
            rag_keywords = content.context_data.get("rag_keywords")
            if isinstance(rag_keywords, list) and rag_keywords:
                parts.append(f"核心提取关键词: {', '.join([str(k) for k in rag_keywords])}")
            core_args = content.context_data.get("core_arguments")
            if isinstance(core_args, str) and core_args:
                parts.append(f"核心长文主旨: {core_args}")

        return "\n".join(p for p in parts if p).strip()

    def _hash_text(self, text_value: str) -> str:
        return hashlib.sha256(text_value.encode("utf-8")).hexdigest()

    async def _embed_text(
        self,
        text_value: str,
        *,
        task_type: str,
    ) -> list[float]:
        text_value = text_value.strip()
        if not text_value:
            return self._build_local_embedding("")

        model = await self._get_embedding_model()
        api_key = await self._get_embedding_api_key()
        output_dimensionality = await self._get_embedding_output_dimensionality()
        if not api_key:
            return self._build_local_embedding(text_value)

        try:
            from google import genai
            from google.genai import types

            # google-genai 的 embed 接口是同步调用，放到线程池里避免阻塞事件循环。
            def _call_gemini():
                client = genai.Client(api_key=api_key)
                return client.models.embed_content(
                    model=model,
                    contents=text_value,
                    config=types.EmbedContentConfig(
                        task_type=task_type,
                        output_dimensionality=output_dimensionality,
                    ),
                )

            response = await asyncio.to_thread(_call_gemini)
            vector = response.embeddings[0].values if response.embeddings else None

            if not vector:
                return self._build_local_embedding(text_value)
            return self._normalize_vector([float(v) for v in vector])
        except Exception as e:
            logger.warning(f"Embedding remote call failed, fallback to local: {e}")
            return self._build_local_embedding(text_value)

    async def _get_embedding_model(self) -> str:
        model = await get_setting_value("embedding_model")
        if isinstance(model, str) and model.strip():
            return model.strip()
        return self._DEFAULT_MODEL

    async def _get_embedding_api_key(self) -> Optional[str]:
        key = await get_setting_value("embedding_api_key")
        if isinstance(key, str) and key.strip():
            return key.strip()
        return None

    async def _get_embedding_output_dimensionality(self) -> int:
        value = await get_setting_value("embedding_output_dimensionality")
        try:
            dimension = int(value)
        except (TypeError, ValueError):
            return self._DEFAULT_OUTPUT_DIMENSIONALITY

        if 128 <= dimension <= 3072:
            return dimension
        return self._DEFAULT_OUTPUT_DIMENSIONALITY

    async def _get_document_embedding_signature(self) -> str:
        model = await self._get_embedding_model()
        dimension = await self._get_embedding_output_dimensionality()
        return f"{model}|dim={dimension}|task={self._DOCUMENT_TASK_TYPE}"

    def _build_local_embedding(self, text_value: str) -> list[float]:
        vec = [0.0] * self._LOCAL_DIM
        tokens = re.findall(r"[\w\u4e00-\u9fff]+", text_value.lower())
        if not tokens:
            return vec

        for token in tokens:
            digest = hashlib.md5(token.encode("utf-8")).hexdigest()
            hashed = int(digest, 16)
            idx = hashed % self._LOCAL_DIM
            sign = -1.0 if ((hashed >> 8) & 1) else 1.0
            vec[idx] += sign
        return self._normalize_vector(vec)

    def _normalize_vector(self, vector: list[float]) -> list[float]:
        norm = math.sqrt(sum(v * v for v in vector))
        if norm == 0:
            return vector
        return [v / norm for v in vector]

    def _coerce_vector(self, value) -> list[float]:
        if not isinstance(value, list):
            return []
        try:
            return [float(v) for v in value]
        except Exception:
            return []

    def _cosine_similarity(self, a: list[float], b: list[float]) -> float:
        if not a or not b:
            return float("nan")
        length = min(len(a), len(b))
        if length == 0:
            return float("nan")
        return float(sum(a[i] * b[i] for i in range(length)))
