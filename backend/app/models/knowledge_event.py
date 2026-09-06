"""Knowledge-event models for evidence-backed cross-content organization."""

from datetime import datetime
from enum import Enum
from typing import Optional

from sqlalchemy import (
    DateTime,
    Enum as SQLEnum,
    ForeignKey,
    Index,
    Integer,
    String,
    Text,
    UniqueConstraint,
)
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.core.time_utils import utcnow
from app.models.base import Base


class KnowledgeEventStatus(str, Enum):
    ACTIVE = "active"
    RESOLVED = "resolved"
    ARCHIVED = "archived"


class KnowledgeEventMemberRole(str, Enum):
    SOURCE = "source"
    REPORT = "report"
    COMMENTARY = "commentary"
    BACKGROUND = "background"
    CORRECTION = "correction"
    EVIDENCE = "evidence"


class KnowledgeEventEvidenceState(str, Enum):
    UNVERIFIED = "unverified"
    CONFIRMED = "confirmed"
    DISPUTED = "disputed"
    VIEWPOINT = "viewpoint"


class KnowledgeEvent(Base):
    """A user-controlled organization view spanning multiple content types."""

    __tablename__ = "knowledge_events"
    __table_args__ = (
        Index("ix_knowledge_events_status_updated", "status", "updated_at"),
    )

    id: Mapped[int] = mapped_column(Integer, primary_key=True, index=True)
    title: Mapped[str] = mapped_column(String(240))
    description: Mapped[Optional[str]] = mapped_column(Text, default=None)
    status: Mapped[KnowledgeEventStatus] = mapped_column(
        SQLEnum(
            KnowledgeEventStatus,
            native_enum=False,
            values_callable=lambda values: [item.value for item in values],
        ),
        default=KnowledgeEventStatus.ACTIVE,
        index=True,
    )
    created_at: Mapped[datetime] = mapped_column(DateTime, default=utcnow)
    updated_at: Mapped[datetime] = mapped_column(
        DateTime,
        default=utcnow,
        onupdate=utcnow,
        index=True,
    )

    members = relationship(
        "KnowledgeEventMember",
        back_populates="event",
        cascade="all, delete-orphan",
        order_by="KnowledgeEventMember.added_at",
    )


class KnowledgeEventMember(Base):
    """One content item and its explicit role inside a knowledge event."""

    __tablename__ = "knowledge_event_members"
    __table_args__ = (
        UniqueConstraint(
            "event_id",
            "content_id",
            name="uq_knowledge_event_member_content",
        ),
        Index("ix_knowledge_event_members_event_added", "event_id", "added_at"),
    )

    id: Mapped[int] = mapped_column(Integer, primary_key=True, index=True)
    event_id: Mapped[int] = mapped_column(
        Integer,
        ForeignKey("knowledge_events.id", ondelete="CASCADE"),
        index=True,
    )
    content_id: Mapped[int] = mapped_column(
        Integer,
        ForeignKey("contents.id", ondelete="CASCADE"),
        index=True,
    )
    role: Mapped[KnowledgeEventMemberRole] = mapped_column(
        SQLEnum(
            KnowledgeEventMemberRole,
            native_enum=False,
            values_callable=lambda values: [item.value for item in values],
        ),
        default=KnowledgeEventMemberRole.SOURCE,
        index=True,
    )
    evidence_state: Mapped[KnowledgeEventEvidenceState] = mapped_column(
        SQLEnum(
            KnowledgeEventEvidenceState,
            native_enum=False,
            values_callable=lambda values: [item.value for item in values],
        ),
        default=KnowledgeEventEvidenceState.UNVERIFIED,
        index=True,
    )
    note: Mapped[Optional[str]] = mapped_column(Text, default=None)
    added_by: Mapped[str] = mapped_column(String(32), default="manual")
    added_at: Mapped[datetime] = mapped_column(DateTime, default=utcnow)
    updated_at: Mapped[datetime] = mapped_column(
        DateTime,
        default=utcnow,
        onupdate=utcnow,
    )

    event = relationship("KnowledgeEvent", back_populates="members")
    content = relationship("Content")
