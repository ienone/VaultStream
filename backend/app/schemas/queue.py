"""
队列与任务运行态相关的 schemas
"""
from typing import Optional, List
from pydantic import BaseModel, ConfigDict, Field

from app.models.system import QueueItemStatus
from app.schemas.base import UtcDatetime, OptionalUtcDatetime


class ContentQueueItemResponse(BaseModel):
    id: int
    content_id: int
    title: Optional[str] = None
    tags: List[str] = Field(default_factory=list)
    is_nsfw: bool = False
    cover_url: Optional[str] = None
    author_name: Optional[str] = None

    rule_id: int
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


class QueueItemRetryRequest(BaseModel):
    """单个项重试请求"""
    reset_attempts: bool = False


class QueueStatsResponse(BaseModel):
    """分发队列状态统计响应"""
    will_push: int
    filtered: int
    pushed: int
    total: int
    due_now: int


# 为了向后兼容路由中的名称
QueueListResponse = ContentQueueItemListResponse
