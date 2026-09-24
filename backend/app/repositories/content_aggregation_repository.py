"""Atomic source-version checks, generated artifacts and workflow progress."""
from dataclasses import dataclass
from datetime import datetime, timedelta
import hashlib
import json

from sqlalchemy import and_, or_, select, update, case

from app.models import (
    Content, ContentSource, ContentStatus, DiscoveryState, KnowledgeEvent,
    KnowledgeEventMember, KnowledgeEventMemberRole, KnowledgeEventEvidenceState,
    LayoutType, Platform, KnowledgeEventStatus,
)
from app.repositories.system_repository import SystemRepository
from app.core.time_utils import utcnow
from app.schemas.content_aggregation import AggregationOutput


@dataclass(frozen=True)
class AggregationInput:
    id: int
    updated_at: datetime
    title: str
    body: str
    canonical_url: str
    is_nsfw: bool


@dataclass(frozen=True)
class AggregationEvent:
    id: int
    title: str
    updated_at: datetime
    source_ids: set[int]


class ContentAggregationRepository:
    def __init__(self, db):
        self.db = db

    @staticmethod
    def _eligible():
        return (
            Content.deleted_at.is_(None), Content.is_synthesis.is_(False),
            Content.status == ContentStatus.PARSE_SUCCESS,
            Content.body.is_not(None), Content.body != "",
            or_(Content.discovery_state.is_(None), Content.discovery_state.not_in([
                DiscoveryState.IGNORED, DiscoveryState.SNOOZED, DiscoveryState.MERGED, DiscoveryState.EXPIRED,
            ])),
        )

    @staticmethod
    def _input(row):
        return AggregationInput(id=row.id, updated_at=row.updated_at, title=row.title or "",
            body=row.body[:6000], canonical_url=row.canonical_url or "", is_nsfw=row.is_nsfw)

    async def select_inputs(self, since: datetime, after_id: int, *, limit: int = 20) -> list[AggregationInput]:
        rows = (await self.db.execute(select(Content).where(*self._eligible(),
            or_(Content.updated_at > since, and_(Content.updated_at == since, Content.id > after_id)),
        ).order_by(Content.updated_at, Content.id).limit(limit))).scalars().all()
        return [self._input(row) for row in rows]

    async def select_context(self, since: datetime, after_id: int, *, reference: datetime, related_source_ids: set[int] | None = None) -> list[AggregationInput]:
        related = Content.id.in_(related_source_ids or set())
        rows = (await self.db.execute(select(Content).where(*self._eligible(),
            or_(related, Content.updated_at >= reference - timedelta(days=7)),
            or_(Content.updated_at < since, and_(Content.updated_at == since, Content.id <= after_id)),
        ).order_by(case((related, 0), else_=1), Content.updated_at.desc(), Content.id.desc()).limit(10))).scalars().all()
        return [self._input(row) for row in rows]

    async def select_events(self, inputs: list[AggregationInput]) -> dict[int, AggregationEvent]:
        candidate_ids = select(KnowledgeEventMember.event_id).where(
            KnowledgeEventMember.content_id.in_([source.id for source in inputs]),
            KnowledgeEventMember.role == KnowledgeEventMemberRole.SOURCE,
        )
        rows = (await self.db.execute(select(KnowledgeEvent, Content).join(
            KnowledgeEventMember, KnowledgeEventMember.event_id == KnowledgeEvent.id,
        ).join(Content, Content.id == KnowledgeEventMember.content_id).where(
            KnowledgeEvent.id.in_(candidate_ids), KnowledgeEvent.status == KnowledgeEventStatus.ACTIVE,
            KnowledgeEventMember.role == KnowledgeEventMemberRole.REPORT,
            Content.source_type == "ai_aggregation", Content.deleted_at.is_(None),
        ).order_by(Content.id.desc()))).all()
        latest = {}
        for event, report in rows:
            if event.id in latest:
                continue
            latest[event.id] = (event, report)
        candidates = {}
        for event, report in list(latest.values())[:10]:
            state = report.context_data if isinstance(report.context_data, dict) else {}
            if state.get("event_updated_at") != event.updated_at.isoformat():
                continue
            source_ids = set((await self.db.execute(select(KnowledgeEventMember.content_id).where(
                KnowledgeEventMember.event_id == event.id,
                KnowledgeEventMember.role == KnowledgeEventMemberRole.SOURCE,
            ))).scalars().all())
            candidates[event.id] = AggregationEvent(event.id, event.title, event.updated_at, source_ids)
        return candidates

    async def save_batch(self, inputs: list[AggregationInput], output: AggregationOutput, *, run_id: str, progress: AggregationInput, events: dict[int, AggregationEvent]) -> tuple[list[int], list[int]]:
        # SQLite obtains the write reservation before checking all versions.
        # A concurrent edit/delete cannot slip between validation and commit.
        for source in inputs:
            result = await self.db.execute(update(Content).where(
                Content.id == source.id, Content.updated_at == source.updated_at,
                Content.deleted_at.is_(None),
            ).values(updated_at=Content.updated_at).execution_options(synchronize_session=False))
            if result.rowcount != 1:
                raise ValueError("聚合期间来源已变化，未保存生成结果")

        by_id = {source.id: source for source in inputs}
        content_ids, event_ids = [], []
        for group in output.groups:
            sources = [by_id[source_id] for source_id in group.source_ids]
            identity = hashlib.sha256(json.dumps([group.event_id, [
                (source.id, source.title, source.body) for source in sorted(sources, key=lambda item: item.id)
            ]], ensure_ascii=False).encode()).hexdigest()
            url = f"vaultstream://aggregation/{identity}"
            existing = (await self.db.execute(select(Content.id).where(
                Content.platform == Platform.UNIVERSAL, Content.canonical_url == url,
            ))).scalar_one_or_none()
            if existing is not None:
                continue
            body = "AI 生成的多来源综合，尚未经人工核实。\n\n"
            for claim in group.claims:
                body += claim.text + "\n\n"
                for evidence in claim.evidence:
                    source = by_id[evidence.content_id]
                    body += f"> {evidence.quote}\n\n"
                    if source.canonical_url.startswith(("https://", "http://")):
                        body += f"[来源 {source.id}]({source.canonical_url})\n\n"
                    else:
                        body += f"来源：收藏 {source.id}\n\n"
            existing_members = set()
            if group.event_id is not None:
                candidate = events[group.event_id]
                changed = await self.db.execute(update(KnowledgeEvent).where(
                    KnowledgeEvent.id == candidate.id, KnowledgeEvent.updated_at == candidate.updated_at,
                    KnowledgeEvent.status == KnowledgeEventStatus.ACTIVE,
                ).values(updated_at=utcnow()).execution_options(synchronize_session=False))
                if changed.rowcount != 1:
                    raise ValueError("聚合期间事件已被修改，未保存生成结果")
                event = await self.db.get(KnowledgeEvent, candidate.id, populate_existing=True)
                existing_members = set((await self.db.execute(select(KnowledgeEventMember.content_id).where(
                    KnowledgeEventMember.event_id == candidate.id,
                ))).scalars().all())
            else:
                event = KnowledgeEvent(title=group.title, description="AI 自动组织的事件，来源关系与综合内容均待人工核实。")
                self.db.add(event)
                await self.db.flush()
            content = Content(
                platform=Platform.UNIVERSAL, url=url, canonical_url=url,
                status=ContentStatus.PARSE_SUCCESS, layout_type=LayoutType.ARTICLE,
                content_type="article", title=group.title, body=body,
                source="content_aggregation", source_type="ai_aggregation", is_synthesis=True,
                is_nsfw=any(source.is_nsfw for source in sources), tags=group.tags,
                context_data={"aggregation_run_id": run_id, "knowledge_event_id": event.id,
                              "source_content_ids": group.source_ids, "event_updated_at": event.updated_at.isoformat()},
            )
            self.db.add(content)
            await self.db.flush()
            self.db.add(ContentSource(content_id=content.id, source="content_aggregation",
                client_context={"run_id": run_id, "source_content_ids": group.source_ids,
                                "evidence": group.model_dump()}))
            for source in sources:
                if source.id in existing_members:
                    continue
                self.db.add(KnowledgeEventMember(event_id=event.id, content_id=source.id,
                    role=KnowledgeEventMemberRole.SOURCE, evidence_state=KnowledgeEventEvidenceState.UNVERIFIED,
                    added_by="workflow"))
            self.db.add(KnowledgeEventMember(event_id=event.id, content_id=content.id,
                role=KnowledgeEventMemberRole.REPORT, evidence_state=KnowledgeEventEvidenceState.UNVERIFIED,
                added_by="workflow", note="AI 生成的综合，不能作为独立来源"))
            content_ids.append(content.id)
            event_ids.append(event.id)
        last = progress
        await SystemRepository(self.db).upsert_setting("content_aggregation_cursor", {
            "updated_at": last.updated_at.isoformat(), "id": last.id,
        }, category="automation")
        return content_ids, event_ids
