"""Typed API contract for evidence-backed knowledge events."""

from datetime import datetime
from typing import Literal

from pydantic import BaseModel, ConfigDict, Field, model_validator

from app.models import (
    KnowledgeEventEvidenceState,
    KnowledgeEventMemberRole,
    KnowledgeEventStatus,
    Platform,
)
from app.schemas.base import OptionalUtcDatetime, UtcDatetime


class KnowledgeEventMemberCreate(BaseModel):
    content_id: int = Field(gt=0)
    role: KnowledgeEventMemberRole = KnowledgeEventMemberRole.SOURCE
    evidence_state: KnowledgeEventEvidenceState = KnowledgeEventEvidenceState.UNVERIFIED
    note: str | None = Field(default=None, max_length=2000)

    model_config = ConfigDict(str_strip_whitespace=True)


class KnowledgeEventCreate(BaseModel):
    title: str = Field(min_length=1, max_length=240)
    description: str | None = Field(default=None, max_length=4000)
    members: list[KnowledgeEventMemberCreate] = Field(min_length=1, max_length=100)

    model_config = ConfigDict(str_strip_whitespace=True)

    @model_validator(mode="after")
    def validate_unique_members(self):
        content_ids = [member.content_id for member in self.members]
        if len(content_ids) != len(set(content_ids)):
            raise ValueError("event members must reference unique content ids")
        return self


class KnowledgeEventUpdate(BaseModel):
    title: str | None = Field(default=None, min_length=1, max_length=240)
    description: str | None = Field(default=None, max_length=4000)
    status: KnowledgeEventStatus | None = None

    model_config = ConfigDict(str_strip_whitespace=True)

    @model_validator(mode="after")
    def validate_change(self):
        if not self.model_fields_set:
            raise ValueError("at least one event field is required")
        return self


class KnowledgeEventMemberUpdate(BaseModel):
    role: KnowledgeEventMemberRole | None = None
    evidence_state: KnowledgeEventEvidenceState | None = None
    note: str | None = Field(default=None, max_length=2000)

    model_config = ConfigDict(str_strip_whitespace=True)

    @model_validator(mode="after")
    def validate_change(self):
        if not self.model_fields_set:
            raise ValueError("at least one member field is required")
        return self


class KnowledgeEventMemberResponse(BaseModel):
    id: int
    content_id: int
    role: KnowledgeEventMemberRole
    evidence_state: KnowledgeEventEvidenceState
    note: str | None
    added_by: str
    added_at: UtcDatetime
    updated_at: UtcDatetime
    title: str | None
    summary: str | None
    platform: Platform
    url: str
    published_at: OptionalUtcDatetime
    content_created_at: UtcDatetime

    model_config = ConfigDict(from_attributes=True)


class KnowledgeEventSummaryResponse(BaseModel):
    id: int
    title: str
    description: str | None
    status: KnowledgeEventStatus
    member_count: int
    first_occurred_at: datetime | None
    last_occurred_at: datetime | None
    latest_member_title: str | None
    created_at: UtcDatetime
    updated_at: UtcDatetime


class KnowledgeEventDetailResponse(KnowledgeEventSummaryResponse):
    members: list[KnowledgeEventMemberResponse]


class KnowledgeEventListResponse(BaseModel):
    items: list[KnowledgeEventSummaryResponse]
    total: int
    page: int
    size: int
    has_more: bool


class KnowledgeEventMemberRemoveResponse(BaseModel):
    removed: Literal[True]
    event_id: int
    content_id: int
