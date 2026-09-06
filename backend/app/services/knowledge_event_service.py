"""User-controlled knowledge-event orchestration."""

from dataclasses import dataclass
from datetime import datetime
from typing import Any

from sqlalchemy import select, update
from sqlalchemy.exc import IntegrityError
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.events import event_bus
from app.core.time_utils import utcnow
from app.models import KnowledgeEvent, KnowledgeEventMember, KnowledgeEventStatus
from app.repositories.knowledge_event_repository import KnowledgeEventRepository
from app.schemas.knowledge_event import (
    KnowledgeEventCreate,
    KnowledgeEventMemberCreate,
    KnowledgeEventMemberUpdate,
    KnowledgeEventUpdate,
)


@dataclass(slots=True)
class KnowledgeEventError(Exception):
    message: str
    code: str
    status_code: int

    def __str__(self) -> str:
        return self.message


class KnowledgeEventService:
    def __init__(self, db: AsyncSession):
        self.db = db
        self.repository = KnowledgeEventRepository(db)

    async def list_events(
        self,
        *,
        page: int,
        size: int,
        status: KnowledgeEventStatus | None,
        content_id: int | None,
    ) -> dict[str, Any]:
        events, total = await self.repository.list_events(
            page=page,
            size=size,
            status=status,
            content_id=content_id,
        )
        return {
            "items": [self._serialize_summary(event) for event in events],
            "total": total,
            "page": page,
            "size": size,
            "has_more": page * size < total,
        }

    async def get_event(self, event_id: int) -> dict[str, Any]:
        event = await self._require_event(event_id)
        return self._serialize_detail(event)

    async def create_event(
        self,
        request: KnowledgeEventCreate,
        *,
        added_by: str = "manual",
    ) -> dict[str, Any]:
        contents = {}
        for member in request.members:
            contents[member.content_id] = await self._require_content(member.content_id)

        now = utcnow()
        event = KnowledgeEvent(
            title=request.title.strip(),
            description=self._optional_text(request.description),
            created_at=now,
            updated_at=now,
            members=[],
        )
        self.repository.add(event)
        for member in request.members:
            event.members.append(
                KnowledgeEventMember(
                    content_id=member.content_id,
                    content=contents[member.content_id],
                    role=member.role,
                    evidence_state=member.evidence_state,
                    note=self._optional_text(member.note),
                    added_by=added_by,
                    added_at=now,
                    updated_at=now,
                )
            )
        await self._commit_or_conflict()
        created = await self._require_event(event.id)
        await self._publish("knowledge_event_created", created, action="created")
        return self._serialize_detail(created)

    async def update_event(
        self,
        event_id: int,
        request: KnowledgeEventUpdate,
    ) -> dict[str, Any]:
        event = await self._require_event(event_id)
        if "title" in request.model_fields_set:
            event.title = request.title.strip() if request.title is not None else event.title
        if "description" in request.model_fields_set:
            event.description = self._optional_text(request.description)
        if "status" in request.model_fields_set and request.status is not None:
            event.status = request.status
        event.updated_at = utcnow()
        await self.db.commit()
        updated = await self._require_event(event.id)
        await self._publish("knowledge_event_updated", updated, action="updated")
        return self._serialize_detail(updated)

    async def add_member(
        self,
        event_id: int,
        request: KnowledgeEventMemberCreate,
        *,
        added_by: str = "manual",
    ) -> dict[str, Any]:
        event = await self._require_event(event_id)
        content = await self._require_content(request.content_id)
        if await self.repository.get_member(event_id, request.content_id) is not None:
            raise KnowledgeEventError(
                "Content already belongs to this event",
                "knowledge_event_member_exists",
                409,
            )

        now = utcnow()
        event.members.append(
            KnowledgeEventMember(
                content_id=request.content_id,
                content=content,
                role=request.role,
                evidence_state=request.evidence_state,
                note=self._optional_text(request.note),
                added_by=added_by,
                added_at=now,
                updated_at=now,
            )
        )
        event.updated_at = now
        await self._commit_or_conflict()
        updated = await self._require_event(event.id)
        await self._publish(
            "knowledge_event_updated",
            updated,
            action="member_added",
            content_id=request.content_id,
        )
        return self._serialize_detail(updated)

    async def update_member(
        self,
        event_id: int,
        content_id: int,
        request: KnowledgeEventMemberUpdate,
    ) -> dict[str, Any]:
        event = await self._require_event(event_id)
        member = await self._require_member(event_id, content_id)
        if "role" in request.model_fields_set and request.role is not None:
            member.role = request.role
        if (
            "evidence_state" in request.model_fields_set
            and request.evidence_state is not None
        ):
            member.evidence_state = request.evidence_state
        if "note" in request.model_fields_set:
            member.note = self._optional_text(request.note)
        now = utcnow()
        member.updated_at = now
        event.updated_at = now
        await self.db.commit()
        updated = await self._require_event(event.id)
        await self._publish(
            "knowledge_event_updated",
            updated,
            action="member_updated",
            content_id=content_id,
        )
        return self._serialize_detail(updated)

    async def remove_member(self, event_id: int, content_id: int) -> dict[str, Any]:
        await self.prepare_member_removal(content_id, event_id=event_id)
        event = await self._require_event(event_id)
        member = await self._require_member(event_id, content_id)
        event.members.remove(member)
        event.updated_at = utcnow()
        await self.db.commit()
        updated = await self._require_event(event.id)
        await self._publish(
            "knowledge_event_updated",
            updated,
            action="member_removed",
            content_id=content_id,
        )
        return {"removed": True, "event_id": event_id, "content_id": content_id}

    async def prepare_member_removal(self, content_id: int, *, event_id: int | None = None) -> None:
        """Serialize membership removals before checking the last evidence.

        Caller commits the same transaction as the membership/content delete.
        Both explicit removal and content CASCADE obey this rule.
        """
        affected = KnowledgeEvent.members.any(KnowledgeEventMember.content_id == content_id)
        statement = update(KnowledgeEvent).where(affected)
        if event_id is not None:
            statement = statement.where(KnowledgeEvent.id == event_id)
        await self.db.execute(statement.values(updated_at=utcnow()))
        missing_evidence = select(KnowledgeEvent.id).where(
            affected,
            ~KnowledgeEvent.members.any(KnowledgeEventMember.content_id != content_id),
        )
        if event_id is not None:
            missing_evidence = missing_evidence.where(KnowledgeEvent.id == event_id)
        if (await self.db.execute(missing_evidence.limit(1))).first() is not None:
            raise KnowledgeEventError(
                "此内容是事件的唯一成员，请先为事件添加另一条内容。",
                "knowledge_event_requires_member",
                409,
            )

    async def _require_event(self, event_id: int) -> KnowledgeEvent:
        event = await self.repository.get_event(event_id)
        if event is None:
            raise KnowledgeEventError(
                "Knowledge event not found",
                "knowledge_event_not_found",
                404,
            )
        return event

    async def _require_content(self, content_id: int):
        content = await self.repository.get_content(content_id)
        if content is None:
            raise KnowledgeEventError(
                "Content not found",
                "knowledge_event_content_not_found",
                404,
            )
        return content

    async def _require_member(
        self,
        event_id: int,
        content_id: int,
    ) -> KnowledgeEventMember:
        member = await self.repository.get_member(event_id, content_id)
        if member is None:
            raise KnowledgeEventError(
                "Knowledge event member not found",
                "knowledge_event_member_not_found",
                404,
            )
        return member

    async def _commit_or_conflict(self) -> None:
        try:
            await self.db.commit()
        except IntegrityError as error:
            await self.db.rollback()
            raise KnowledgeEventError(
                "Content already belongs to this event",
                "knowledge_event_member_exists",
                409,
            ) from error

    async def _publish(
        self,
        event_type: str,
        event: KnowledgeEvent,
        *,
        action: str,
        content_id: int | None = None,
    ) -> None:
        payload = {
            "id": event.id,
            "action": action,
            "status": event.status.value,
            "member_count": len(event.members),
        }
        if content_id is not None:
            payload["content_id"] = content_id
        await event_bus.publish(event_type, payload)

    def _serialize_summary(self, event: KnowledgeEvent) -> dict[str, Any]:
        members = [member for member in event.members if member.content is not None]
        ordered = sorted(members, key=self._member_time)
        return {
            "id": event.id,
            "title": event.title,
            "description": event.description,
            "status": event.status,
            "member_count": len(members),
            "first_occurred_at": self._member_time(ordered[0]) if ordered else None,
            "last_occurred_at": self._member_time(ordered[-1]) if ordered else None,
            "latest_member_title": ordered[-1].content.title if ordered else None,
            "created_at": event.created_at,
            "updated_at": event.updated_at,
        }

    def _serialize_detail(self, event: KnowledgeEvent) -> dict[str, Any]:
        summary = self._serialize_summary(event)
        members = [member for member in event.members if member.content is not None]
        summary["members"] = [
            self._serialize_member(member)
            for member in sorted(members, key=self._member_time)
        ]
        return summary

    @staticmethod
    def _serialize_member(member: KnowledgeEventMember) -> dict[str, Any]:
        content = member.content
        return {
            "id": member.id,
            "content_id": member.content_id,
            "role": member.role,
            "evidence_state": member.evidence_state,
            "note": member.note,
            "added_by": member.added_by,
            "added_at": member.added_at,
            "updated_at": member.updated_at,
            "title": content.title,
            "summary": content.summary,
            "platform": content.platform,
            "url": content.url,
            "published_at": content.published_at,
            "content_created_at": content.created_at or member.added_at,
        }

    @staticmethod
    def _member_time(member: KnowledgeEventMember) -> datetime:
        return member.content.published_at or member.content.created_at or member.added_at

    @staticmethod
    def _optional_text(value: str | None) -> str | None:
        if value is None:
            return None
        normalized = value.strip()
        return normalized or None
