from __future__ import annotations

import asyncio
import hashlib
import math
import re
import time
from dataclasses import dataclass
from datetime import datetime
from typing import Optional

from sqlalchemy import and_, or_, select, text
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.database import AsyncSessionLocal
from app.core.logging import logger
from app.utils.text_search import rank_ids_by_fts_or_like
from app.models import (
    Content,
    ContentEmbedding,
    ContentStatus,
    DiscoveryState,
    Platform,
)
from app.services.settings_service import get_setting_value
from app.adapters.storage.manager import get_storage_backend


@dataclass
class SemanticSearchHit:
    content: Content
    score: float
    match_source: str  # vector | fts | hybrid
    chunk_index: int = -1
    chunk_title: Optional[str] = None


class EmbeddingService:
    """
    语义索引与混合检索服务。支持 AI 智能切片与多模态嵌入。
    """

    _RRF_K = 60
    _LOCAL_DIM = 256
    _MAX_BODY_CHARS = 4000
    _DEFAULT_MODEL = "gemini-embedding-2-preview"
    _DEFAULT_OUTPUT_DIMENSIONALITY = 1536
    _DOCUMENT_TASK_TYPE = "RETRIEVAL_DOCUMENT"
    _QUERY_TASK_TYPE = "RETRIEVAL_QUERY"

    async def embed_query(self, query: str) -> list[float]:
        return await self._embed_text(query, task_type=self._QUERY_TASK_TYPE)

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

    async def index_content(self, content_id: int, *, session: Optional[AsyncSession] = None) -> bool:

        if session is not None:
            return await self._index_content_impl(content_id, session, own_session=False)

        async with AsyncSessionLocal() as local_session:
            return await self._index_content_impl(content_id, local_session, own_session=True)

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

        # 1. 准备全局摘要向量 (Index = -1)
        global_payload = self._build_content_text(content)
        if global_payload:
            await self._upsert_embedding(
                session, content_id, -1, "全局摘要", global_payload, []
            )

        # 2. 处理 AI 智能切片 (Index >= 0)
        chunks = (content.rich_payload or {}).get("chunks", [])
        if chunks:
            logger.info(f"Indexing {len(chunks)} semantic chunks for content_id={content_id}")
            for idx, chunk in enumerate(chunks):
                title = chunk.get("title", f"片段 {idx}")
                text_part = chunk.get("content", "")
                media_refs = chunk.get("media_refs", [])
                
                if text_part:
                    await self._upsert_embedding(
                        session, content_id, idx, title, text_part, media_refs
                    )

        if own_session:
            await session.commit()
        else:
            await session.flush()
        return True

    async def _upsert_embedding(
        self, 
        session: AsyncSession, 
        content_id: int, 
        chunk_index: int, 
        chunk_title: str,
        text_val: str,
        media_refs: list[str]
    ):
        """执行单个切片的向量化与入库"""
        text_hash = self._hash_text(text_val + "".join(media_refs))
        model_signature = await self._get_document_embedding_signature()
        
        existing = (
            await session.execute(
                select(ContentEmbedding).where(
                    ContentEmbedding.content_id == content_id,
                    ContentEmbedding.chunk_index == chunk_index
                )
            )
        ).scalar_one_or_none()

        if existing and existing.text_hash == text_hash and existing.embedding_model == model_signature:
            return

        # 调用多模态嵌入
        vector = await self._embed_multimodal(text_val, media_refs)
        
        record = existing or ContentEmbedding(content_id=content_id, chunk_index=chunk_index)
        record.embedding_model = model_signature
        record.embedding = vector
        record.text_hash = text_hash
        record.source_text = text_val[:4000]
        record.chunk_title = chunk_title
        record.indexed_at = datetime.utcnow()

        if existing is None:
            session.add(record)

    async def _embed_multimodal(self, text_val: str, media_refs: list[str]) -> list[float]:
        """调用 Gemini V2 生成图文混合向量"""
        if not media_refs:
            return await self._embed_text(text_val, task_type=self._DOCUMENT_TASK_TYPE)

        api_key = await self._get_embedding_api_key()
        if not api_key:
            return self._build_local_embedding(text_val)

        storage = get_storage_backend()
        mm_parts = []
        
        # 组装文本
        mm_parts.append(text_val)
        
        # 组装图片
        for ref in media_refs[:3]: # 限制每个切片最多 3 张图
            if ref.startswith("local://"):
                key = ref.replace("local://", "")
                try:
                    img_bytes = await storage.get_bytes(key)
                    mm_parts.append({"mime_type": "image/jpeg", "data": img_bytes})
                except Exception:
                    continue

        try:
            from google import genai
            from google.genai import types
            model = await self._get_embedding_model()
            output_dimensionality = await self._get_embedding_output_dimensionality()

            def _call():
                client = genai.Client(api_key=api_key)
                return client.models.embed_content(
                    model=model,
                    contents=mm_parts,
                    config=types.EmbedContentConfig(
                        task_type=self._DOCUMENT_TASK_TYPE,
                        output_dimensionality=output_dimensionality,
                    ),
                )

            response = await asyncio.to_thread(_call)
            vector = response.embeddings[0].values
            return self._normalize_vector([float(v) for v in vector])
        except Exception as e:
            logger.warning(f"Multimodal embedding failed: {e}")
            return await self._embed_text(text_val, task_type=self._DOCUMENT_TASK_TYPE)


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
        started_at = time.perf_counter()
        filters = self._build_content_filters(platform=platform, date_from=date_from, date_to=date_to)
        candidate_limit = max(50, top_k * 6)

        query_vec = await self.embed_query(query)
        vector_ranked = await self._vector_rank_ids(
            session=session,
            query_vec=query_vec,
            filters=filters,
            limit=candidate_limit,
        )
        vector_ids = [cid for cid, _, _, _ in vector_ranked]
        vector_meta_map = {cid: (score, cidx, ctitle) for cid, score, cidx, ctitle in vector_ranked}

        fts_ids = await rank_ids_by_fts_or_like(
            session=session,
            query=query,
            filters=filters,
            limit=candidate_limit,
            like_columns=(Content.title, Content.summary, Content.body),
        )

        merged = self._rrf_merge(vector_ids=vector_ids, fts_ids=fts_ids, top_k=top_k)
        if not merged:
            logger.bind(
                component="semantic_search",
                candidate_limit=candidate_limit,
                vector_candidates=len(vector_ids),
                fts_candidates=len(fts_ids),
                result_count=0,
                elapsed_ms=round((time.perf_counter() - started_at) * 1000, 2),
            ).info("Semantic search completed")
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

            in_vector = content_id in vector_meta_map
            in_fts = content_id in set(fts_ids)
            
            score = rrf_score
            cidx, ctitle = -1, None
            
            if in_vector:
                v_score, cidx, ctitle = vector_meta_map[content_id]
                if not in_fts:
                    score = max(rrf_score, v_score)
                source = "hybrid" if in_fts else "vector"
            else:
                source = "fts"

            results.append(SemanticSearchHit(
                content=content, 
                score=float(score), 
                match_source=source,
                chunk_index=cidx,
                chunk_title=ctitle
            ))
        logger.bind(
            component="semantic_search",
            candidate_limit=candidate_limit,
            vector_candidates=len(vector_ids),
            fts_candidates=len(fts_ids),
            result_count=len(results),
            elapsed_ms=round((time.perf_counter() - started_at) * 1000, 2),
        ).info("Semantic search completed")
        return results


    async def _vector_rank_ids(
        self,
        *,
        session: AsyncSession,
        query_vec: list[float],
        filters: list,
        limit: int,
    ) -> list[tuple[int, float, int, Optional[str]]]:
        """
        向量搜索：支持多切片。
        返回: list[(content_id, score, chunk_index, chunk_title)]
        """
        # 获取当前模型的基础签名（忽略 task 类型）
        model_base = await self._get_embedding_model()
        dim = await self._get_embedding_output_dimensionality()
        model_pattern = f"{model_base}|dim={dim}%" # 使用 LIKE 匹配
        
        model_filters = list(filters)
        model_filters.append(ContentEmbedding.embedding_model.like(model_pattern))
        
        stmt = (
            select(
                ContentEmbedding.content_id, 
                ContentEmbedding.embedding,
                ContentEmbedding.chunk_index,
                ContentEmbedding.chunk_title
            )
            .join(Content, Content.id == ContentEmbedding.content_id)
            .where(and_(*model_filters))
        )

        
        rows = (await session.execute(stmt)).all()

        if not rows:
            return []

        import numpy as np
        
        q = np.array(query_vec, dtype=np.float32)
        
        results = []
        for row in rows:
            vec = self._coerce_vector(row.embedding)
            if len(vec) != len(q):
                continue
            
            score = float(np.dot(vec, q))
            results.append((row.content_id, score, row.chunk_index, row.chunk_title))

        # 按分数排序
        results.sort(key=lambda x: x[1], reverse=True)
        
        # 结果去重：同一篇文章如果命中多个 chunk，只保留最高分的那个，但记录 chunk 信息
        seen_content_ids = set()
        unique_results = []
        for cid, score, cidx, ctitle in results:
            if cid not in seen_content_ids:
                unique_results.append((cid, score, cidx, ctitle))
                seen_content_ids.add(cid)
                if len(unique_results) >= limit:
                    break
                    
        return unique_results


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
            logger.bind(
                component="embedding",
                model=model,
                task_type=task_type,
                fallback="local_hash",
            ).warning(f"Embedding remote call failed, fallback to local: {e}")
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
            digest = hashlib.md5(token.encode("utf-8"), usedforsecurity=False).hexdigest()
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
