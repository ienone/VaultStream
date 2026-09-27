from __future__ import annotations

import asyncio
import hashlib
import math
import time
from dataclasses import dataclass
from datetime import datetime
from typing import Optional

from sqlalchemy import and_, delete, desc, func, select, update
from sqlalchemy.exc import IntegrityError
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm.exc import StaleDataError

from app.core.database import AsyncSessionLocal
from app.core.logging import logger
from app.utils.text_search import rank_ids_by_fts_or_like
from app.models import (
    Content,
    ContentEmbedding,
    ContentStatus,
)
from app.repositories.content_repository import ContentRepository
from app.services.config_service import ConfigService, EmbeddingAIConfig


@dataclass
class SemanticSearchHit:
    content: Content
    score: float
    match_source: str  # vector | fts | hybrid
    chunk_index: int = -1
    chunk_title: Optional[str] = None
    source_text: Optional[str] = None


class EmbeddingIndexError(RuntimeError):
    """Failed chunks were persisted and can be retried."""


class EmbeddingService:
    """
    语义索引与混合检索服务。支持 AI 智能切片与多模态嵌入。
    """

    _RRF_K = 60
    _MAX_BODY_CHARS = 4000
    _SUPPORTED_MODEL = "gemini-embedding-2"
    _DEFAULT_OUTPUT_DIMENSIONALITY = 1536
    _SIGNATURE_VERSION = "vaultstream_rag_v1"
    _REQUEST_BATCH_SIZE = 16
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
        platforms: Optional[list[str]] = None,
        statuses: Optional[list[str]] = None,
        tags: Optional[list[str]] = None,
        author: Optional[str] = None,
        date_from: Optional[datetime] = None,
        date_to: Optional[datetime] = None,
        scope: str = "library",
        session: Optional[AsyncSession] = None,
    ) -> list[SemanticSearchHit]:
        if not query.strip():
            return []

        if session is not None:
            return await self._search_impl(
                query=query,
                top_k=top_k,
                platforms=platforms,
                statuses=statuses,
                tags=tags,
                author=author,
                date_from=date_from,
                date_to=date_to,
                scope=scope,
                session=session,
            )

        async with AsyncSessionLocal() as local_session:
            return await self._search_impl(
                query=query,
                top_k=top_k,
                platforms=platforms,
                statuses=statuses,
                tags=tags,
                author=author,
                date_from=date_from,
                date_to=date_to,
                scope=scope,
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

    async def retry_embedding(
        self,
        embedding_id: int,
        *,
        session: Optional[AsyncSession] = None,
    ) -> dict:
        if session is not None:
            return await self._retry_embedding_impl(embedding_id, session, own_session=False)
        async with AsyncSessionLocal() as local_session:
            return await self._retry_embedding_impl(embedding_id, local_session, own_session=True)

    async def has_current_content_index(
        self,
        content_id: int,
        *,
        session: Optional[AsyncSession] = None,
    ) -> bool:
        if session is not None:
            return await self._has_current_content_index_impl(content_id, session)
        async with AsyncSessionLocal() as local_session:
            return await self._has_current_content_index_impl(content_id, local_session)

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
            stale_units = await self._count_stale_embedding_units(
                session=session,
                content=content,
                model_signature=signature,
            )
            estimated_calls += (stale_units + self._REQUEST_BATCH_SIZE - 1) // self._REQUEST_BATCH_SIZE
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
            try:
                ok = await self._index_content_impl(cid, session, own_session=False)
            except EmbeddingIndexError:
                ok = False
            indexed += int(ok)
            failed += int(not ok)
            # Release the SQLite writer before the next provider request.
            await session.commit()
            if idx % batch_size == 0:
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

    async def _count_stale_embedding_units(
        self,
        *,
        session: AsyncSession,
        content: Content,
        model_signature: str,
    ) -> int:
        units = await self._validated_embedding_units(content, session)
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
        model_signature = await self._get_document_embedding_signature()
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
        status_count_map = {
            str(status or "unknown"): int(count)
            for status, count in raw_status_counts
        }
        status_counts = [{"status": "none", "count": none_count}]
        status_counts.extend(
            {"status": str(status or "unknown"), "count": int(count)}
            for status, count in raw_status_counts
        )
        last_attempt_at = (
            await session.execute(select(func.max(ContentEmbedding.last_attempted_at)))
        ).scalar()
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
        recent_failure_rows = (
            await session.execute(
                select(ContentEmbedding, Content.title)
                .join(Content, Content.id == ContentEmbedding.content_id, isouter=True)
                .where(ContentEmbedding.index_status == "failed")
                .order_by(
                    ContentEmbedding.last_attempted_at.desc().nullslast(),
                    ContentEmbedding.updated_at.desc().nullslast(),
                )
                .limit(10)
            )
        ).all()
        recent_failures = [
            {
                "content_id": row.content_id,
                "title": title,
                "chunk_index": row.chunk_index,
                "chunk_title": row.chunk_title,
                "failure_reason": row.failure_reason,
                "retry_count": int(row.retry_count or 0),
                "last_attempted_at": row.last_attempted_at,
                "updated_at": row.updated_at,
            }
            for row, title in recent_failure_rows
        ]
        return {
            "contents_total": int(contents_total),
            "parse_success_total": int(parse_success_total),
            "indexed_total": int(indexed_total),
            "pending_total": int(status_count_map.get("pending", 0)),
            "failed_total": int(status_count_map.get("failed", 0)),
            "last_attempt_at": last_attempt_at,
            "current_model_signature": model_signature,
            "status_counts": status_counts,
            "model_distribution": model_distribution,
            "recent_failures": recent_failures,
        }

    async def _retry_embedding_impl(
        self,
        embedding_id: int,
        session: AsyncSession,
        *,
        own_session: bool,
    ) -> dict:
        embedding = await session.get(ContentEmbedding, embedding_id)
        if embedding is None:
            raise ValueError("embedding not found")

        content = await session.get(Content, embedding.content_id)
        if content is None or content.status != ContentStatus.PARSE_SUCCESS:
            raise ValueError("content is not ready for semantic indexing")

        units = {
            chunk_index: (text_part, media_refs, title)
            for chunk_index, text_part, media_refs, title in await self._validated_embedding_units(content, session)
        }
        unit = units.get(embedding.chunk_index)
        if unit is None:
            raise ValueError("semantic unit no longer exists")

        text_part, media_refs, title = unit
        source_updated_at = content.updated_at
        with session.no_autoflush:
            failed_units = await self._upsert_embeddings(
                session, content.id, [(embedding.chunk_index, text_part, media_refs, title)],
            )
            if failed_units is None or not await self._lock_current_source(session, content.id, source_updated_at):
                if own_session:
                    await session.rollback()
                raise StaleDataError("原文已变化，请刷新后重新索引")
        await session.flush()
        await session.refresh(embedding)
        if own_session:
            await session.commit()

        return {
            "embedding_id": embedding.id,
            "content_id": embedding.content_id,
            "chunk_index": embedding.chunk_index,
            "chunk_title": embedding.chunk_title,
            "index_status": embedding.index_status,
            "failure_reason": embedding.failure_reason,
            "retry_count": int(embedding.retry_count or 0),
            "last_attempted_at": embedding.last_attempted_at,
            "last_indexed_at": embedding.last_indexed_at,
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

        units = await self._validated_embedding_units(content, session)
        source_updated_at = content.updated_at
        logger.info(f"Indexing {len(units)} semantic units for content_id={content_id}")
        try:
            # Queries for later units must not flush earlier units while we
            # still await remote models: SQLite would hold its sole writer
            # lock throughout those network calls. Persist the set together.
            with session.no_autoflush:
                failed_units = await self._upsert_embeddings(session, content_id, units)
                if failed_units is None:
                    if own_session:
                        await session.rollback()
                    return False

                # Acquire the write transaction only after remote work, and
                # only if the source revision used above is still current.
                if not await self._lock_current_source(session, content_id, source_updated_at):
                    if own_session:
                        await session.rollback()
                        return False
                    raise StaleDataError("Content changed during semantic indexing; rollback required")

            # Reindexing replaces the source's unit set, not just existing rows.
            # Otherwise removed subtitles remain retrievable indefinitely.
            await session.execute(
                delete(ContentEmbedding).where(
                    ContentEmbedding.content_id == content_id,
                    ContentEmbedding.chunk_index.not_in([unit[0] for unit in units]),
                )
            )
            if own_session:
                await session.commit()
            else:
                await session.flush()
        except IntegrityError:
            if not own_session:
                raise
            await session.rollback()
            content_exists = (
                await session.execute(
                    select(Content.id).where(Content.id == content_id)
                )
            ).scalar_one_or_none()
            if content_exists is None:
                logger.bind(component="embedding", content_id=content_id).info(
                    "Content was deleted while semantic indexing was running"
                )
                return False
            raise
        if failed_units:
            raise EmbeddingIndexError(f"{failed_units} 个语义分块索引失败，可重试失败分块")
        return True

    async def _lock_current_source(self, session: AsyncSession, content_id: int, revision: datetime | None) -> bool:
        guard = await session.execute(
            update(Content).where(
                Content.id == content_id,
                Content.status == ContentStatus.PARSE_SUCCESS,
                Content.updated_at == revision,
            ).values(updated_at=Content.updated_at)
            .execution_options(synchronize_session=False)
        )
        return guard.rowcount == 1

    async def _validated_embedding_units(self, content: Content, session: AsyncSession):
        from app.services.document_text import build_document_text_items, document_assets
        chunks = (content.rich_payload or {}).get("chunks", [])
        document_indexes = set()
        if isinstance(chunks, list) and any(isinstance(c, dict) and c.get("source_kind") == "pdf_native_text" for c in chunks):
            document_indexes = {page.chunk_index
                for document in build_document_text_items(content, await document_assets(session, content.id))
                for page in document.pages}
        return self._content_embedding_units(content, document_chunk_indexes=document_indexes)

    def _content_embedding_units(self, content: Content, *, document_chunk_indexes: set[int] | None = None) -> list[tuple[int, str, list[str], str]]:
        units: list[tuple[int, str, list[str], str]] = []
        global_payload = self._build_content_text(content)
        if global_payload:
            units.append((-1, global_payload, [], "全局摘要"))

        # Long source text needs its own complete retrieval coverage; the
        # global overview intentionally caps body length. Negative IDs below
        # -1 cannot collide with source media chunks or imply video timestamps.
        body = (content.body or "").strip()
        if len(body) > self._MAX_BODY_CHARS:
            for part, start in enumerate(range(0, len(body), 1800)):
                text = body[start:start + 2000]
                units.append((-2 - part, text, [], f"正文片段 {part + 1}（字符 {start + 1}–{start + len(text)}）"))
                if start + 2000 >= len(body):
                    break

        chunks = (content.rich_payload or {}).get("chunks", [])
        if isinstance(chunks, list):
            for idx, chunk in enumerate(chunks):
                if not isinstance(chunk, dict):
                    continue
                if chunk.get("source_kind") == "pdf_native_text" and idx not in (document_chunk_indexes or set()):
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

    async def _upsert_embeddings(self, session: AsyncSession, content_id: int, units: list) -> int | None:
        """Batch only stale units; keep source identity and each failure persisted."""
        config = await self._get_embedding_config()
        model = self._normalize_embedding_model(config.model)
        dimension = self._normalize_embedding_output_dimensionality(config.output_dimensionality)
        signature = f"{model}|dim={dimension}|prefix={self._SIGNATURE_VERSION}|role=document"
        existing = {row.chunk_index: row for row in (await session.scalars(
            select(ContentEmbedding).where(ContentEmbedding.content_id == content_id)
        )).all()}
        pending, texts, unchanged = [], [], []
        for index, text, refs, title in units:
            fingerprint = self._hash_text(text + "".join(refs))
            row = existing.get(index)
            if row and row.text_hash == fingerprint and row.embedding_model_signature == signature and row.index_status == "indexed":
                unchanged.append((row, title))
                continue
            pending.append((index, text, title, fingerprint, row))
            media_note = "\n媒体引用: " + " ".join(refs[:10]) if refs else ""
            texts.append(self._prefix_document(text + media_note))
        try:
            results = await self._embed_texts(texts, config)
        except Exception as exc:
            results = [exc] * len(texts)
        if await session.scalar(select(Content.id).where(Content.id == content_id)) is None:
            return None
        for row, title in unchanged:
            row.chunk_title = title
        failures = 0
        for (index, text, title, fingerprint, row), result in zip(pending, results, strict=True):
            record = row or ContentEmbedding(content_id=content_id, chunk_index=index)
            record.text_hash = fingerprint
            record.source_text = text[:4000]
            record.chunk_title = title
            record.embedding_model = model
            record.embedding_model_signature = signature
            record.last_attempted_at = datetime.utcnow()
            if isinstance(result, Exception):
                record.embedding = []
                record.index_status = "failed"
                record.failure_reason = str(result)[:1000]
                record.retry_count = int(record.retry_count or 0) + 1
                failures += 1
            else:
                record.embedding = result
                record.index_status = "indexed"
                record.failure_reason = None
                record.last_indexed_at = record.last_attempted_at
            if row is None:
                session.add(record)
        return failures

    async def _search_impl(
        self,
        *,
        query: str,
        top_k: int,
        platforms: Optional[list[str]],
        statuses: Optional[list[str]],
        tags: Optional[list[str]],
        author: Optional[str],
        date_from: Optional[datetime],
        date_to: Optional[datetime],
        scope: str,
        session: AsyncSession,
    ) -> list[SemanticSearchHit]:
        started_at = time.perf_counter()
        filters = await ContentRepository(session).build_conditions(
            platforms=platforms,
            statuses=statuses or [ContentStatus.PARSE_SUCCESS],
            tags=tags,
            author=author,
            start_date=date_from,
            end_date=date_to,
            scope=scope,
        )
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
            stmt = stmt.order_by(ContentEmbedding.last_indexed_at.desc()).limit(row_scan_limit)
        
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

    async def _has_current_content_index_impl(self, content_id: int, session: AsyncSession) -> bool:
        content = await session.get(Content, content_id)
        if content is None or content.status != ContentStatus.PARSE_SUCCESS:
            return False
        if not await self._validated_embedding_units(content, session):
            return False
        missing = await self._count_stale_embedding_units(
            session=session,
            content=content,
            model_signature=await self._get_document_embedding_signature(),
        )
        return missing == 0

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
        results = await self._embed_texts([text_value], await self._get_embedding_config())
        if isinstance(results[0], Exception):
            raise results[0]
        return results[0]

    async def _embed_texts(self, texts: list[str], config: EmbeddingAIConfig) -> list[list[float] | Exception]:
        if not texts:
            return []
        if not config.api_key:
            raise RuntimeError("embedding_api_key is required")
        if any(not text.strip() for text in texts):
            raise RuntimeError("embedding text is empty")
        from google import genai
        from google.genai import types

        model = self._normalize_embedding_model(config.model)
        dimension = self._normalize_embedding_output_dimensionality(config.output_dimensionality)
        keys = [self._hash_text(f"{model}|dim={dimension}|{text.strip()}") for text in texts]
        missing = {key: text.strip() for key, text in zip(keys, texts) if key not in self._EMBED_CACHE}
        values: dict[str, list[float] | Exception] = {}
        if missing:
            # One client per operation, shared by all batches and always closed.
            async with genai.Client(api_key=config.api_key).aio as client:
                pending = list(missing.items())
                for start in range(0, len(pending), self._REQUEST_BATCH_SIZE):
                    batch = pending[start:start + self._REQUEST_BATCH_SIZE]
                    try:
                        async with self._REMOTE_SEMAPHORE:
                            response = await client.models.embed_content(
                                model=model,
                                # Separate Content objects prevent Embedding 2 from
                                # aggregating multiple source texts into one vector.
                                contents=[types.Content(parts=[types.Part.from_text(text=text)]) for _, text in batch],
                                config=types.EmbedContentConfig(output_dimensionality=dimension),
                            )
                        embeddings = response.embeddings or []
                        if len(embeddings) != len(batch):
                            raise RuntimeError("Gemini 返回的向量数量与输入不一致")
                        for (key, _), embedding in zip(batch, embeddings, strict=True):
                            vector = embedding.values or []
                            if len(vector) != dimension or not all(math.isfinite(v) for v in vector) or not any(vector):
                                values[key] = RuntimeError("Gemini 返回了无效向量")
                            else:
                                normalized = self._normalize_vector(vector)
                                self._EMBED_CACHE[key] = normalized
                                values[key] = normalized
                    except Exception as exc:
                        for key, _ in batch:
                            values[key] = exc
        return [list(self._EMBED_CACHE[key]) if key in self._EMBED_CACHE else values[key] for key in keys]

    async def _get_embedding_config(self) -> EmbeddingAIConfig:
        return await ConfigService().get_embedding_ai_config()

    async def _get_embedding_model(self) -> str:
        config = await self._get_embedding_config()
        return self._normalize_embedding_model(config.model)

    def _normalize_embedding_model(self, model: object) -> str:
        if isinstance(model, str) and model.strip():
            normalized = model.strip()
        else:
            normalized = self._SUPPORTED_MODEL
        if normalized != self._SUPPORTED_MODEL:
            raise RuntimeError(f"Only {self._SUPPORTED_MODEL} is supported")
        return normalized

    async def _get_embedding_api_key(self) -> Optional[str]:
        config = await self._get_embedding_config()
        key = config.api_key
        if isinstance(key, str) and key.strip():
            return key.strip()
        return None

    async def _get_embedding_output_dimensionality(self) -> int:
        config = await self._get_embedding_config()
        return self._normalize_embedding_output_dimensionality(
            config.output_dimensionality
        )

    def _normalize_embedding_output_dimensionality(self, value: object) -> int:
        try:
            dimension = int(value)
        except (TypeError, ValueError):
            return self._DEFAULT_OUTPUT_DIMENSIONALITY

        if 128 <= dimension <= 3072:
            return dimension
        return self._DEFAULT_OUTPUT_DIMENSIONALITY

    async def _get_embedding_search_max_rows(self) -> int:
        config = await self._get_embedding_config()
        return self._normalize_embedding_search_max_rows(config.search_max_rows)

    def _normalize_embedding_search_max_rows(self, value: object) -> int:
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
