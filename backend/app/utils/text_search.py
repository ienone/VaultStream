from __future__ import annotations

import re
from typing import Iterable, Sequence

from loguru import logger
from sqlalchemy import and_, or_, select, text
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.sql.elements import ColumnElement

from app.models import Content

_fts_warning_emitted = False


def build_like_condition(query: str, *, columns: Sequence[ColumnElement]) -> ColumnElement:
    terms = _query_terms(query)
    if not terms:
        terms = [query]
    return or_(
        *[
            col.ilike(f"%{term}%")
            for term in terms
            for col in columns
            if term.strip()
        ]
    )


def _query_terms(query: str) -> list[str]:
    raw_parts = [part.strip() for part in re.split(r"\s+", query) if part.strip()]
    terms: list[str] = []
    for part in raw_parts:
        if len(part) >= 2:
            terms.append(part)
        terms.extend(re.findall(r"[A-Za-z0-9][A-Za-z0-9_\-]{1,}", part))
    if not terms and query.strip():
        terms.append(query.strip())
    deduped: list[str] = []
    seen = set()
    for term in terms:
        lowered = term.lower()
        if lowered not in seen:
            deduped.append(term)
            seen.add(lowered)
    return deduped[:12]


def _fts_query(query: str) -> str:
    terms = _query_terms(query)
    if not terms:
        return query
    escaped = [term.replace('"', '""') for term in terms]
    return " OR ".join(f'"{term}"' for term in escaped)


async def fetch_fts_content_ids(
    *,
    session: AsyncSession,
    query: str,
    limit: int | None = None,
) -> list[int]:
    sql = "SELECT content_id FROM contents_fts WHERE contents_fts MATCH :q"
    params: dict = {"q": _fts_query(query)}
    if limit is not None:
        sql += " LIMIT :limit"
        params["limit"] = int(limit)
    global _fts_warning_emitted
    try:
        rows = (await session.execute(text(sql), params)).all()
        return [int(r[0]) for r in rows]
    except Exception as e:
        if not _fts_warning_emitted:
            logger.warning("FTS search unavailable, falling back to LIKE queries: {}", e)
            _fts_warning_emitted = True
        return []


async def build_fts_or_like_condition(
    *,
    session: AsyncSession,
    query: str,
    like_columns: Sequence[ColumnElement],
) -> ColumnElement:
    fts_ids = await fetch_fts_content_ids(session=session, query=query)
    like_cond = build_like_condition(query, columns=like_columns)
    if fts_ids:
        return or_(Content.id.in_(fts_ids), like_cond)
    return like_cond


async def rank_ids_by_fts_or_like(
    *,
    session: AsyncSession,
    query: str,
    filters: Iterable,
    limit: int,
    like_columns: Sequence[ColumnElement],
    order_by: ColumnElement | None = None,
) -> list[int]:
    """
    Return ranked Content IDs using FTS when available, else fallback to LIKE ranking.

    - FTS path: preserve FTS ordering, then apply `filters` by intersecting IDs.
    - Fallback path: query by LIKE over `like_columns` with `filters`, order by `order_by` (default created_at desc).
    """
    try:
        raw_ids = await fetch_fts_content_ids(session=session, query=query, limit=limit)
        if raw_ids:
            filtered_ids = (
                await session.execute(select(Content.id).where(Content.id.in_(raw_ids), and_(*filters)))
            ).scalars().all()
            filtered_set = {int(cid) for cid in filtered_ids}
            ranked = [cid for cid in raw_ids if cid in filtered_set]
            if len(ranked) >= limit:
                return ranked[:limit]
        else:
            ranked = []
    except Exception as e:
        logger.debug("FTS ranking failed, fallback to LIKE ranking: {}", e)
        ranked = []

    like_cond = build_like_condition(query, columns=like_columns)
    if order_by is None:
        order_by = Content.created_at.desc()

    fallback_ids = (
        await session.execute(
            select(Content.id)
            .where(and_(*filters, like_cond))
            .order_by(order_by)
            .limit(int(limit))
        )
    ).scalars().all()
    for cid in fallback_ids:
        cid = int(cid)
        if cid not in ranked:
            ranked.append(cid)
    return ranked[:limit]
