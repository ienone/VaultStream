"""Database access for knowledge events and their content membership."""

from sqlalchemy import and_, distinct, func, or_, select
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import selectinload

from app.models import (
    Content,
    KnowledgeEvent,
    KnowledgeEventMember,
    KnowledgeEventStatus,
)


class KnowledgeEventRepository:
    def __init__(self, db: AsyncSession):
        self.db = db

    async def list_events(
        self,
        *,
        page: int,
        size: int,
        status: KnowledgeEventStatus | None,
        content_id: int | None,
    ) -> tuple[list[KnowledgeEvent], int]:
        filters = []
        if status is not None:
            filters.append(KnowledgeEvent.status == status)

        count_statement = select(func.count(distinct(KnowledgeEvent.id))).select_from(
            KnowledgeEvent
        )
        statement = select(KnowledgeEvent)
        if content_id is not None:
            count_statement = count_statement.join(KnowledgeEventMember)
            statement = statement.join(KnowledgeEventMember)
            filters.append(KnowledgeEventMember.content_id == content_id)

        if filters:
            count_statement = count_statement.where(*filters)
            statement = statement.where(*filters)

        total = int((await self.db.execute(count_statement)).scalar() or 0)
        events = (
            (
                await self.db.execute(
                    statement
                    .options(
                        selectinload(KnowledgeEvent.members).selectinload(
                            KnowledgeEventMember.content
                        ).load_only(
                            Content.id, Content.title, Content.published_at, Content.created_at,
                            raiseload=True,
                        )
                    )
                    .order_by(KnowledgeEvent.updated_at.desc(), KnowledgeEvent.id.desc())
                    .offset((page - 1) * size)
                    .limit(size)
                )
            )
            .scalars()
            .unique()
            .all()
        )
        return list(events), total

    async def get_event(self, event_id: int) -> KnowledgeEvent | None:
        return (
            await self.db.execute(
                select(KnowledgeEvent)
                .options(
                    selectinload(KnowledgeEvent.members).selectinload(
                        KnowledgeEventMember.content
                    )
                )
                .where(KnowledgeEvent.id == event_id)
                .execution_options(populate_existing=True)
            )
        ).scalar_one_or_none()

    async def search_events(
        self,
        *,
        query: str,
        limit: int,
    ) -> list[KnowledgeEvent]:
        pattern = f"%{query.casefold()}%"
        content_match = KnowledgeEventMember.content.has(
            and_(
                Content.deleted_at.is_(None),
                or_(
                    func.lower(Content.title).like(pattern),
                    func.lower(Content.summary).like(pattern),
                    func.lower(Content.body).like(pattern),
                ),
            ),
        )
        member_match = KnowledgeEvent.members.any(
            or_(
                func.lower(KnowledgeEventMember.note).like(pattern),
                content_match,
            )
        )
        rows = (
            (
                await self.db.execute(
                    select(KnowledgeEvent)
                    .options(
                        selectinload(KnowledgeEvent.members).selectinload(
                            KnowledgeEventMember.content
                        ).load_only(
                            Content.id, Content.title, Content.published_at, Content.created_at,
                            raiseload=True,
                        )
                    )
                    .where(
                        or_(
                            func.lower(KnowledgeEvent.title).like(pattern),
                            func.lower(KnowledgeEvent.description).like(pattern),
                            member_match,
                        )
                    )
                    .order_by(KnowledgeEvent.updated_at.desc(), KnowledgeEvent.id.desc())
                    .limit(limit)
                )
            )
            .scalars()
            .unique()
            .all()
        )
        return list(rows)

    async def get_content(self, content_id: int) -> Content | None:
        return (
            await self.db.execute(
                select(Content).where(
                    Content.id == content_id,
                    Content.deleted_at.is_(None),
                )
            )
        ).scalar_one_or_none()

    async def get_member(
        self,
        event_id: int,
        content_id: int,
    ) -> KnowledgeEventMember | None:
        return (
            await self.db.execute(
                select(KnowledgeEventMember)
                .options(selectinload(KnowledgeEventMember.content))
                .where(
                    KnowledgeEventMember.event_id == event_id,
                    KnowledgeEventMember.content_id == content_id,
                )
            )
        ).scalar_one_or_none()

    def add(self, value: KnowledgeEvent | KnowledgeEventMember) -> None:
        self.db.add(value)
