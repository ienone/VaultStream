"""
Pydantic 模式定义（用于API请求/响应）
"""
from datetime import datetime
import json
from typing import Optional, List, Dict, Any
from pydantic import BaseModel, Field, field_validator
from app.models import ContentStatus, Platform, BilibiliContentType, ReviewStatus


NOTE_MAX_LENGTH = 2000 # 备注内容的最大长度
CLIENT_CONTEXT_MAX_BYTES = 4096 # JSON序列化后最大4KB


class ShareRequest(BaseModel):
    """分享请求"""
    url: str = Field(..., description="要分享的URL")
    tags: List[str] = Field(default_factory=list, description="标签列表")
    source: Optional[str] = Field(None, description="来源标识")
    note: Optional[str] = Field(None, description="备注", max_length=NOTE_MAX_LENGTH)
    client_context: Optional[Dict[str, Any]] = Field(None, description="客户端上下文（可选）")
    is_nsfw: bool = Field(default=False, description="是否为NSFW内容")

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
        from_attributes = True


class ContentDetail(BaseModel):
    """内容详情"""
    id: int
    platform: Platform
    url: str
    clean_url: Optional[str]
    status: ContentStatus

    # 解析失败信息（轻量字段，便于排查/人工修复）
    failure_count: int = 0
    last_error_type: Optional[str] = None
    last_error: Optional[str] = None
    last_error_at: Optional[datetime] = None
    
    # M4: 审批流字段
    review_status: Optional[ReviewStatus] = ReviewStatus.PENDING
    reviewed_at: Optional[datetime] = None
    reviewed_by: Optional[str] = None
    review_note: Optional[str] = None
    
    tags: List[str]
    is_nsfw: bool
    source: Optional[str]
    platform_id: Optional[str] = None # 平台特有ID
    content_type: Optional[str] = None # 内容具体类型

    # 通用字段
    title: Optional[str] # 内容标题
    description: Optional[str] # 内容描述
    author_name: Optional[str] # 作者名称
    author_id: Optional[str] # 作者平台ID
    cover_url: Optional[str] # 封面URL
    cover_color: Optional[str] = None # 封面主色调 (Hex)
    media_urls: List[str] # 媒体资源URL列表
    view_count: int = 0 # 查看次数
    like_count: int = 0 # 点赞次数
    collect_count: int = 0 # 收藏次数
    share_count: int = 0 # 分享次数 
    comment_count: int = 0 # 评论次数
    extra_stats: Dict[str, Any] = Field(default_factory=dict) # 平台特有扩展数据

    # B站特有
    bilibili_type: Optional[BilibiliContentType]
    bilibili_id: Optional[str]
        
    # 元数据
    raw_metadata: Optional[Dict[str, Any]]
    
    # 时间
    created_at: datetime
    updated_at: datetime
    published_at: Optional[datetime]
    
    class Config:
        from_attributes = True


class GetContentRequest(BaseModel):
    """获取待分发内容请求"""
    tag: Optional[str] = Field(None, description="按标签筛选")
    platform: Optional[str] = Field(None, description="按平台筛选 (twitter, bilibili)")
    target_platform: str = Field(..., description="目标平台标识")
    limit: int = Field(1, ge=1, le=10, description="获取数量")


class ContentListResponse(BaseModel):
    """内容列表响应"""
    items: List[ContentDetail]
    total: int
    page: int
    size: int
    has_more: bool


class TagStats(BaseModel):
    """标签统计"""
    name: str
    count: int


class QueueStats(BaseModel):
    """队列统计"""
    pending: int
    processing: int
    failed: int
    archived: int
    total: int


class DashboardStats(BaseModel):
    """仪表盘数据"""
    platform_counts: Dict[str, int]
    daily_growth: List[Dict[str, Any]]
    storage_usage_bytes: int


class ContentUpdate(BaseModel):
    """内容修改请求"""
    tags: Optional[List[str]] = None
    title: Optional[str] = None
    description: Optional[str] = None
    author_name: Optional[str] = None
    cover_url: Optional[str] = None
    is_nsfw: Optional[bool] = None
    status: Optional[ContentStatus] = None


class MarkPushedRequest(BaseModel):
    """标记已推送请求"""
    content_id: int
    target_platform: str
    target_id: str  # M4: 新增目标ID（如频道ID）
    message_id: Optional[str] = None


class ShareCard(BaseModel):
    """合规分享卡片（对外输出用）。

    与“私有存档 raw_metadata”严格隔离：这里不允许出现 raw_metadata、client_context 等全量信息。
    """

    id: int
    platform: Platform
    url: str
    clean_url: Optional[str] = None
    content_type: Optional[str] = None
    title: Optional[str] = None
    summary: Optional[str] = None
    description: Optional[str] = None  # Added for text content display
    author_name: Optional[str] = None  # 作者名称
    author_id: Optional[str] = None     # 作者ID
    author_avatar_url: Optional[str] = None # 作者头像URL
    cover_url: Optional[str] = None
    cover_color: Optional[str] = None  # M5: 封面主色调 (Hex)
    media_urls: List[str] = Field(default_factory=list) # M6: 支持首图回退
    tags: List[str] = Field(default_factory=list)
    published_at: Optional[datetime] = None

    # 少量通用互动数据（可选）
    view_count: int = 0
    like_count: int = 0
    collect_count: int = 0
    share_count: int = 0
    comment_count: int = 0

    class Config:
        from_attributes = True


class ShareCardListResponse(BaseModel):
    """分发合规内容列表响应"""
    items: List[ShareCard]
    total: int
    page: int
    size: int
    has_more: bool


# ========== M4: 分发规则与审批流 Schema ==========

class OptimizedMedia(BaseModel):
    """优化后的媒体资源（Share Card 使用）"""
    type: str  # "image", "video", "audio"
    url: str  # 代理URL或优化后的URL
    thumbnail_url: Optional[str] = None
    width: Optional[int] = None
    height: Optional[int] = None
    size_bytes: Optional[int] = None


class ShareCardPreview(BaseModel):
    """分享卡片预览（完整版）"""
    id: int
    platform: Platform
    title: Optional[str]
    summary: Optional[str]
    author_name: Optional[str]
    cover_url: Optional[str]
    optimized_media: List[OptimizedMedia] = Field(default_factory=list)
    source_url: str  # 原始来源链接
    tags: List[str]
    published_at: Optional[datetime]
    
    # 互动数据
    view_count: int = 0
    like_count: int = 0
    
    class Config:
        from_attributes = True


class DistributionTarget(BaseModel):
    """分发目标配置"""
    platform: str  # "telegram", "qq" 等
    target_id: str  # 频道/群组 ID
    enabled: bool = True


class DistributionRuleCreate(BaseModel):
    """创建分发规则"""
    name: str = Field(..., min_length=1, max_length=200)
    description: Optional[str] = None
    match_conditions: Dict[str, Any] = Field(..., description="匹配条件 JSON")
    targets: List[Dict[str, Any]] = Field(default_factory=list, description="目标配置列表")
    enabled: bool = True
    priority: int = 0
    nsfw_policy: str = Field(default="block", description="NSFW策略: allow/block/separate_channel")
    approval_required: bool = False
    auto_approve_conditions: Optional[Dict[str, Any]] = None
    rate_limit: Optional[int] = None
    time_window: Optional[int] = None
    template_id: Optional[str] = None


class DistributionRuleUpdate(BaseModel):
    """更新分发规则"""
    name: Optional[str] = None
    description: Optional[str] = None
    match_conditions: Optional[Dict[str, Any]] = None
    targets: Optional[List[Dict[str, Any]]] = None
    enabled: Optional[bool] = None
    priority: Optional[int] = None
    nsfw_policy: Optional[str] = None
    approval_required: Optional[bool] = None
    auto_approve_conditions: Optional[Dict[str, Any]] = None
    rate_limit: Optional[int] = None
    time_window: Optional[int] = None
    template_id: Optional[str] = None


class DistributionRuleResponse(BaseModel):
    """分发规则响应"""
    id: int
    name: str
    description: Optional[str]
    match_conditions: Dict[str, Any]
    targets: List[Dict[str, Any]]
    enabled: bool
    priority: int
    nsfw_policy: str
    approval_required: bool
    auto_approve_conditions: Optional[Dict[str, Any]]
    rate_limit: Optional[int]
    time_window: Optional[int]
    template_id: Optional[str]
    created_at: datetime
    updated_at: datetime
    
    class Config:
        from_attributes = True


class ReviewAction(BaseModel):
    """审批操作"""
    action: str = Field(..., description="approve/reject")
    note: Optional[str] = Field(None, description="审批备注")
    reviewed_by: Optional[str] = Field(None, description="审批人")


class BatchReviewRequest(BaseModel):
    """批量审批请求"""
    content_ids: List[int] = Field(..., min_items=1)
    action: str = Field(..., description="approve/reject")
    note: Optional[str] = None
    reviewed_by: Optional[str] = None


class PushedRecordResponse(BaseModel):
    """推送记录响应"""
    id: int
    content_id: int
    target_platform: str
    target_id: str
    message_id: Optional[str]
    push_status: str
    error_message: Optional[str]
    pushed_at: datetime
    
    class Config:
        from_attributes = True


class WeiboUserResponse(BaseModel):
    """微博用户响应"""
    id: int
    platform_id: str
    nick_name: str
    avatar_hd: Optional[str]
    description: Optional[str]
    followers_count: int
    friends_count: int
    statuses_count: int
    verified: bool
    class Config:
        from_attributes = True


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
    updated_at: datetime

    class Config:
        from_attributes = True
