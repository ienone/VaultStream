"""
Pydantic 模式定义（用于API请求/响应）
"""
from datetime import datetime
from enum import Enum
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
    author_avatar_url: Optional[str] = None # 作者头像URL
    author_url: Optional[str] = None # 作者主页链接
    cover_url: Optional[str] # 封面URL
    cover_color: Optional[str] = None # 封面主色调 (Hex)
    media_urls: List[str] # 媒体资源URL列表
    source_tags: List[str] = Field(default_factory=list) # 平台原生标签
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
    review_status: Optional[ReviewStatus] = None
    review_note: Optional[str] = None
    reviewed_by: Optional[str] = None


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
    is_nsfw: bool = False
    published_at: Optional[datetime] = None
    
    # 审批状态
    review_status: Optional[ReviewStatus] = None

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
    description: Optional[str] = None
    match_conditions: Dict[str, Any] = Field(default_factory=dict)
    targets: List[Dict[str, Any]] = Field(default_factory=list)
    enabled: bool = True
    priority: int = 0
    nsfw_policy: str = "inherit"
    approval_required: bool = False
    auto_approve_conditions: Optional[Dict[str, Any]] = None
    rate_limit: Optional[int] = None
    time_window: Optional[int] = None
    template_id: Optional[str] = None
    created_at: datetime
    updated_at: datetime
    
    @field_validator('match_conditions', mode='before')
    @classmethod
    def default_match_conditions(cls, v):
        return v if v is not None else {}
    
    @field_validator('targets', mode='before')
    @classmethod
    def default_targets(cls, v):
        return v if v is not None else []
    
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


# ========== Bot 管理 Schema ==========

class BotChatCreate(BaseModel):
    """创建 Bot 聊天关联"""
    chat_id: str = Field(..., description="Telegram Chat ID")
    chat_type: str = Field(..., description="channel/group/supergroup/private")
    title: Optional[str] = None
    username: Optional[str] = None
    description: Optional[str] = None
    enabled: bool = True
    priority: int = 0
    nsfw_policy: str = "inherit"
    nsfw_chat_id: Optional[str] = None
    tag_filter: List[str] = Field(default_factory=list)
    platform_filter: List[str] = Field(default_factory=list)
    linked_rule_ids: List[int] = Field(default_factory=list)


class BotChatUpdate(BaseModel):
    """更新 Bot 聊天配置"""
    title: Optional[str] = None
    enabled: Optional[bool] = None
    priority: Optional[int] = None
    nsfw_policy: Optional[str] = None
    nsfw_chat_id: Optional[str] = None
    tag_filter: Optional[List[str]] = None
    platform_filter: Optional[List[str]] = None
    linked_rule_ids: Optional[List[int]] = None


class BotChatResponse(BaseModel):
    """Bot 聊天响应"""
    id: int
    chat_id: str
    chat_type: str
    title: Optional[str]
    username: Optional[str]
    description: Optional[str]
    member_count: Optional[int]
    is_admin: bool
    can_post: bool
    enabled: bool
    priority: int
    nsfw_policy: str
    nsfw_chat_id: Optional[str]
    tag_filter: List[str]
    platform_filter: List[str]
    linked_rule_ids: List[int]
    total_pushed: int
    last_pushed_at: Optional[datetime]
    created_at: datetime
    updated_at: datetime

    class Config:
        from_attributes = True


class BotStatusResponse(BaseModel):
    """Bot 状态响应"""
    is_running: bool
    bot_username: Optional[str]
    bot_id: Optional[int]
    connected_chats: int
    total_pushed_today: int
    uptime_seconds: Optional[int]


class BotSyncRequest(BaseModel):
    """同步 Bot 聊天请求"""
    chat_id: Optional[str] = Field(None, description="指定同步的 Chat ID，为空则同步所有")


class StorageStatsResponse(BaseModel):
    """存储统计响应"""
    total_bytes: int
    media_count: int
    by_platform: Dict[str, int]
    by_type: Dict[str, int]


class HealthDetailResponse(BaseModel):
    """健康检查详细响应"""
    status: str
    database: str
    storage: str
    bot: Optional[str]
    queue_pending: int
    queue_failed: int
    uptime_seconds: int
    version: str


# ========== Bot Runtime Schema ==========

class BotChatUpsert(BaseModel):
    """Bot 聊天 Upsert（用于 Bot 进程上报）"""
    chat_id: str = Field(..., description="Telegram Chat ID")
    chat_type: str = Field(..., description="channel/group/supergroup/private")
    title: Optional[str] = None
    username: Optional[str] = None
    description: Optional[str] = None
    member_count: Optional[int] = None
    is_admin: bool = False
    can_post: bool = False
    raw_data: Optional[Dict] = None


class BotHeartbeat(BaseModel):
    """Bot 心跳请求"""
    bot_id: str
    bot_username: str
    bot_first_name: Optional[str] = None
    version: str = "0.1.0"
    error: Optional[str] = None


class BotRuntimeResponse(BaseModel):
    """Bot 运行时状态响应"""
    bot_id: Optional[str]
    bot_username: Optional[str]
    bot_first_name: Optional[str]
    started_at: Optional[datetime]
    last_heartbeat_at: Optional[datetime]
    is_running: bool
    uptime_seconds: Optional[int]
    version: Optional[str]
    last_error: Optional[str]
    last_error_at: Optional[datetime]


class BotSyncResult(BaseModel):
    """Bot 群组同步结果"""
    total: int
    updated: int
    failed: int
    inaccessible: int
    details: List[Dict] = Field(default_factory=list)


class RepushFailedRequest(BaseModel):
    """重新推送失败任务请求"""
    limit: int = Field(default=10, le=100)
    older_than_minutes: int = Field(default=5, ge=1)
    task_ids: Optional[List[int]] = None


class RepushFailedResponse(BaseModel):
    """重新推送失败任务响应"""
    repushed_count: int
    task_ids: List[int]


# ========== 规则预览 Schema ==========

class RulePreviewRequest(BaseModel):
    """规则预览请求"""
    hours_ahead: int = Field(default=24, ge=1, le=168, description="预览未来多少小时")
    limit: int = Field(default=50, ge=1, le=200, description="最大返回条数")


class PreviewItemStatus(str, Enum):
    """预览项状态"""
    WILL_PUSH = "will_push"
    FILTERED_NSFW = "filtered_nsfw"
    FILTERED_TAG = "filtered_tag"
    FILTERED_PLATFORM = "filtered_platform"
    PENDING_REVIEW = "pending_review"
    RATE_LIMITED = "rate_limited"
    ALREADY_PUSHED = "already_pushed"


class RulePreviewItem(BaseModel):
    """规则预览项"""
    content_id: int
    title: Optional[str] = None
    platform: str
    tags: List[str] = Field(default_factory=list)
    is_nsfw: bool = False
    status: str
    reason: Optional[str] = None
    scheduled_time: Optional[datetime] = None
    thumbnail_url: Optional[str] = None
    
    class Config:
        from_attributes = True


class RulePreviewResponse(BaseModel):
    """规则预览响应"""
    rule_id: int
    rule_name: str
    total_matched: int
    will_push_count: int
    filtered_count: int
    pending_review_count: int
    rate_limited_count: int
    items: List[RulePreviewItem]


class RulePreviewStats(BaseModel):
    """规则预览统计"""
    rule_id: int
    rule_name: str
    will_push: int
    filtered: int
    pending_review: int
    rate_limited: int
