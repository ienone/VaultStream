from __future__ import annotations

import asyncio
import hashlib
import math
import time
from dataclasses import dataclass
from datetime import datetime
from typing import Optional

from sqlalchemy import and_, desc, func, or_, select
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


@dataclass
class SemanticSearchHit:
    content: Content
    score: float
    match_source: str  # vector | fts | hybrid
    chunk_index: int = -1
    chunk_title: Optional[str] = None
    source_text: Optional[str] = None


class EmbeddingService:
    """
    语义索引与混合检索服务。支持 AI 智能切片与多模态嵌入。
    """

    _RRF_K = 60
    _MAX_BODY_CHARS = 4000
    _SUPPORTED_MODEL = "gemini-embedding-2"
    _DEFAULT_OUTPUT_DIMENSIONALITY = 1536
    _SIGNATURE_VERSION = "vaultstream_rag_v1"
    _REMOTE_CONCURRENCY = 2
    _EMBED_CACHE: dict[str, list[float]] = {}
    _REMOTE_SEMAPHORE = asyncio.Semaphore(_REMOTE_CONCURRENCY)

    async def embed_query(self, query: str) -> list[float]:
        return await self._embed_text(self._prefix_query(query))

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

    async def plan_reindex(
        self,
        *,
        scope: str,
        content_id: int | None = None,
        limit: int = 100,
        session: Optional[AsyncSession] = None,
    ) -> tuple[list[int], int]:
        if session is not None:
            return await self._plan_reindex_impl(
                scope=scope,
                content_id=content_id,
                limit=limit,
                session=session,
            )
        async with AsyncSessionLocal() as local_session:
            return await self._plan_reindex_impl(
                scope=scope,
                content_id=content_id,
                limit=limit,
                session=local_session,
            )

    async def reindex_scope(
        self,
        *,
        scope: str,
        content_id: int | None = None,
        limit: int = 100,
        batch_size: int = 8,
        delay_seconds: float = 0.2,
        session: Optional[AsyncSession] = None,
    ) -> dict:
        if session is not None:
            return await self._reindex_scope_impl(
                scope=scope,
                content_id=content_id,
                limit=limit,
                batch_size=batch_size,
                delay_seconds=delay_seconds,
                session=session,
                own_session=False,
            )
        async with AsyncSessionLocal() as local_session:
            return await self._reindex_scope_impl(
                scope=scope,
                content_id=content_id,
                limit=limit,
                batch_size=batch_size,
                delay_seconds=delay_seconds,
                session=local_session,
                own_session=True,
            )

    async def get_index_status(self, *, session: Optional[AsyncSession] = None) -> dict:
        if session is not None:
            return await self._get_index_status_impl(session)
        async with AsyncSessionLocal() as local_session:
            return await self._get_index_status_impl(local_session)

    async def _plan_reindex_impl(
        self,
        *,
        scope: str,
        content_id: int | None,
        limit: int,
        session: AsyncSession,
    ) -> tuple[list[int], int]:
        normalized_scope = scope.strip().lower()
        limit = max(1, min(int(limit or 100), 5000))
        if normalized_scope == "single":
            if content_id is None:
                raise ValueError("content_id is required for single reindex")
            stmt = select(Content).where(
                Content.id == content_id,
                Content.status == ContentStatus.PARSE_SUCCESS,
            )
        elif normalized_scope == "failed":
            failed_ids = (
                select(ContentEmbedding.content_id)
                .where(ContentEmbedding.index_status == "failed")
                .distinct()
            )
            stmt = (
                select(Content)
                .where(Content.id.in_(failed_ids), Content.status == ContentStatus.PARSE_SUCCESS)
                .order_by(Content.updated_at.desc())
                .limit(limit)
            )
        elif normalized_scope == "all":
            stmt = (
                select(Content)
                .where(Content.status == ContentStatus.PARSE_SUCCESS)
                .order_by(Content.updated_at.desc())
                .limit(limit)
            )
        else:
            raise ValueError("scope must be single, all or failed")

        contents = (await session.execute(stmt)).scalars().all()
        signature = await self._get_document_embedding_signature()
        estimated_calls = 0
        for content in contents:
            estimated_calls += await self._estimate_missing_embedding_calls(
                session=session,
                content=content,
                model_signature=signature,
            )
        return [c.id for c in contents], estimated_calls

    async def _reindex_scope_impl(
        self,
        *,
        scope: str,
        content_id: int | None,
        limit: int,
        batch_size: int,
        delay_seconds: float,
        session: AsyncSession,
        own_session: bool,
    ) -> dict:
        content_ids, estimated_calls = await self._plan_reindex_impl(
            scope=scope,
            content_id=content_id,
            limit=limit,
            session=session,
        )
        indexed = 0
        failed = 0
        batch_size = max(1, min(batch_size, 32))
        for idx, cid in enumerate(content_ids, start=1):
            ok = await self._index_content_impl(cid, session, own_session=False)
            indexed += int(ok)
            failed += int(not ok)
            if idx % batch_size == 0:
                await session.commit()
                await asyncio.sleep(max(0.0, delay_seconds))
        if own_session:
            await session.commit()
        else:
            await session.flush()
        return {
            "scope": scope,
            "content_id": content_id,
            "candidate_count": len(content_ids),
            "estimated_embedding_calls": estimated_calls,
            "indexed": indexed,
            "failed": failed,
        }

    async def _estimate_missing_embedding_calls(
        self,
        *,
        session: AsyncSession,
        content: Content,
        model_signature: str,
    ) -> int:
        units = self._content_embedding_units(content)
        if not units:
            return 0
        existing_rows = (
            await session.execute(
                select(
                    ContentEmbedding.chunk_index,
                    ContentEmbedding.text_hash,
                    ContentEmbedding.embedding_model_signature,
                    ContentEmbedding.embedding_model,
                    ContentEmbedding.index_status,
                ).where(ContentEmbedding.content_id == content.id)
            )
        ).all()
        existing = {row.chunk_index: row for row in existing_rows}
        missing = 0
        for chunk_index, text_value, media_refs, _title in units:
            expected_hash = self._hash_text(text_value + "".join(media_refs))
            row = existing.get(chunk_index)
            row_signature = (row.embedding_model_signature or row.embedding_model) if row else None
            if (
                row is None
                or row.text_hash != expected_hash
                or row_signature != model_signature
                or row.index_status != "indexed"
            ):
                missing += 1
        return missing

    async def _get_index_status_impl(self, session: AsyncSession) -> dict:
        contents_total = (await session.execute(select(func.count(Content.id)))).scalar() or 0
        parse_success_total = (
            await session.execute(
                select(func.count(Content.id)).where(Content.status == ContentStatus.PARSE_SUCCESS)
            )
        ).scalar() or 0
        indexed_total = (
            await session.execute(
                select(func.count(func.distinct(ContentEmbedding.content_id))).where(
                    ContentEmbedding.index_status == "indexed"
                )
            )
        ).scalar() or 0
        raw_status_counts = (
            await session.execute(
                select(ContentEmbedding.index_status, func.count(ContentEmbedding.id))
                .group_by(ContentEmbedding.index_status)
                .order_by(ContentEmbedding.index_status)
            )
        ).all()
        none_count = max(0, int(parse_success_total) - int(indexed_total))
        status_counts = [{"status": "none", "count": none_count}]
        status_counts.extend(
            {"status": str(status or "unknown"), "count": int(count)}
            for status, count in raw_status_counts
        )
        model_distribution = [
            {
                "embedding_model": str(model or "NULL"),
                "embedding_model_signature": str(signature or "NULL"),
                "count": int(count),
            }
            for model, signature, count in (
                await session.execute(
                    select(
                        ContentEmbedding.embedding_model,
                        ContentEmbedding.embedding_model_signature,
                        func.count(ContentEmbedding.id),
                    )
                    .group_by(ContentEmbedding.embedding_model, ContentEmbedding.embedding_model_signature)
                    .order_by(desc(func.count(ContentEmbedding.id)))
                )
            ).all()
        ]
        return {
            "contents_total": int(contents_total),
            "parse_success_total": int(parse_success_total),
            "indexed_total": int(indexed_total),
            "status_counts": status_counts,
            "model_distribution": model_distribution,
        }

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

        units = self._content_embedding_units(content)
        logger.info(f"Indexing {len(units)} semantic units for content_id={content_id}")
        for chunk_index, text_part, media_refs, title in units:
            await self._upsert_embedding(
                session, content_id, chunk_index, title, text_part, media_refs
            )

        if own_session:
            await session.commit()
        else:
            await session.flush()
        return True

    def _content_embedding_units(self, content: Content) -> list[tuple[int, str, list[str], str]]:
        units: list[tuple[int, str, list[str], str]] = []
        global_payload = self._build_content_text(content)
        if global_payload:
            units.append((-1, global_payload, [], "全局摘要"))

        chunks = (content.rich_payload or {}).get("chunks", [])
        if isinstance(chunks, list):
            for idx, chunk in enumerate(chunks):
                if not isinstance(chunk, dict):
                    continue
                text_part = str(chunk.get("content") or "").strip()
                if not text_part:
                    continue
                title = str(chunk.get("title") or f"片段 {idx}")
                media_refs = chunk.get("media_refs") or []
                if not isinstance(media_refs, list):
                    media_refs = []
                units.append((idx, text_part, [str(ref) for ref in media_refs], title))
        return units

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
        model = await self._get_embedding_model()
        
        existing = (
            await session.execute(
                select(ContentEmbedding).where(
                    ContentEmbedding.content_id == content_id,
                    ContentEmbedding.chunk_index == chunk_index
                )
            )
        ).scalar_one_or_none()

        existing_signature = existing.embedding_model_signature or existing.embedding_model if existing else None
        if (
            existing
            and existing.text_hash == text_hash
            and existing_signature == model_signature
            and existing.index_status == "indexed"
        ):
            return

        record = existing or ContentEmbedding(content_id=content_id, chunk_index=chunk_index)
        record.text_hash = text_hash
        record.source_text = text_val[:4000]
        record.chunk_title = chunk_title
        record.embedding_model = model
        record.embedding_model_signature = model_signature
        record.index_status = "pending"
        record.failure_reason = None

        try:
            vector = await self._embed_document_text(text_val, media_refs)
            record.embedding = vector
            record.index_status = "indexed"
            record.last_indexed_at = datetime.utcnow()
            record.indexed_at = record.last_indexed_at
        except Exception as exc:
            record.embedding = []
            record.index_status = "failed"
            record.failure_reason = str(exc)[:1000]
            record.retry_count = int(record.retry_count or 0) + 1
            logger.bind(
                component="embedding",
                content_id=content_id,
                chunk_index=chunk_index,
                model_signature=model_signature,
            ).warning(f"Embedding indexing failed: {exc}")

        if existing is None:
            session.add(record)

    async def _embed_document_text(self, text_val: str, media_refs: list[str]) -> list[float]:
        """Generate a document embedding using the project text-prefix convention."""
        media_note = ""
        if media_refs:
            media_note = "\n媒体引用: " + " ".join(media_refs[:10])
        return await self._embed_text(self._prefix_document(text_val + media_note))


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

        vector_ranked = []
        if await self._has_current_index(session=session, filters=filters):
            query_vec = await self.embed_query(query)
            vector_ranked = await self._vector_rank_ids(
                session=session,
                query_vec=query_vec,
                filters=filters,
                limit=candidate_limit,
            )
        vector_ids = [cid for cid, _, _, _, _ in vector_ranked]
        vector_meta_map = {cid: (score, cidx, ctitle, source_text) for cid, score, cidx, ctitle, source_text in vector_ranked}

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
            cidx, ctitle, source_text = -1, None, None
            
            if in_vector:
                v_score, cidx, ctitle, source_text = vector_meta_map[content_id]
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
                chunk_title=ctitle,
                source_text=source_text,
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

    async def _has_current_index(self, *, session: AsyncSession, filters: list) -> bool:
        model_signature = await self._get_document_embedding_signature()
        stmt = (
            select(ContentEmbedding.id)
            .join(Content, Content.id == ContentEmbedding.content_id)
            .where(
                and_(
                    *filters,
                    ContentEmbedding.embedding_model_signature == model_signature,
                    ContentEmbedding.index_status == "indexed",
                )
            )
            .limit(1)
        )
        return (await session.execute(stmt)).scalar_one_or_none() is not None


    async def _vector_rank_ids(
        self,
        *,
        session: AsyncSession,
        query_vec: list[float],
        filters: list,
        limit: int,
    ) -> list[tuple[int, float, int, Optional[str], Optional[str]]]:
        """
        向量搜索：支持多切片。
        返回: list[(content_id, score, chunk_index, chunk_title)]
        """
        model_signature = await self._get_document_embedding_signature()
        
        model_filters = list(filters)
        model_filters.append(ContentEmbedding.embedding_model_signature == model_signature)
        model_filters.append(ContentEmbedding.index_status == "indexed")
        
        stmt = (
            select(
                ContentEmbedding.content_id, 
                ContentEmbedding.embedding,
                ContentEmbedding.chunk_index,
                ContentEmbedding.chunk_title,
                ContentEmbedding.source_text,
            )
            .join(Content, Content.id == ContentEmbedding.content_id)
            .where(and_(*model_filters))
        )

        row_scan_limit = await self._get_embedding_search_max_rows()
        row_scan_limit = max(limit, row_scan_limit)
        if row_scan_limit > 0:
            stmt = stmt.order_by(ContentEmbedding.indexed_at.desc()).limit(row_scan_limit)
        
        rows = (await session.execute(stmt)).all()
        logger.bind(
            component="semantic_search",
            vector_scan_rows=len(rows),
            vector_scan_limit=row_scan_limit,
        ).debug("Semantic vector scan completed")

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
            results.append((row.content_id, score, row.chunk_index, row.chunk_title, row.source_text))

        # 按分数排序
        results.sort(key=lambda x: x[1], reverse=True)
        
        # 结果去重：同一篇文章如果命中多个 chunk，只保留最高分的那个，但记录 chunk 信息
        seen_content_ids = set()
        unique_results = []
        for cid, score, cidx, ctitle, source_text in results:
            if cid not in seen_content_ids:
                unique_results.append((cid, score, cidx, ctitle, source_text))
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

    async def _embed_text(self, text_value: str) -> list[float]:
        text_value = text_value.strip()
        if not text_value:
            raise RuntimeError("embedding text is empty")

        model = await self._get_embedding_model()
        api_key = await self._get_embedding_api_key()
        output_dimensionality = await self._get_embedding_output_dimensionality()
        if not api_key:
            raise RuntimeError("embedding_api_key is required")

        cache_key = self._hash_text(f"{model}|dim={output_dimensionality}|{text_value}")
        cached = self._EMBED_CACHE.get(cache_key)
        if cached is not None:
            return list(cached)

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
                        output_dimensionality=output_dimensionality,
                    ),
                )

            async with self._REMOTE_SEMAPHORE:
                response = await asyncio.to_thread(_call_gemini)
            vector = response.embeddings[0].values if response.embeddings else None

            if not vector:
                raise RuntimeError("Gemini returned an empty embedding")
            normalized = self._normalize_vector([float(v) for v in vector])
            self._EMBED_CACHE[cache_key] = list(normalized)
            return normalized
        except Exception as e:
            logger.bind(
                component="embedding",
                model=model,
            ).warning(f"Embedding remote call failed: {e}")
            raise

    async def _get_embedding_model(self) -> str:
        model = await get_setting_value("embedding_model")
        if isinstance(model, str) and model.strip():
            normalized = model.strip()
        else:
            normalized = self._SUPPORTED_MODEL
        if normalized != self._SUPPORTED_MODEL:
            raise RuntimeError(f"Only {self._SUPPORTED_MODEL} is supported")
        return normalized

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

    async def _get_embedding_search_max_rows(self) -> int:
        value = await get_setting_value("embedding_search_max_rows", 5000)
        try:
            row_limit = int(value)
        except (TypeError, ValueError):
            return 5000

        if row_limit <= 0:
            return 5000
        return min(row_limit, 100_000)

    async def _get_document_embedding_signature(self) -> str:
        model = await self._get_embedding_model()
        dimension = await self._get_embedding_output_dimensionality()
        return f"{model}|dim={dimension}|prefix={self._SIGNATURE_VERSION}|role=document"

    def _prefix_document(self, text_value: str) -> str:
        return f"VaultStream retrieval document:\n{text_value.strip()}"

    def _prefix_query(self, text_value: str) -> str:
        return f"VaultStream retrieval query:\n{text_value.strip()}"

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
