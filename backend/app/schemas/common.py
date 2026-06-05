"""
通用的 schema 定义与基类模型
"""
from datetime import datetime
from typing import Optional, List, Dict, Any
from pydantic import BaseModel, Field, ConfigDict
from app.models import Platform, ContentStatus, ReviewStatus, LayoutType
from app.schemas.base import OptionalUtcDatetime, UtcDatetime

class APIResponse(BaseModel):
    """标准的 API 响应包裹体（如需扩展）"""
    code: int = 200
    message: str = "success"
    data: Optional[Any] = None

class TagStats(BaseModel):
    """标签统计"""
    name: str
    count: int

class QueueStats(BaseModel):
    """队列统计"""
    unprocessed: int
    processing: int
    parse_success: int
    parse_failed: int
    total: int

class DistributionStatusStats(BaseModel):
    """解析成功后进入分发阶段的状态统计"""
    will_push: int
    filtered: int
    pushed: int
    total: int

class DashboardStats(BaseModel):
    """仪表盘数据"""
    platform_counts: Dict[str, int]
    daily_growth: List[Dict[str, Any]]
    storage_usage_bytes: int


class QueueOverviewStats(BaseModel):
    """看板队列总览统计（解析+分发）"""
    parse: QueueStats
    distribution: DistributionStatusStats


class BackgroundTaskStateResponse(BaseModel):
    """Background task runtime state exported from system_settings."""

    task: str
    status: str
    last_started_at: Optional[str] = None
    last_success_at: Optional[str] = None
    last_error_at: Optional[str] = None
    last_error: Optional[str] = None
    run_count: int = 0
    error_count: int = 0
    metrics: Dict[str, Any] = Field(default_factory=dict)


class FailedParseTaskResponse(BaseModel):
    """Failed parse task detail for diagnostics pages."""

    id: int
    task_type: str
    content_id: Optional[int] = None
    retry_count: int
    max_retries: int
    retryable: bool
    last_error: Optional[str] = None
    created_at: OptionalUtcDatetime
    started_at: OptionalUtcDatetime
    completed_at: OptionalUtcDatetime


class FailedDistributionQueueItemResponse(BaseModel):
    """Failed distribution queue detail with retry status."""

    id: int
    content_id: int
    title: Optional[str] = None
    target_platform: str
    target_id: str
    attempt_count: int
    max_attempts: int
    retryable: bool
    next_attempt_at: OptionalUtcDatetime
    last_error: Optional[str] = None
    last_error_type: Optional[str] = None
    last_error_at: OptionalUtcDatetime
    updated_at: UtcDatetime


class FailedDiscoverySourceResponse(BaseModel):
    """Discovery source with last sync error."""

    id: int
    name: str
    kind: str
    enabled: bool
    last_sync_at: OptionalUtcDatetime
    last_error: Optional[str] = None


class BackgroundTaskRunResponse(BaseModel):
    """Recent background task run with task-specific metadata."""

    run_id: str
    task: str
    status: str
    started_at: OptionalUtcDatetime = None
    finished_at: OptionalUtcDatetime = None
    error: Optional[str] = None
    result: Optional[Dict[str, Any]] = None

    model_config = ConfigDict(extra="allow")


class BackgroundTaskDiagnosticsResponse(BaseModel):
    """Detailed backend diagnostics for failed background work."""

    summary: Dict[str, Any]
    task_states: List[BackgroundTaskStateResponse]
    recent_task_runs: List[BackgroundTaskRunResponse]
    failed_parse_tasks: List[FailedParseTaskResponse]
    failed_distribution_items: List[FailedDistributionQueueItemResponse]
    failed_discovery_sources: List[FailedDiscoverySourceResponse]


class SystemSettingBase(BaseModel):
    """系统设置基础"""
    value: Any
    category: Optional[str] = "general"
    description: Optional[str] = None


class SystemSettingUpdate(BaseModel):
    """更新系统设置"""
    value: Any
    description: Optional[str] = None


class SystemSettingResponse(SystemSettingBase):
    """系统设置响应"""
    key: str
    updated_at: UtcDatetime

    model_config = ConfigDict(from_attributes=True)


class FavoritesSyncTriggerRequest(BaseModel):
    """Manual favorites sync trigger payload."""

    platform: Optional[str] = None


class FavoritesSyncPreviewRequest(BaseModel):
    """Favorites sync preview payload."""

    platform: Optional[str] = None


class FavoritesSyncItemRetryRequest(BaseModel):
    """Retry importing one failed favorites item."""

    platform: str = Field(..., min_length=1)
    url: str = Field(..., min_length=1)
    title: Optional[str] = None
    item_id: Optional[str] = None
    source_run_id: Optional[str] = None


class FavoritesSyncPlatformPreview(BaseModel):
    """Read-only preview of one platform favorites sync round."""

    platform: str
    status: str
    authenticated: bool = False
    max_items: int
    cursor_present: bool = False
    fetched: int = 0
    unique: int = 0
    existing: int = 0
    estimated_new: int = 0
    skipped: int = 0
    next_cursor_available: bool = False
    error: Optional[str] = None
    error_code: Optional[str] = None
    error_message: Optional[str] = None
    error_hint: Optional[str] = None
    retryable: bool = False
    auth_required: bool = False
    items: List[Dict[str, Any]] = Field(default_factory=list)


class FavoritesSyncPreviewResponse(BaseModel):
    """Read-only preview of a favorites sync trigger."""

    platform: str
    status: str
    fetched: int = 0
    unique: int = 0
    existing: int = 0
    estimated_new: int = 0
    skipped: int = 0
    platforms: List[FavoritesSyncPlatformPreview] = Field(default_factory=list)


class StorageStatsResponse(BaseModel):
    """存储统计响应"""
    total_bytes: int
    media_count: int
    by_platform: Dict[str, int]
    by_type: Dict[str, int]

class PushedRecordResponse(BaseModel):
    """推送记录响应"""
    id: int
    content_id: int
    target_platform: str
    target_id: str
    message_id: Optional[str] = None
    push_status: str
    error_message: Optional[str] = None
    pushed_at: UtcDatetime
    
    model_config = ConfigDict(from_attributes=True)
