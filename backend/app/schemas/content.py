"""
内容相关 schemas
"""
from datetime import datetime
from typing import Optional, List, Dict, Any
from pydantic import BaseModel, Field, field_validator, model_validator
import json

from app.models import Platform, ContentStatus, ReviewStatus, LayoutType
from app.constants import SUPPORTED_PLATFORMS

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
    created_at: datetime
    
    class Config:
        orm_mode = True


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
    author_url: Optional[str] = None
    cover_url: Optional[str] = None
    source_tags: List[str] = Field(default_factory=list)
    
    cover_color: Optional[str] = None
    media_urls: List[str] = Field(default_factory=list)
    extra_stats: Dict[str, Any] = Field(default_factory=dict)
    
    review_status: ReviewStatus = ReviewStatus.PENDING
    reviewed_at: Optional[datetime] = None
    reviewed_by: Optional[str] = None
    review_note: Optional[str] = None

    layout_type: Optional[LayoutType] = None
    layout_type_override: Optional[LayoutType] = None

    context_data: Optional[Dict[str, Any]] = None
    rich_payload: Optional[Dict[str, Any]] = None
    
    created_at: datetime
    updated_at: datetime
    published_at: Optional[datetime]
    
    class Config:
        orm_mode = True


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
    created_at: datetime
    published_at: Optional[datetime] = None

    class Config:
        orm_mode = True


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
    clean_url: Optional[str] = None
    content_type: Optional[str] = None
    effective_layout_type: Optional[str] = None
    title: Optional[str] = None
    author_name: Optional[str] = None
    author_id: Optional[str] = None
    author_avatar_url: Optional[str] = None
    cover_url: Optional[str] = None
    thumbnail_url: Optional[str] = None
    cover_color: Optional[str] = None
    tags: List[str] = Field(default_factory=list)
    is_nsfw: bool = False
    review_status: Optional[ReviewStatus] = None
    published_at: Optional[datetime] = None
    created_at: Optional[datetime] = None
    view_count: int = 0
    like_count: int = 0

    class Config:
        orm_mode = True


class ShareCardListResponse(BaseModel):
    """分发合规内容列表响应"""
    items: List[ShareCard]
    total: int
    page: int
    size: int
    has_more: bool


class BatchDeleteRequest(BaseModel):
    ids: List[int]
    
    
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

    class Config:
        orm_mode = True
