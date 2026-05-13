from __future__ import annotations

from typing import Iterable, Sequence

from loguru import logger
from sqlalchemy import and_, or_, select, text
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.sql.elements import ColumnElement

from app.models import Content

_fts_warning_emitted = False


def build_like_condition(query: str, *, columns: Sequence[ColumnElement]) -> ColumnElement:
    like_expr = f"%{query}%"
    return or_(*[col.ilike(like_expr) for col in columns])


async def fetch_fts_content_ids(
    *,
    session: AsyncSession,
    query: str,
    limit: int | None = None,
) -> list[int]:
    sql = "SELECT content_id FROM contents_fts WHERE contents_fts MATCH :q"
    params: dict = {"q": query}
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
            return [cid for cid in raw_ids if cid in filtered_set]
    except Exception as e:
        logger.debug("FTS ranking failed, fallback to LIKE ranking: {}", e)

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
    return [int(cid) for cid in fallback_ids]
