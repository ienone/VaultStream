"""
内容相关 schemas
"""
from datetime import datetime
from enum import Enum
from typing import Optional, List, Dict, Any
from pydantic import BaseModel, Field, field_validator, ConfigDict
import json

from app.models import Platform, ContentStatus, ReviewStatus, LayoutType
from app.schemas.base import UtcDatetime, OptionalUtcDatetime
from app.schemas.media import MediaAssetManifest

NOTE_MAX_LENGTH = 2000 # 备注内容的最大长度
CLIENT_CONTEXT_MAX_BYTES = 4096 # JSON序列化后最大4KB

class ShareRequest(BaseModel):
    """分享请求"""
    url: str = Field(..., description="要分享的URL")
    tags: List[str] = Field(default_factory=list, description="标签列表")
    tags_text: Optional[str] = Field(None, description="原始标签输入文本（后端统一拆分清洗）")
    source: Optional[str] = Field(None, description="来源标识")
    note: Optional[str] = Field(None, description="备注", max_length=NOTE_MAX_LENGTH)
    client_context: Optional[Dict[str, Any]] = Field(None, description="客户端上下文（可选）")
    is_nsfw: bool = Field(default=False, description="是否为NSFW内容")
    layout_type_override: Optional[LayoutType] = Field(None, description="强制指定的布局类型")

    @field_validator("client_context")
    @classmethod
    def validate_client_context_size(cls, v: Optional[Dict[str, Any]]):
        if v is None:
            return v
        try:
            payload = json.dumps(v, ensure_ascii=False, separators=(",", ":")).encode("utf-8")
        except Exception as e:
            raise ValueError(f"client_context 序列化失败: {e}")
        if len(payload) > CLIENT_CONTEXT_MAX_BYTES: 
            raise ValueError(f"client_context 太大 (> {CLIENT_CONTEXT_MAX_BYTES} 字节)") 
        return v


class ShareResponse(BaseModel):
    """分享响应"""
    id: int
    platform: Platform
    url: str
    status: ContentStatus
    created_at: UtcDatetime
    
    model_config = ConfigDict(from_attributes=True)


class ContentDetail(BaseModel):
    """内容详情"""
    id: int
    platform: Platform
    url: str
    clean_url: Optional[str]
    status: ContentStatus
    
    failure_count: int = 0
    last_error_type: Optional[str] = None
    last_error: Optional[str] = None
    
    queue_priority: int = 0
    
    tags: List[str] = Field(default_factory=list)
    is_nsfw: bool = False
    source: Optional[str] = None
    ai_score: Optional[float] = None
    
    platform_id: Optional[str] = None
    
    view_count: int = 0
    like_count: int = 0
    collect_count: int = 0
    share_count: int = 0
    comment_count: int = 0
    
    title: Optional[str] = None
    body: Optional[str] = None
    summary: Optional[str] = None
    author_name: Optional[str] = None
    author_id: Optional[str] = None
    author_avatar_url: Optional[str] = None
    author_url: Optional[str] = None
    cover_url: Optional[str] = None
    source_tags: List[str] = Field(default_factory=list)
    
    cover_color: Optional[str] = None
    media_urls: List[str] = Field(default_factory=list)
    media_assets: List[MediaAssetManifest] = Field(
        default_factory=list,
        validation_alias="media_asset_manifests",
    )
    extra_stats: Dict[str, Any] = Field(default_factory=dict)
    
    review_status: ReviewStatus = ReviewStatus.PENDING
    reviewed_at: OptionalUtcDatetime = None
    reviewed_by: Optional[str] = None
    review_note: Optional[str] = None

    content_type: Optional[str] = None  # 平台原生内容类型，模板细分依据
    layout_type: Optional[LayoutType] = None
    layout_type_override: Optional[LayoutType] = None
    effective_layout_type: Optional[str] = None  # 计算字段：frontend 读取此字段

    context_data: Optional[Dict[str, Any]] = None
    rich_payload: Optional[Dict[str, Any]] = None
    
    created_at: UtcDatetime
    updated_at: UtcDatetime
    published_at: OptionalUtcDatetime
    
    model_config = ConfigDict(from_attributes=True)


class ContentListItem(BaseModel):
    """内容列表项（精简版）"""
    id: int
    platform: Platform
    url: str
    status: ContentStatus
    title: Optional[str] = None
    cover_url: Optional[str] = None
    thumbnail_url: Optional[str] = None
    author_name: Optional[str] = None
    tags: List[str] = Field(default_factory=list)
    is_nsfw: bool = False
    layout_type: Optional[str] = None
    created_at: UtcDatetime
    published_at: OptionalUtcDatetime = None

    model_config = ConfigDict(from_attributes=True)


class ContentListResponse(BaseModel):
    items: List[ContentDetail]
    total: int
    page: int
    size: int
    has_more: bool


class ContentListItemResponse(BaseModel):
    items: List[ContentListItem]
    total: int
    page: int
    size: int
    has_more: bool


class ContentUpdate(BaseModel):
    """内容修改请求"""
    tags: Optional[List[str]] = None
    title: Optional[str] = None
    body: Optional[str] = None
    summary: Optional[str] = None
    author_name: Optional[str] = None
    cover_url: Optional[str] = None
    is_nsfw: Optional[bool] = None
    status: Optional[ContentStatus] = None
    review_status: Optional[ReviewStatus] = None
    review_note: Optional[str] = None
    reviewed_by: Optional[str] = None
    layout_type_override: Optional[LayoutType] = None


class BatchReviewRequest(BaseModel):
    """批量审批请求"""
    content_ids: List[int] = Field(..., min_items=1)
    action: str = Field(..., description="approve/reject")
    note: Optional[str] = None
    reviewed_by: Optional[str] = None


class ReviewAction(BaseModel):
    """审批操作"""
    action: str = Field(..., description="approve/reject")
    note: Optional[str] = Field(None, description="审批备注")
    reviewed_by: Optional[str] = Field(None, description="审批人")


class ShareCard(BaseModel):
    """合规分享卡片（对外输出用）- 轻量级列表展示。"""
    id: int
    platform: Platform
    url: str
    status: Optional[ContentStatus] = None
    clean_url: Optional[str] = None
    content_type: Optional[str] = None
    effective_layout_type: Optional[str] = None
    title: Optional[str] = None
    author_name: Optional[str] = None
    author_id: Optional[str] = None
    author_avatar_url: Optional[str] = None
    cover_url: Optional[str] = None
    thumbnail_url: Optional[str] = None
    media_assets: List[MediaAssetManifest] = Field(
        default_factory=list,
        validation_alias="media_asset_manifests",
    )
    cover_color: Optional[str] = None
    tags: List[str] = Field(default_factory=list)
    is_nsfw: bool = False
    review_status: Optional[ReviewStatus] = None
    discovery_state: Optional[str] = None
    published_at: OptionalUtcDatetime = None
    created_at: OptionalUtcDatetime = None
    view_count: int = 0
    like_count: int = 0

    model_config = ConfigDict(from_attributes=True, populate_by_name=True)


class ShareCardListResponse(BaseModel):
    """分发合规内容列表响应"""
    items: List[ShareCard]
    total: int
    page: int
    size: int
    has_more: bool


class BatchDeleteRequest(BaseModel):
    ids: List[int]
    
    
class ProcessingStageKey(str, Enum):
    """后处理阶段标识。与 `_build_processing_status` 返回的阶段一一对应。"""
    SUMMARY = "summary"
    SEMANTIC_INDEX = "semantic_index"
    ARCHIVE_MEDIA = "archive_media"
    PATROL = "patrol"
    DISTRIBUTION = "distribution"


class ProcessingStageState(str, Enum):
    """规范化阶段状态。

    每个阶段仍有自己的具体条件（见 `ProcessingStage.detail_state`），
    但 UI 只依据本枚举决定层级、颜色和是否提示用户处理。
    """
    PENDING = "pending"                  # 已排队/待开始，无需用户介入
    RUNNING = "running"                  # 正在执行
    SUCCESS = "success"                  # 全部完成
    PARTIAL = "partial"                  # 部分完成，仍有未完成或失败单元
    FAILED = "failed"                    # 失败，需要用户关注
    BLOCKED = "blocked"                  # 依赖未满足（上游未成功、密钥缺失）
    DISABLED = "disabled"                # 被用户配置关闭
    NOT_APPLICABLE = "not_applicable"    # 该内容不适用此阶段


class ProcessingActionKind(str, Enum):
    """后处理可执行动作。前端按 kind 分发，不解析文案。"""
    GENERATE_SUMMARY = "generate_summary"
    REBUILD_SEMANTIC_INDEX = "rebuild_semantic_index"
    RETRY_SEMANTIC_CHUNK = "retry_semantic_chunk"
    RETRY_DISTRIBUTION_ITEM = "retry_distribution_item"
    REMATCH_DISTRIBUTION = "rematch_distribution"
    PATROL_SCORE = "patrol_score"


class ProcessingStageAction(BaseModel):
    """一个阶段当前允许执行的动作。

    `external_effect=True` 表示该动作会调用付费模型或向外部平台发送内容，
    前端必须显式确认后才执行。
    """
    kind: ProcessingActionKind
    label: str
    external_effect: bool = False
    target_ids: List[int] = Field(default_factory=list)


class ProcessingStageFailure(BaseModel):
    """阶段内单个失败单元。"""
    id: Optional[int] = None
    reference: Optional[str] = None
    reason: Optional[str] = None
    error_type: Optional[str] = None
    retry_count: int = 0
    max_retries: Optional[int] = None
    retryable: bool = False
    occurred_at: OptionalUtcDatetime = None


class ProcessingStage(BaseModel):
    """单个后处理阶段的状态。"""
    key: ProcessingStageKey
    label: str
    state: ProcessingStageState
    detail_state: str
    message: str
    issues: List[str] = Field(default_factory=list)
    hints: List[str] = Field(default_factory=list)
    actions: List[ProcessingStageAction] = Field(default_factory=list)
    failures: List[ProcessingStageFailure] = Field(default_factory=list)
    failures_total: int = 0
    failures_truncated: bool = False
    completed_units: Optional[int] = None
    total_units: Optional[int] = None
    details: Dict[str, Any] = Field(default_factory=dict)


class ContentProcessingStatus(BaseModel):
    """内容后处理状态汇总。

    这不是第二套内容详情模型，只描述解析之后的派生处理链。
    """
    content_id: int
    content_status: ContentStatus
    state: ProcessingStageState
    stages: List[ProcessingStage]


class ContentPushPayload(BaseModel):
    """推送 payload — 供 push service 消费的内容数据。"""
    id: int
    platform: str
    title: Optional[str] = None
    body: Optional[str] = None
    summary: Optional[str] = None
    author_name: Optional[str] = None
    cover_url: Optional[str] = None
    url: Optional[str] = None
    render_config: Optional[Dict[str, Any]] = None
    context_data: Optional[Dict[str, Any]] = None
    rich_payload: Optional[Dict[str, Any]] = None
    media_items: List[Dict[str, Any]] = Field(default_factory=list)

    model_config = ConfigDict(from_attributes=True)
