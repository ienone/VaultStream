"""
Pydantic 模式定义（用于API请求/响应）
"""
from datetime import datetime
from enum import Enum
import json
from typing import Optional, List, Dict, Any
from pydantic import BaseModel, Field, field_validator
from app.models import ContentStatus, Platform, BilibiliContentType, ReviewStatus, LayoutType, QueueItemStatus
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
    
    # 布局类型 - 用于前端展示形态的判定
    layout_type: Optional[LayoutType] = None  # 系统检测/推荐值
    layout_type_override: Optional[LayoutType] = None  # 用户覆盖值
    effective_layout_type: Optional[str] = None  # 有效布局类型

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
    
    # Phase 7: 结构化字段（已完成raw_metadata迁移）
    associated_question: Optional[Dict[str, Any]] = None  # 知乎回答关联的问题
    top_answers: Optional[List[Dict[str, Any]]] = None  # 知乎问题的精选回答
    
    # 时间
    created_at: datetime
    updated_at: datetime
    published_at: Optional[datetime]
    
    class Config:
        from_attributes = True


class ContentListItem(BaseModel):
    """内容列表项（精简版，用于列表展示）"""
    id: int
    platform: Platform
    url: str
    status: ContentStatus
    
    # 显示必需字段
    title: Optional[str] = None
    cover_url: Optional[str] = None
    thumbnail_url: Optional[str] = None  # 缩略图URL（优化加载）
    author_name: Optional[str] = None
    
    tags: List[str] = Field(default_factory=list)
    is_nsfw: bool = False
    layout_type: Optional[str] = None
    
    # 时间戳
    created_at: datetime
    published_at: Optional[datetime] = None
    
    # 排除：raw_metadata, extra_stats, 所有统计字段
    
    class Config:
        from_attributes = True


class ContentListResponse(BaseModel):
    """内容列表响应"""
    items: List[ContentDetail]
    total: int
    page: int
    size: int
    has_more: bool


class ContentListItemResponse(BaseModel):
    """内容列表响应（精简版）"""
    items: List[ContentListItem]
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
    unprocessed: int
    processing: int
    parse_success: int
    parse_failed: int
    total: int


class DistributionStatusStats(BaseModel):
    """解析成功后进入分发阶段的状态统计"""
    will_push: int
    filtered: int
    pending_review: int
    pushed: int
    total: int


class QueueOverviewStats(BaseModel):
    """看板状态总览（解析 + 分发）"""
    parse: QueueStats
    distribution: DistributionStatusStats


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
    layout_type_override: Optional[LayoutType] = None  # 用户覆盖布局类型


class BatchUpdateRequest(BaseModel):
    """批量更新请求"""
    content_ids: List[int] = Field(..., min_items=1, max_items=100, description="内容ID列表")
    updates: ContentUpdate = Field(..., description="更新内容")


class BatchOperationResponse(BaseModel):
    """批量操作响应"""
    success_count: int
    failed_count: int
    success_ids: List[int] = Field(default_factory=list)
    failed_ids: List[int] = Field(default_factory=list)
    errors: Dict[int, str] = Field(default_factory=dict)


class ShareCard(BaseModel):
    """合规分享卡片（对外输出用）- 轻量级列表展示。

    与"私有存档 raw_metadata"严格隔离：这里不允许出现 raw_metadata、client_context 等全量信息。
    优化后仅包含列表展示必需字段，移除 description, summary, media_urls 等详情页字段。
    """

    id: int
    platform: Platform
    url: str
    clean_url: Optional[str] = None
    content_type: Optional[str] = None
    
    # 布局类型 - 使用计算后的有效值
    effective_layout_type: Optional[str] = None  # 已计算的有效布局类型
    
    # 基础展示字段
    title: Optional[str] = None
    author_name: Optional[str] = None
    author_id: Optional[str] = None
    author_avatar_url: Optional[str] = None
    
    # 封面相关
    cover_url: Optional[str] = None
    thumbnail_url: Optional[str] = None  # 缩略图URL (优化加载)
    cover_color: Optional[str] = None  # M5: 封面主色调 (Hex)
    
    # 分类和标记
    tags: List[str] = Field(default_factory=list)
    is_nsfw: bool = False
    
    # 审批状态
    review_status: Optional[ReviewStatus] = None
    
    # 时间戳
    published_at: Optional[datetime] = None
    created_at: Optional[datetime] = None

    # 基础统计（仅用于列表排序/筛选）
    view_count: int = 0
    like_count: int = 0

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


class RenderConfig(BaseModel):
    """渲染配置结构（可嵌套或扁平使用）"""
    # Display control
    show_platform_id: bool = True
    show_title: bool = True
    show_tags: bool = False
    
    # Mode selectors
    author_mode: str = Field(default="full", description="Author display mode: none/name/full")
    content_mode: str = Field(default="summary", description="Content mode: hidden/summary/full")
    media_mode: str = Field(default="auto", description="Media mode: none/auto/all")
    link_mode: str = Field(default="clean", description="Link mode: none/clean/original")
    
    # Template text
    header_text: str = Field(default="", description="Header text with variable support")
    footer_text: str = Field(default="", description="Footer text with variable support")


class DistributionTarget(BaseModel):
    """分发目标配置"""
    platform: str = Field(..., description="Platform name: telegram/qq")
    target_id: str = Field(..., description="Channel/Group ID")
    enabled: bool = Field(default=True, description="Enable this target")
    
    # 批量转发选项（仅适用于 QQ）
    merge_forward: bool = Field(default=False, description="Use merged forward mode (QQ only)")
    use_author_name: bool = Field(default=False, description="Show original author name")
    summary: str = Field(default="", description="Display name for merged forward")
    
    # 可选的渲染配置覆盖（如果需要针对特定目标调整展示）
    render_config: Optional[Dict[str, Any]] = Field(None, description="Per-target render config override")


def _validate_targets_list(v: List[Dict[str, Any]]) -> List[Dict[str, Any]]:
    """Helper to validate target schema to ensure consistency"""
    if v is None:
        return v
        
    for target in v:
        # Required fields
        if 'platform' not in target or 'target_id' not in target:
            raise ValueError("Each target must have 'platform' and 'target_id'")
        
        # Platform validation
        platform = target['platform']
        if platform not in SUPPORTED_PLATFORMS:
            raise ValueError(f"Invalid platform: {platform}. Must be one of {SUPPORTED_PLATFORMS}")
        
        # Validate and normalize target_id
        target_id = str(target['target_id']).strip()
        if not target_id:
            raise ValueError("target_id cannot be empty or whitespace-only")
        
        # Platform-specific validation
        if platform == Platform.TELEGRAM.value:
            # Telegram: numeric chat ID or @username
            if not (target_id.startswith('@') or target_id.lstrip('-').isdigit()):
                raise ValueError(
                    f"Invalid Telegram target_id: '{target_id}'. "
                    "Must be numeric chat ID or @username"
                )
        elif platform == Platform.QQ.value:
            # QQ: numeric group/user ID or group:numeric
            if target_id.startswith('group:'):
                group_id = target_id.split(':', 1)[1]
                if not group_id.isdigit():
                    raise ValueError(
                        f"Invalid QQ group ID: '{target_id}'. "
                        "Group ID must be numeric"
                    )
            elif not target_id.isdigit():
                raise ValueError(
                    f"Invalid QQ target_id: '{target_id}'. "
                    "Must be numeric or 'group:numeric' format"
                )
        
        # Update target_id after validation
        target['target_id'] = target_id
        
        # Optional fields with defaults
        target.setdefault('enabled', True)
        target.setdefault('merge_forward', False)
        target.setdefault('use_author_name', False)
        target.setdefault('summary', '')
        
        # Validate render_config if present
        if 'render_config' in target and target['render_config'] is not None:
            if not isinstance(target['render_config'], dict):
                raise ValueError("render_config must be a dictionary")
    
    return v


class DistributionRuleCreate(BaseModel):
    """创建分发规则"""
    name: str = Field(..., min_length=1, max_length=200)
    description: Optional[str] = None
    match_conditions: Dict[str, Any] = Field(..., description="匹配条件 JSON")
    enabled: bool = True
    priority: int = 0
    nsfw_policy: str = Field(default="block", description="NSFW策略: allow/block/separate_channel")
    approval_required: bool = False
    auto_approve_conditions: Optional[Dict[str, Any]] = None
    rate_limit: Optional[int] = None
    time_window: Optional[int] = None
    template_id: Optional[str] = None
    render_config: Optional[Dict[str, Any]] = None


class DistributionRuleUpdate(BaseModel):
    """更新分发规则（Phase 4: targets 字段已移除，请使用 DistributionTarget API）"""
    name: Optional[str] = None
    description: Optional[str] = None
    match_conditions: Optional[Dict[str, Any]] = None
    enabled: Optional[bool] = None
    priority: Optional[int] = None
    nsfw_policy: Optional[str] = None
    approval_required: Optional[bool] = None
    auto_approve_conditions: Optional[Dict[str, Any]] = None
    rate_limit: Optional[int] = None
    time_window: Optional[int] = None
    template_id: Optional[str] = None
    render_config: Optional[Dict[str, Any]] = None


class DistributionRuleResponse(BaseModel):
    """分发规则响应"""
    id: int
    name: str
    description: Optional[str] = None
    match_conditions: Dict[str, Any] = Field(default_factory=dict)
    enabled: bool = True
    priority: int = 0
    nsfw_policy: str = "block"
    approval_required: bool = False
    auto_approve_conditions: Optional[Dict[str, Any]] = None
    rate_limit: Optional[int] = None
    time_window: Optional[int] = None
    template_id: Optional[str] = None
    render_config: Optional[Dict[str, Any]] = None
    created_at: datetime
    updated_at: datetime
    
    @field_validator('match_conditions', mode='before')
    @classmethod
    def default_match_conditions(cls, v):
        return v if v is not None else {}
    
    class Config:
        from_attributes = True


# ========== DistributionTarget Schemas ==========

class DistributionTargetCreate(BaseModel):
    """创建分发目标"""
    bot_chat_id: int = Field(..., description="关联的 BotChat ID")
    enabled: bool = True
    merge_forward: bool = False  # QQ 合并转发
    use_author_name: bool = True  # 显示原作者名
    summary: Optional[str] = None  # 合并转发显示名
    render_config_override: Optional[Dict[str, Any]] = None  # 渲染配置覆盖


class DistributionTargetUpdate(BaseModel):
    """更新分发目标"""
    enabled: Optional[bool] = None
    merge_forward: Optional[bool] = None
    use_author_name: Optional[bool] = None
    summary: Optional[str] = None
    render_config_override: Optional[Dict[str, Any]] = None


class DistributionTargetResponse(BaseModel):
    """分发目标响应"""
    id: int
    rule_id: int
    bot_chat_id: int
    enabled: bool
    merge_forward: bool
    use_author_name: bool
    summary: Optional[str]
    render_config_override: Optional[Dict[str, Any]]
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


# ========== Bot 管理 Schema ==========

class BotChatCreate(BaseModel):
    """创建 Bot 聊天关联"""
    bot_config_id: int = Field(..., ge=1, description="所属 BotConfig ID")
    chat_id: str = Field(..., description="Telegram Chat ID")
    chat_type: str = Field(..., description="channel/group/supergroup/private")
    title: Optional[str] = None
    username: Optional[str] = None
    description: Optional[str] = None
    enabled: bool = True
    nsfw_chat_id: Optional[str] = None


class BotChatUpdate(BaseModel):
    """更新 Bot 聊天配置"""
    title: Optional[str] = None
    enabled: Optional[bool] = None
    nsfw_chat_id: Optional[str] = None


class BotChatResponse(BaseModel):
    """Bot 聊天响应"""
    id: int
    bot_config_id: int
    chat_id: str
    chat_type: str
    title: Optional[str]
    username: Optional[str]
    description: Optional[str]
    member_count: Optional[int]
    is_admin: bool
    can_post: bool
    enabled: bool
    nsfw_chat_id: Optional[str]
    total_pushed: int
    last_pushed_at: Optional[datetime]
    is_accessible: bool
    last_sync_at: Optional[datetime]
    sync_error: Optional[str]
    applied_rule_ids: List[int] = Field(default_factory=list)
    applied_rule_names: List[str] = Field(default_factory=list)
    applied_rule_count: int = 0
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
    napcat_status: Optional[str] = None
    parse_stats: QueueStats
    distribution_stats: DistributionStatusStats
    rule_breakdown: Dict[str, DistributionStatusStats] = Field(default_factory=dict)


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
    bot_config_id: int = Field(..., ge=1, description="所属 BotConfig ID")
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


class ChatRuleBindingInfo(BaseModel):
    """群组已绑定规则信息"""
    rule_id: int
    name: str
    enabled: bool = True


class BotChatRulesResponse(BaseModel):
    """群组规则列表"""
    chat_id: str
    rule_ids: List[int] = Field(default_factory=list)
    rules: List[ChatRuleBindingInfo] = Field(default_factory=list)


class BotChatRuleAssignRequest(BaseModel):
    """群组规则绑定更新请求"""
    rule_ids: List[int] = Field(default_factory=list)


class BotConfigBase(BaseModel):
    """Bot 配置基础字段"""
    platform: str = Field(..., pattern=r"^(telegram|qq)$")
    name: str = Field(..., min_length=1, max_length=100)
    bot_token: Optional[str] = None
    napcat_http_url: Optional[str] = None
    napcat_ws_url: Optional[str] = None
    napcat_access_token: Optional[str] = None
    enabled: bool = True
    is_primary: bool = False


class BotConfigCreate(BotConfigBase):
    """创建 Bot 配置"""


class BotConfigUpdate(BaseModel):
    """更新 Bot 配置"""
    name: Optional[str] = Field(default=None, min_length=1, max_length=100)
    bot_token: Optional[str] = None
    napcat_http_url: Optional[str] = None
    napcat_ws_url: Optional[str] = None
    napcat_access_token: Optional[str] = None
    enabled: Optional[bool] = None
    is_primary: Optional[bool] = None


class BotConfigResponse(BaseModel):
    """Bot 配置响应"""
    id: int
    platform: str
    name: str
    bot_token_masked: Optional[str] = None
    napcat_http_url: Optional[str] = None
    napcat_ws_url: Optional[str] = None
    napcat_access_token_masked: Optional[str] = None
    enabled: bool
    is_primary: bool
    bot_id: Optional[str] = None
    bot_username: Optional[str] = None
    chat_count: int = 0
    created_at: datetime
    updated_at: datetime


class BotConfigActivateResponse(BaseModel):
    """激活主 Bot 响应"""
    id: int
    platform: str
    is_primary: bool


class BotConfigSyncChatsResponse(BaseModel):
    """Bot 配置同步群组响应"""
    bot_config_id: int
    total: int = 0
    updated: int = 0
    created: int = 0
    failed: int = 0
    details: List[Dict[str, Any]] = Field(default_factory=list)


class BotConfigQrCodeResponse(BaseModel):
    """Napcat 登录二维码响应"""
    bot_config_id: int
    status: str
    qr_code: Optional[str] = None
    message: Optional[str] = None


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


# ========== Target Management Schema ==========

class TargetUsageInfo(BaseModel):
    """Target usage information"""
    target_platform: str
    target_id: str
    enabled: bool = True
    
    # Statistics
    rule_count: int = Field(0, description="Number of rules using this target")
    rule_ids: List[int] = Field(default_factory=list, description="IDs of rules using this target")
    rule_names: List[str] = Field(default_factory=list, description="Names of rules using this target")
    total_pushed: int = Field(0, description="Total number of pushes to this target")
    last_pushed_at: Optional[datetime] = Field(None, description="Last push timestamp")
    
    # Configuration
    merge_forward: bool = Field(default=False, description="Use merged forward mode")
    use_author_name: bool = Field(default=False, description="Show original author name")
    summary: str = Field(default="", description="Display name for merged forward")
    render_config: Optional[Dict[str, Any]] = Field(None, description="Render config override")
    
    # Connection status
    connection_status: Optional[str] = Field(None, description="Connection test result: unknown/ok/error")
    connection_message: Optional[str] = Field(None, description="Connection test message")


class TargetListResponse(BaseModel):
    """Target list response"""
    total: int
    targets: List[TargetUsageInfo]


class TargetTestRequest(BaseModel):
    """Target connection test request"""
    platform: str = Field(..., description="Platform: telegram/qq")
    target_id: str = Field(..., description="Channel/Group ID")


class TargetTestResponse(BaseModel):
    """Target connection test response"""
    platform: str
    target_id: str
    status: str = Field(..., description="Test status: ok/error")
    message: str = Field(..., description="Test result message")
    details: Optional[Dict[str, Any]] = Field(None, description="Additional details")


class BatchTargetUpdateRequest(BaseModel):
    """Batch target update request"""
    rule_ids: List[int] = Field(..., description="Rule IDs to update")
    target_platform: str = Field(..., description="Target platform to update")
    target_id: str = Field(..., description="Target ID to update")
    enabled: Optional[bool] = Field(None, description="Enable/disable target")
    merge_forward: Optional[bool] = Field(None, description="Update merge forward setting")
    render_config: Optional[Dict[str, Any]] = Field(None, description="Update render config")


class BatchTargetUpdateResponse(BaseModel):
    """Batch target update response"""
    updated_count: int
    updated_rules: List[int]
    message: str


# ========== Render Config Preset Schema ==========

class RenderConfigPreset(BaseModel):
    """Render config preset template"""
    id: str = Field(..., description="Preset ID")
    name: str = Field(..., description="Preset name")
    description: Optional[str] = Field(None, description="Preset description")
    config: Dict[str, Any] = Field(..., description="Render config")
    is_builtin: bool = Field(default=False, description="Built-in preset (cannot be deleted)")
    created_at: Optional[datetime] = None
    updated_at: Optional[datetime] = None


class RenderConfigPresetCreate(BaseModel):
    """Create render config preset"""
    name: str = Field(..., min_length=1, max_length=100)
    description: Optional[str] = None
    config: Dict[str, Any] = Field(...)


class RenderConfigPresetUpdate(BaseModel):
    """Update render config preset"""
    name: Optional[str] = None
    description: Optional[str] = None
    config: Optional[Dict[str, Any]] = None


# ========== Distribution Queue Schemas ==========

class ContentQueueItemResponse(BaseModel):
    """队列项响应"""
    id: int
    content_id: int
    title: Optional[str] = None
    tags: List[str] = Field(default_factory=list)
    is_nsfw: bool = False
    cover_url: Optional[str] = None
    author_name: Optional[str] = None
    rule_id: int
    bot_chat_id: int
    target_platform: str
    target_id: str
    status: str
    priority: int = 0
    scheduled_at: Optional[datetime] = None
    needs_approval: bool = False
    approved_at: Optional[datetime] = None
    attempt_count: int = 0
    max_attempts: int = 3
    next_attempt_at: Optional[datetime] = None
    message_id: Optional[str] = None
    last_error: Optional[str] = None
    last_error_type: Optional[str] = None
    last_error_at: Optional[datetime] = None
    started_at: Optional[datetime] = None
    completed_at: Optional[datetime] = None
    created_at: datetime
    updated_at: datetime

    class Config:
        from_attributes = True


class ContentQueueItemListResponse(BaseModel):
    """队列项列表响应"""
    items: List[ContentQueueItemResponse]
    total: int
    page: int = 1
    size: int = 50
    has_more: bool = False


class QueueStatsResponse(BaseModel):
    """队列统计响应"""
    will_push: int = 0
    filtered: int = 0
    pending_review: int = 0
    pushed: int = 0
    total: int = 0
    due_now: int = 0


class EnqueueContentRequest(BaseModel):
    """手动入队请求"""
    force: bool = Field(default=False, description="强制重新入队（即使已存在）")


class QueueItemRetryRequest(BaseModel):
    """重试队列项请求"""
    reset_attempts: bool = Field(default=False, description="是否重置重试次数")


class BatchQueueRetryRequest(BaseModel):
    """批量重试队列项请求"""
    item_ids: Optional[List[int]] = Field(None, description="指定重试的队列项ID")
    status_filter: str = Field(default="failed", description="状态过滤: failed")
    limit: int = Field(default=50, le=200, description="最大重试数量")
