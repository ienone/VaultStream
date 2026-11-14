"""
队列与任务运行态相关的 schemas
"""
from typing import List, Literal, Optional
from pydantic import BaseModel, ConfigDict, Field

from app.models.system import QueueItemStatus
from app.schemas.base import UtcDatetime, OptionalUtcDatetime
from app.schemas.media import MediaAssetManifest


class ContentQueueItemResponse(BaseModel):
    id: int
    content_id: int
    title: Optional[str] = None
    tags: List[str] = Field(default_factory=list)
    is_nsfw: bool = False
    cover_url: Optional[str] = None
    author_name: Optional[str] = None
    media_assets: List[MediaAssetManifest] = Field(default_factory=list)

    rule_id: Optional[int]
    bot_chat_id: int
    source_platform: Optional[str] = None
    target_platform: str
    target_id: str
    status: QueueItemStatus
    priority: int
    scheduled_at: OptionalUtcDatetime

    approved_by: Optional[str]

    attempt_count: int
    max_attempts: int
    next_attempt_at: OptionalUtcDatetime

    message_id: Optional[str]
    reason_code: Optional[str] = None
    last_error: Optional[str]
    last_error_type: Optional[str]
    last_error_at: OptionalUtcDatetime

    started_at: OptionalUtcDatetime
    completed_at: OptionalUtcDatetime
    created_at: UtcDatetime
    updated_at: UtcDatetime
    run_id: Optional[str] = None

    model_config = ConfigDict(from_attributes=True)


class ContentQueueItemListResponse(BaseModel):
    """队列项列表响应"""
    items: List[ContentQueueItemResponse]
    total: int
    page: int = 1
    size: int
    has_more: bool


class BatchQueueRetryRequest(BaseModel):
    """批量队列重试请求"""
    item_ids: Optional[List[int]] = None
    status_filter: Optional[str] = None
    limit: int = 100


class EnqueueContentRequest(BaseModel):
    """内容入队请求"""
    force: bool = False


class QueueStatsResponse(BaseModel):
    """分发队列状态统计响应"""
    will_push: int
    filtered: int
    pushed: int
    total: int
    due_now: int


class QueueEnqueueResponse(BaseModel):
    status: Literal["ok"]
    enqueued_count: int

    model_config = ConfigDict(extra="forbid")


class BatchQueueRetryResponse(BaseModel):
    retried_count: int
    item_ids: List[int] = Field(default_factory=list)

    model_config = ConfigDict(extra="forbid")


class QueueChangedResponse(BaseModel):
    status: Literal["ok"]
    changed: int
    run_id: Optional[str] = None

    model_config = ConfigDict(extra="forbid")


class ManualPushRequest(BaseModel):
    model_config = ConfigDict(extra="forbid")
    content_ids: List[int] = Field(min_length=1, max_length=50)
    bot_chat_ids: List[int] = Field(min_length=1, max_length=10)


class ManualPushResponse(BaseModel):
    item_ids: List[int]
    already_sent: int


class QueueSelection(BaseModel):
    item_ids: List[int] = Field(min_length=1, max_length=500)


class BatchScheduleRequest(QueueSelection):
    start_time: UtcDatetime
    interval_seconds: int = Field(default=0, ge=0)


class QueueSendResult(BaseModel):
    item_id: int
    sent: bool
    error: str | None = None


class BatchQueueSendResponse(BaseModel):
    items: list[QueueSendResult]


class BatchQueueCancelRequest(QueueSelection):
    model_config = ConfigDict(extra="forbid")


class BatchQueueCancelResponse(BaseModel):
    model_config = ConfigDict(extra="forbid")
    canceled_ids: List[int]
