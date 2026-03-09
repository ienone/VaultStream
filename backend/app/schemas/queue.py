"""
队列与任务运行态相关的 schemas
"""
from datetime import datetime
from typing import Optional, List, Dict, Any
from datetime import datetime
from pydantic import BaseModel, Field, ConfigDict

from app.models.system import QueueItemStatus
from app.schemas.base import UtcDatetime, OptionalUtcDatetime


class ContentQueueItemResponse(BaseModel):
    id: int
    content_id: int
    rule_id: int
    bot_chat_id: int
    target_platform: str
    target_id: str
    status: QueueItemStatus
    priority: int
    scheduled_at: OptionalUtcDatetime
    
    needs_approval: bool
    approved_at: OptionalUtcDatetime
    approved_by: Optional[str]
    
    attempt_count: int
    max_attempts: int
    next_attempt_at: OptionalUtcDatetime
    
    message_id: Optional[str]
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
    size: int
    has_more: bool

class BatchQueueActionRequest(BaseModel):
    """批量队列操作请求"""
    item_ids: List[int]
    action: str  # "approve", "reject", "retry", "cancel"
    note: Optional[str] = None


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
    pending_review: int
    pushed: int
    total: int
    due_now: int


# 为了向后兼容路由中的名称
QueueListResponse = ContentQueueItemListResponse


