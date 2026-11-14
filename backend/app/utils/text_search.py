from __future__ import annotations

import re
from typing import Iterable, Sequence

from sqlalchemy import column, or_, select, table
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.sql.elements import ColumnElement

from app.models import Content



def build_like_condition(query: str, *, columns: Sequence[ColumnElement]) -> ColumnElement:
    terms = _query_terms(query)
    if not terms:
        terms = [query]
    return or_(
        *[
            col.icontains(term, autoescape=True)
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


_FTS = table("contents_fts", column("rowid"), column("rank"))


def build_fts_or_like_condition(*, query: str, like_columns: Sequence[ColumnElement]) -> ColumnElement:
    matches = select(_FTS.c.rowid).where(column("contents_fts").match(_fts_query(query)))
    return or_(Content.id.in_(matches), build_like_condition(query, columns=like_columns))


async def rank_ids_by_fts_or_like(
    *, session: AsyncSession, query: str, filters: Iterable, limit: int,
    like_columns: Sequence[ColumnElement], order_by: ColumnElement | None = None,
) -> list[int]:
    ranked = list(await session.scalars(
        select(Content.id).join(_FTS, _FTS.c.rowid == Content.id)
        .where(column("contents_fts").match(_fts_query(query)), *filters)
        .order_by(_FTS.c.rank, Content.id).limit(limit)
    ))
    remaining = limit - len(ranked)
    if remaining:
        fallback = select(Content.id).where(*filters, build_like_condition(query, columns=like_columns))
        if ranked:
            fallback = fallback.where(Content.id.not_in(ranked))
        fallback = fallback.order_by(order_by if order_by is not None else Content.created_at.desc(), Content.id)
        ranked.extend(await session.scalars(fallback.limit(remaining)))
    return ranked
