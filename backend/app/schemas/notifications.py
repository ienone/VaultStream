from datetime import datetime
from typing import Any, Literal

from pydantic import BaseModel, ConfigDict, Field

from app.schemas.base import OptionalUtcDatetime, UtcDatetime


NotificationState = Literal["active", "unread", "read", "muted", "snoozed", "all"]
NotificationAction = Literal[
    "read",
    "unread",
    "mute",
    "unmute",
    "snooze",
    "unsnooze",
    "dismiss",
    "restore",
]


class NotificationMessageResponse(BaseModel):
    id: int
    dedupe_key: str
    category: str
    severity: str
    title: str
    body: str | None = None
    route: str | None = None
    source_type: str
    source_id: str | None = None
    payload: dict[str, Any] = Field(default_factory=dict)
    occurrence_count: int
    first_occurred_at: UtcDatetime
    last_occurred_at: UtcDatetime
    read_at: OptionalUtcDatetime
    muted_at: OptionalUtcDatetime
    snoozed_until: OptionalUtcDatetime
    expires_at: OptionalUtcDatetime
    dismissed_at: OptionalUtcDatetime
    is_unread: bool

    model_config = ConfigDict(from_attributes=True)


class NotificationInboxResponse(BaseModel):
    items: list[NotificationMessageResponse]
    total: int
    unread_count: int


class NotificationActionRequest(BaseModel):
    action: NotificationAction
    snoozed_until: datetime | None = None


class NotificationReadAllResponse(BaseModel):
    changed: int


class NotificationDigestResponse(BaseModel):
    created: bool
    window_started_at: UtcDatetime
    window_ended_at: UtcDatetime
    discovery_count: int
    event_count: int
    notification: NotificationMessageResponse | None = None
