"""Unified search across persisted contents and human-curated knowledge events."""

from dataclasses import dataclass
from datetime import datetime

from sqlalchemy import or_, select, text
from sqlalchemy.ext.asyncio import AsyncSession

from app.models import (
    Content,
    ContentStatus,
    DiscoveryState,
    KnowledgeEvent,
    MediaAsset,
    MediaType,
    Platform,
)
from app.repositories.knowledge_event_repository import KnowledgeEventRepository
from app.services.embedding_service import EmbeddingService, SemanticSearchHit
from app.services.media_segments import extract_media_segments


@dataclass(slots=True)
class UnifiedEventSearchHit:
    event: KnowledgeEvent
    match_source: str


@dataclass(slots=True)
class UnifiedContentFacetHit:
    name: str
    content_count: int
    latest_content_id: int
    latest_content_title: str | None
    latest_at: datetime | None


@dataclass(slots=True)
class UnifiedTimepointSearchHit:
    content_id: int
    content_title: str | None
    media_asset_id: int
    media_type: str
    segment_type: str
    title: str
    excerpt: str
    start_seconds: float
    end_seconds: float | None
    match_source: str
    score: float


@dataclass(slots=True)
class UnifiedSearchResultSet:
    contents: list[SemanticSearchHit]
    events: list[UnifiedEventSearchHit]
    people: list[UnifiedContentFacetHit]
    topics: list[UnifiedContentFacetHit]
    timepoints: list[UnifiedTimepointSearchHit]


class UnifiedSearchService:
    def __init__(self, db: AsyncSession):
        self.db = db

    async def search(
        self,
        *,
        query: str,
        top_k: int,
        kind: str,
        content_scope: str,
        platforms: list[str] | None = None,
        date_from: datetime | None = None,
        date_to: datetime | None = None,
    ) -> UnifiedSearchResultSet:
        contents: list[SemanticSearchHit] = []
        events: list[UnifiedEventSearchHit] = []
        if kind in {"all", "contents", "people", "topics", "timepoints"}:
            contents = await EmbeddingService().search(
                query=query,
                top_k=top_k,
                platforms=platforms,
                date_from=date_from,
                date_to=date_to,
                scope=content_scope,
                session=self.db,
            )
        if kind in {"all", "events"}:
            rows = await KnowledgeEventRepository(self.db).search_events(
                query=query,
                limit=top_k,
            )
            events = [
                UnifiedEventSearchHit(
                    event=event,
                    match_source=self._event_match_source(event, query),
                )
                for event in rows
            ]
        people = []
        if kind in {"all", "people"}:
            people_candidates = self._merge_content_hits(
                contents,
                await self._exact_people_contents(
                    query=query,
                    content_scope=content_scope,
                    platforms=platforms,
                    date_from=date_from,
                    date_to=date_to,
                    limit=max(50, top_k * 6),
                ),
            )
            people = self._content_facets(
                people_candidates,
                attribute="author_name",
                limit=top_k,
            )
        topics = []
        if kind in {"all", "topics"}:
            topic_candidates = self._merge_content_hits(
                contents,
                await self._exact_topic_contents(
                    query=query,
                    content_scope=content_scope,
                    platforms=platforms,
                    date_from=date_from,
                    date_to=date_to,
                    limit=max(50, top_k * 6),
                ),
            )
            topics = self._topic_facets(topic_candidates, limit=top_k)
        timepoints = (
            await self._timepoint_hits(
                contents,
                query=query,
                content_scope=content_scope,
                platforms=platforms,
                date_from=date_from,
                date_to=date_to,
                limit=top_k,
            )
            if kind in {"all", "timepoints"}
            else []
        )
        return UnifiedSearchResultSet(
            contents=contents if kind in {"all", "contents"} else [],
            events=events,
            people=people,
            topics=topics,
            timepoints=timepoints,
        )

    @staticmethod
    def _event_match_source(event: KnowledgeEvent, query: str) -> str:
        needle = query.casefold()
        if needle in event.title.casefold():
            return "title"
        if event.description and needle in event.description.casefold():
            return "description"
        return "member"

    @staticmethod
    def _content_facets(
        hits: list[SemanticSearchHit],
        *,
        attribute: str,
        limit: int,
    ) -> list[UnifiedContentFacetHit]:
        grouped: dict[str, UnifiedContentFacetHit] = {}
        for hit in hits:
            content = hit.content
            name = str(getattr(content, attribute, "") or "").strip()
            if not name:
                continue
            key = name.casefold()
            occurred_at = content.published_at or content.created_at
            current = grouped.get(key)
            if current is None:
                grouped[key] = UnifiedContentFacetHit(
                    name=name,
                    content_count=1,
                    latest_content_id=content.id,
                    latest_content_title=content.title,
                    latest_at=occurred_at,
                )
                continue
            current.content_count += 1
            if UnifiedSearchService._is_later(occurred_at, current.latest_at):
                current.latest_content_id = content.id
                current.latest_content_title = content.title
                current.latest_at = occurred_at
        return UnifiedSearchService._sort_content_facets(grouped.values(), limit)

    @staticmethod
    def _topic_facets(
        hits: list[SemanticSearchHit],
        *,
        limit: int,
    ) -> list[UnifiedContentFacetHit]:
        grouped: dict[str, UnifiedContentFacetHit] = {}
        for hit in hits:
            content = hit.content
            occurred_at = content.published_at or content.created_at
            seen_for_content: set[str] = set()
            for raw_tag in content.tags or []:
                name = str(raw_tag or "").strip()
                key = name.casefold()
                if not name or key in seen_for_content:
                    continue
                seen_for_content.add(key)
                current = grouped.get(key)
                if current is None:
                    grouped[key] = UnifiedContentFacetHit(
                        name=name,
                        content_count=1,
                        latest_content_id=content.id,
                        latest_content_title=content.title,
                        latest_at=occurred_at,
                    )
                    continue
                current.content_count += 1
                if UnifiedSearchService._is_later(occurred_at, current.latest_at):
                    current.latest_content_id = content.id
                    current.latest_content_title = content.title
                    current.latest_at = occurred_at
        return UnifiedSearchService._sort_content_facets(grouped.values(), limit)

    async def _timepoint_hits(
        self,
        hits: list[SemanticSearchHit],
        *,
        query: str,
        content_scope: str,
        platforms: list[str] | None,
        date_from: datetime | None,
        date_to: datetime | None,
        limit: int,
    ) -> list[UnifiedTimepointSearchHit]:
        candidates = list(hits)
        seen_content_ids = {hit.content.id for hit in candidates}
        for content in await self._exact_timepoint_contents(
            query=query,
            content_scope=content_scope,
            platforms=platforms,
            date_from=date_from,
            date_to=date_to,
            limit=max(50, limit * 6),
        ):
            if content.id in seen_content_ids:
                continue
            candidates.append(
                SemanticSearchHit(
                    content=content,
                    score=0.0,
                    match_source="fts",
                )
            )
            seen_content_ids.add(content.id)
        content_ids = [hit.content.id for hit in candidates]
        if not content_ids:
            return []
        assets = (
            await self.db.execute(
                select(MediaAsset).where(
                    MediaAsset.content_id.in_(content_ids),
                    MediaAsset.media_type.in_([MediaType.AUDIO, MediaType.VIDEO]),
                )
            )
        ).scalars().all()
        needle = query.casefold().strip()
        results: list[UnifiedTimepointSearchHit] = []
        for hit in candidates:
            content = hit.content
            for segment in extract_media_segments(
                content_id=content.id,
                rich_payload=content.rich_payload,
                assets=assets,
            ):
                text_matches = bool(needle) and needle in (
                    f"{segment.title}\n{segment.excerpt}".casefold()
                )
                semantic_matches = (
                    segment.chunk_index == hit.chunk_index
                    and hit.match_source in {"vector", "hybrid"}
                )
                if not text_matches and not semantic_matches:
                    continue
                results.append(
                    UnifiedTimepointSearchHit(
                        content_id=content.id,
                        content_title=content.title,
                        media_asset_id=segment.media_asset_id,
                        media_type=segment.media_type.value,
                        segment_type=segment.segment_type,
                        title=segment.title,
                        excerpt=segment.excerpt,
                        start_seconds=segment.start_seconds,
                        end_seconds=segment.end_seconds,
                        match_source=hit.match_source if semantic_matches else "text",
                        score=float(hit.score),
                    )
                )
        results.sort(
            key=lambda item: (-item.score, item.content_id, item.start_seconds)
        )
        return results[:limit]

    async def _exact_timepoint_contents(
        self,
        *,
        query: str,
        content_scope: str,
        platforms: list[str] | None,
        date_from: datetime | None,
        date_to: datetime | None,
        limit: int,
    ) -> list[Content]:
        needle = query.strip()
        if not needle:
            return []
        return list(
            (
                await self.db.execute(
                    select(Content)
                    .where(
                        *self._content_filters(
                            content_scope=content_scope,
                            platforms=platforms,
                            date_from=date_from,
                            date_to=date_to,
                        ),
                        text("""EXISTS (
                        SELECT 1 FROM json_each(contents.rich_payload, '$.chunks') AS chunk
                        WHERE json_extract(chunk.value, '$.segment_type') IN ('chapter', 'transcript')
                          AND json_type(chunk.value, '$.media_asset_id') = 'integer'
                          AND json_type(chunk.value, '$.start_seconds') IN ('integer', 'real')
                          AND (
                            instr(lower(COALESCE(json_extract(chunk.value, '$.title'), '')), lower(:query)) > 0
                            OR instr(lower(COALESCE(json_extract(chunk.value, '$.content'), '')), lower(:query)) > 0
                          )
                    )"""),
                    )
                    .order_by(Content.updated_at.desc(), Content.id.desc())
                    .limit(limit)
                    .params(query=needle)
                )
            ).scalars()
        )

    async def _exact_people_contents(
        self,
        *,
        query: str,
        content_scope: str,
        platforms: list[str] | None,
        date_from: datetime | None,
        date_to: datetime | None,
        limit: int,
    ) -> list[Content]:
        needle = query.strip()
        if not needle:
            return []
        return list(
            (
                await self.db.execute(
                    select(Content)
                    .where(
                        *self._content_filters(
                            content_scope=content_scope,
                            platforms=platforms,
                            date_from=date_from,
                            date_to=date_to,
                        ),
                        Content.author_name.icontains(needle, autoescape=True),
                    )
                    .order_by(Content.updated_at.desc(), Content.id.desc())
                    .limit(limit)
                )
            ).scalars()
        )

    async def _exact_topic_contents(
        self,
        *,
        query: str,
        content_scope: str,
        platforms: list[str] | None,
        date_from: datetime | None,
        date_to: datetime | None,
        limit: int,
    ) -> list[Content]:
        needle = query.strip()
        if not needle:
            return []
        return list(
            (
                await self.db.execute(
                    select(Content)
                    .where(
                        *self._content_filters(
                            content_scope=content_scope,
                            platforms=platforms,
                            date_from=date_from,
                            date_to=date_to,
                        ),
                        text("""EXISTS (
                        SELECT 1 FROM json_each(contents.tags) AS tag
                        WHERE instr(lower(CAST(tag.value AS TEXT)), lower(:query)) > 0
                    )"""),
                    )
                    .order_by(Content.updated_at.desc(), Content.id.desc())
                    .limit(limit)
                    .params(query=needle)
                )
            ).scalars()
        )

    @staticmethod
    def _merge_content_hits(
        hits: list[SemanticSearchHit],
        exact_contents: list[Content],
    ) -> list[SemanticSearchHit]:
        merged = list(hits)
        seen_content_ids = {hit.content.id for hit in merged}
        for content in exact_contents:
            if content.id in seen_content_ids:
                continue
            merged.append(
                SemanticSearchHit(
                    content=content,
                    score=0.0,
                    match_source="fts",
                )
            )
            seen_content_ids.add(content.id)
        return merged

    @staticmethod
    def _content_scope_filter(content_scope: str):
        active_discovery_states = [
            DiscoveryState.INGESTED,
            DiscoveryState.SCORED,
            DiscoveryState.VISIBLE,
        ]
        if content_scope == "discovery":
            return Content.discovery_state.in_(active_discovery_states)
        if content_scope == "all":
            return or_(
                Content.discovery_state.is_(None),
                Content.discovery_state == DiscoveryState.PROMOTED,
                Content.discovery_state.in_(active_discovery_states),
            )
        return or_(
            Content.discovery_state.is_(None),
            Content.discovery_state == DiscoveryState.PROMOTED,
        )

    @classmethod
    def _content_filters(
        cls,
        *,
        content_scope: str,
        platforms: list[str] | None,
        date_from: datetime | None,
        date_to: datetime | None,
    ) -> list:
        filters = [
            Content.status == ContentStatus.PARSE_SUCCESS,
            cls._content_scope_filter(content_scope),
        ]
        if platforms:
            filters.append(
                Content.platform.in_([Platform(platform) for platform in platforms])
            )
        if date_from is not None:
            filters.append(Content.created_at >= date_from)
        if date_to is not None:
            filters.append(Content.created_at <= date_to)
        return filters

    @staticmethod
    def _sort_content_facets(
        facets,
        limit: int,
    ) -> list[UnifiedContentFacetHit]:
        return sorted(
            facets,
            key=lambda item: (
                item.content_count,
                item.latest_at or datetime.min,
                item.name.casefold(),
            ),
            reverse=True,
        )[:limit]

    @staticmethod
    def _is_later(candidate: datetime | None, current: datetime | None) -> bool:
        if candidate is None:
            return False
        return current is None or candidate > current
