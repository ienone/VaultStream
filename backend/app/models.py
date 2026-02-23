"""
数据库模型定义
"""
from datetime import datetime, timezone
from enum import Enum
from typing import Optional, List
from sqlalchemy import Column, Integer, String, DateTime, Boolean, Text, ForeignKey, Enum as SQLEnum, UniqueConstraint, JSON, Index, Float
from sqlalchemy.orm import declarative_base, relationship, backref

from app.core.time_utils import utcnow

Base = declarative_base()


class LayoutType(str, Enum):
    """内容布局类型 - 用于前端展示形态的判定"""
    ARTICLE = "article"   # 长文 (知乎专栏, 博客, 新闻) - 侧重 Markdown 渲染
    VIDEO = "video"       # 纯视频 (B站, YouTube) - 侧重播放器
    GALLERY = "gallery"   # 画廊 (微博, 小红书, Twitter/X) - 侧重图片轮播
    AUDIO = "audio"       # 音频 (Podcast)
    LINK = "link"         # 纯链接 (无法解析时)


class ContentStatus(str, Enum):
    """内容状态"""
    UNPROCESSED = "unprocessed"  # 未处理
    PROCESSING = "processing"    # 处理中
    PARSE_SUCCESS = "parse_success"  # 解析成功
    PARSE_FAILED = "parse_failed"    # 解析失败


class ReviewStatus(str, Enum):
    """内容审核状态（M4 审批流）"""
    PENDING = "pending"          # 待审核
    APPROVED = "approved"        # 已批准
    REJECTED = "rejected"        # 已拒绝
    AUTO_APPROVED = "auto_approved"  # 自动批准


class Platform(str, Enum):
    """支持的平台"""
    BILIBILI = "bilibili"
    TWITTER = "twitter"
    XIAOHONGSHU = "xiaohongshu"
    DOUYIN = "douyin"
    WEIBO = "weibo"
    ZHIHU = "zhihu"
    KU_AN="ku_an"
    UNIVERSAL = "universal"


class BilibiliContentType(str, Enum):
    """B站内容类型"""
    VIDEO = "video"          # 视频
    ARTICLE = "article"      # 专栏文章
    DYNAMIC = "dynamic"      # 动态
    BANGUMI = "bangumi"      # 番剧
    AUDIO = "audio"          # 音频
    LIVE = "live"            # 直播
    CHEESE = "cheese"        # 课程


class TwitterContentType(str, Enum):
    """Twitter内容类型"""
    TWEET = "tweet"          # 推文
    THREAD = "thread"        # 线程（暂时与tweet相同，未来可能扩展）
    # 未来可扩展：SPACE, MOMENT 等


class Content(Base):
    """内容表"""
    __tablename__ = "contents"

    __table_args__ = (
        UniqueConstraint("platform", "canonical_url", name="uq_contents_platform_canonical_url"),
        # M3 增加复合索引以加速查询和排序
        Index("ix_contents_platform_created_at", "platform", "created_at"),
        Index("ix_contents_status_created_at", "status", "created_at"),
        Index("ix_contents_is_nsfw_created_at", "is_nsfw", "created_at"),
        Index("ix_contents_layout_type_created_at", "layout_type", "created_at"),
    )
    
    id = Column(Integer, primary_key=True, index=True)
    platform = Column(SQLEnum(Platform, native_enum=False, values_callable=lambda x: [e.value for e in x]), nullable=False, index=True)  # 按枚举 value（小写）存储
    url = Column(Text, nullable=False)  # 原始输入
    canonical_url = Column(Text, index=True)  # 用于去重的规范化URL
    clean_url = Column(Text)  # 解析后的净化URL
    status = Column(
        SQLEnum(ContentStatus, native_enum=False, values_callable=lambda x: [e.value for e in x]),
        default=ContentStatus.UNPROCESSED,
        index=True,
    )
    
    # 布局类型 - 内容驱动的展示形态
    layout_type = Column(SQLEnum(LayoutType, values_callable=lambda x: [e.value for e in x]), nullable=True, index=True)  # 系统检测/推荐值
    layout_type_override = Column(SQLEnum(LayoutType, values_callable=lambda x: [e.value for e in x]), nullable=True)  # 用户覆盖值
    content_type = Column(String(50), index=True)  # 平台内容类型 (video, article, dynamic等)

    # 失败记录（用于失败重试/人工修复/后续可视化）
    failure_count = Column(Integer, default=0)
    last_error = Column(Text)
    last_error_type = Column(String(200))
    last_error_detail = Column(JSON)
    last_error_at = Column(DateTime)
    
    # M4: 审批流状态
    review_status = Column(SQLEnum(ReviewStatus, native_enum=False, values_callable=lambda x: [e.value for e in x]), default=ReviewStatus.PENDING, index=True)
    reviewed_at = Column(DateTime)  # 审核时间
    reviewed_by = Column(String(100))  # 审核人（预留）
    review_note = Column(Text)  # 审核备注
    
    # 队列排序优先级（越大越优先）
    queue_priority = Column(Integer, default=0, index=True)
    
    # 标签和分类
    tags = Column(JSON, default=list)  # 用户自定义标签
    is_nsfw = Column(Boolean, default=False)
    source = Column(String(100))  # 来源标识
    source_type = Column(String(50), default="user_submit", index=True)  # user_submit, ai_discovered
    ai_score = Column(Float, nullable=True)
    discovered_at = Column(DateTime)
    
    # 平台特有 ID (如 BV号, 推文ID)
    platform_id = Column(String(100), index=True)
    
    # 通用互动数据
    view_count = Column(Integer, default=0)
    like_count = Column(Integer, default=0)
    collect_count = Column(Integer, default=0)
    share_count = Column(Integer, default=0)
    comment_count = Column(Integer, default=0)
    
    # 平台特有扩展数据 (如 B站投币、转发等)
    extra_stats = Column(JSON, default=dict)
    
    # 提取的通用字段
    title = Column(Text)
    body = Column(Text)  # 正文（Markdown/纯文本）
    summary = Column(Text)  # 摘要（LLM生成或截取）
    author_name = Column(String(200))
    author_id = Column(String(100))
    author_avatar_url = Column("author_avatar_url", Text)  # 直接存储，展示逻辑由 content_presenter 提供
    author_url = Column(Text)  # 作者主页链接
    cover_url = Column(Text)
    source_tags = Column(JSON, default=list)  # 平台原生标签

    cover_color = Column(String(20))  # 封面主色调 (Hex)
    media_urls = Column(JSON, default=list)  # 媒体资源URL列表
    
    # [Context Slot] 关联上下文: {"type": "parent/reference", "title": "...", "url": "...", "cover": "..."}
    context_data = Column(JSON, nullable=True)

    # [Rich Payload] 富媒体/交互组件块: {"blocks": [{"type": "sub_item/poll/media_grid", "data": {...}}]}
    rich_payload = Column(JSON, nullable=True)

    # [Archive Blob] 原始元数据: 仅用于后端审计和重解析
    archive_metadata = Column(JSON)
    
    # 软删除支持
    deleted_at = Column(DateTime, nullable=True)
    
    # 时间戳
    created_at = Column(DateTime, default=utcnow, index=True)
    updated_at = Column(DateTime, default=utcnow, onupdate=utcnow)
    published_at = Column(DateTime)  # 原始发布时间
    
    # 关系
    pushed_records = relationship("PushedRecord", back_populates="content")
    sources = relationship("ContentSource", back_populates="content")


class ContentSource(Base):
    """每次分享触发记录（用于追踪来源与重放）。
    记录内容包括:
    - content_id: 关联的内容ID
    - source: 分享来源标识
    - tags_snapshot: 分享时的标签快照
    - note: 备注信息
    - client_context: 客户端上下文信息
    - created_at: 创建时间
    """

    __tablename__ = "content_sources"

    id = Column(Integer, primary_key=True, index=True)
    content_id = Column(Integer, ForeignKey("contents.id"), nullable=False, index=True)

    source = Column(String(100))
    tags_snapshot = Column(JSON, default=list)
    note = Column(Text)
    client_context = Column(JSON)

    created_at = Column(DateTime, default=utcnow, index=True)

    content = relationship("Content", back_populates="sources")


class PushedRecord(Base):
    """推送记录表（M4 扩展：记录 message_id 和 target_id）"""
    __tablename__ = "pushed_records"
    
    __table_args__ = (
        # 同一内容同一目标不重复推送（唯一约束）
        UniqueConstraint("content_id", "target_id", name="uq_pushed_records_content_target"),
        Index("ix_pushed_records_target_id", "target_id"),
    )
    
    id = Column(Integer, primary_key=True, index=True)
    content_id = Column(Integer, ForeignKey("contents.id"), nullable=False, index=True)
    
    # M4 扩展字段
    target_platform = Column(String(100), nullable=False)  # "telegram", "qq" 等
    target_id = Column(String(200), nullable=False)  # 频道/群组 ID（如 @channel_name, -1001234567890）
    message_id = Column(String(200))  # 推送后的消息ID（用于更新/撤回）
    
    # 推送状态
    push_status = Column(String(50), default="success")  # success/failed/pending
    error_message = Column(Text)  # 失败原因
    
    pushed_at = Column(DateTime, default=utcnow, index=True)
    
    # 关系
    content = relationship("Content", back_populates="pushed_records")


class DistributionRule(Base):
    """分发规则表（M4 分发引擎）"""
    __tablename__ = "distribution_rules"
    
    id = Column(Integer, primary_key=True, index=True)
    
    # 规则名称与描述
    name = Column(String(200), nullable=False, unique=True)
    description = Column(Text)
    
    # 匹配条件（使用 JSON 存储灵活条件）
    # 示例: {"tags": ["tech", "news"], "platform": "bilibili", "is_nsfw": false}
    match_conditions = Column(JSON, nullable=False)
    
    # 规则配置
    enabled = Column(Boolean, default=True, index=True)
    priority = Column(Integer, default=0, index=True)  # 优先级（越大越高）
    
    # NSFW 策略
    nsfw_policy = Column(String(50), default="block")  # "allow", "block", "separate_channel"
    
    # 审批配置
    approval_required = Column(Boolean, default=False)  # 是否需要人工审批
    auto_approve_conditions = Column(JSON)  # 自动审批条件（可选）
    
    # 限流配置
    rate_limit = Column(Integer)  # 每小时最大推送数（可选）
    time_window = Column(Integer)  # 时间窗口（秒）
    
    # 模板ID（预留）
    template_id = Column(String(100))

    # 渲染配置（用于个性化推送内容格式）
    render_config = Column(JSON, nullable=True)

    # 时间戳
    created_at = Column(DateTime, default=utcnow)
    updated_at = Column(DateTime, default=utcnow, onupdate=utcnow)


class DistributionTarget(Base):
    """分发目标表（M4 分发引擎 - 重构后）"""
    __tablename__ = "distribution_targets"
    
    id = Column(Integer, primary_key=True, index=True)
    
    # 外键关联
    rule_id = Column(Integer, ForeignKey("distribution_rules.id", ondelete="CASCADE"), nullable=False, index=True)
    bot_chat_id = Column(Integer, ForeignKey("bot_chats.id", ondelete="CASCADE"), nullable=False, index=True)
    
    # 目标配置
    enabled = Column(Boolean, default=True, index=True)
    
    # 发送选项（平台特定）
    merge_forward = Column(Boolean, default=False)  # QQ 合并转发
    use_author_name = Column(Boolean, default=True)  # 显示原作者名
    summary = Column(String(200))  # 合并转发显示名
    
    # 渲染覆盖（优先级高于规则级 render_config）
    render_config_override = Column(JSON)  # 覆盖规则级 render_config
    
    # 时间戳
    created_at = Column(DateTime, default=utcnow)
    updated_at = Column(DateTime, default=utcnow, onupdate=utcnow)
    
    # 关系
    rule = relationship(
        "DistributionRule",
        backref=backref("distribution_targets", cascade="all, delete-orphan", passive_deletes=True),
    )
    bot_chat = relationship("BotChat", backref="distribution_targets")
    
    # 唯一约束：同一规则不能重复添加同一目标
    __table_args__ = (
        Index("idx_rule_chat", "rule_id", "bot_chat_id", unique=True),
    )


class TaskStatus(str, Enum):
    """任务状态"""
    PENDING = "pending"
    RUNNING = "running"
    COMPLETED = "completed"
    FAILED = "failed"


class Task(Base):
    """任务表（用于SQLite队列模式）"""
    __tablename__ = "tasks"
    
    id = Column(Integer, primary_key=True, index=True)
    task_type = Column(String(100), nullable=False)  # "parse_content"
    payload = Column(JSON, nullable=False)  # {"content_id": 123}
    status = Column(SQLEnum(TaskStatus, native_enum=False, values_callable=lambda x: [e.value for e in x]), default=TaskStatus.PENDING, index=True)  # 按枚举 value（小写）存储
    priority = Column(Integer, default=0, index=True)  # 越大越优先
    retry_count = Column(Integer, default=0)
    max_retries = Column(Integer, default=3)
    last_error = Column(Text)
    
    created_at = Column(DateTime, default=utcnow, index=True)
    started_at = Column(DateTime)
    completed_at = Column(DateTime)


class SystemSetting(Base):
    """系统动态设置表"""
    __tablename__ = "system_settings"
    
    key = Column(String(100), primary_key=True, index=True)
    value = Column(JSON, nullable=False)  # 存储各种格式的配置（JSON 格式）
    category = Column(String(50), index=True) # platform, storage, general, etc.
    description = Column(Text)
    updated_at = Column(DateTime, default=utcnow, onupdate=utcnow)

class BotChatType(str, Enum):
    """Bot 聊天类型"""
    CHANNEL = "channel"     # TG 频道
    GROUP = "group"         # TG 普通群组
    SUPERGROUP = "supergroup"  # TG 超级群组
    PRIVATE = "private"     # TG 私聊
    QQ_GROUP = "qq_group"   # QQ 群
    QQ_PRIVATE = "qq_private"  # QQ 私聊


class BotConfigPlatform(str, Enum):
    """Bot 配置平台"""
    TELEGRAM = "telegram"
    QQ = "qq"


class BotConfig(Base):
    """Bot 配置（支持多 Bot 管理）"""
    __tablename__ = "bot_configs"

    id = Column(Integer, primary_key=True, index=True)
    platform = Column(
        SQLEnum(BotConfigPlatform, native_enum=False, values_callable=lambda x: [e.value for e in x]),
        nullable=False,
        index=True,
    )
    name = Column(String(100), nullable=False)

    # Telegram
    bot_token = Column(String(300))

    # Napcat / QQ
    napcat_http_url = Column(String(300))
    napcat_ws_url = Column(String(300))
    napcat_access_token = Column(String(300))

    # 状态
    enabled = Column(Boolean, default=True, index=True)
    is_primary = Column(Boolean, default=False, index=True)

    # 元数据
    bot_id = Column(String(50))
    bot_username = Column(String(100))

    created_at = Column(DateTime, default=utcnow)
    updated_at = Column(DateTime, default=utcnow, onupdate=utcnow)

    chats = relationship("BotChat", back_populates="bot_config")


class BotChat(Base):
    """Bot 关联的聊天/群组/频道"""
    __tablename__ = "bot_chats"
    
    id = Column(Integer, primary_key=True, index=True)

    __table_args__ = (
        Index("ix_bot_chats_bot_config_chat", "bot_config_id", "chat_id", unique=True),
    )

    bot_config_id = Column(Integer, ForeignKey("bot_configs.id", ondelete="CASCADE"), nullable=False, index=True)
    
    # Telegram 聊天信息
    chat_id = Column(String(50), nullable=False, index=True)  # Telegram/QQ chat_id
    chat_type = Column(SQLEnum(BotChatType, native_enum=False, values_callable=lambda x: [e.value for e in x]), nullable=False)  # 按枚举 value（小写）存储
    title = Column(String(200))  # 群组/频道名称
    username = Column(String(100))  # @username（可选）
    description = Column(Text)  # 群组描述
    
    # 成员信息
    member_count = Column(Integer)  # 成员数量
    
    # Bot 权限状态
    is_admin = Column(Boolean, default=False)  # Bot 是否为管理员
    can_post = Column(Boolean, default=False)  # 是否可以发送消息
    
    # 分发配置
    enabled = Column(Boolean, default=True, index=True)  # 是否启用此目标
    
    # NSFW 路由（备用频道指针，非策略）
    nsfw_chat_id = Column(String(50))  # NSFW 内容的备用频道/群组
    
    # 统计
    total_pushed = Column(Integer, default=0)  # 累计推送数
    last_pushed_at = Column(DateTime)  # 最后推送时间
    
    # 元数据
    raw_data = Column(JSON)  # 原始 Telegram Chat 数据
    
    # 可访问性标记（同步时检测）
    is_accessible = Column(Boolean, default=True)  # Bot 是否还能访问该群组
    last_sync_at = Column(DateTime)  # 最后同步时间
    sync_error = Column(String(500))  # 同步错误信息
    
    @property
    def platform_type(self) -> str:
        """根据 chat_type 自动推断平台"""
        if self.chat_type in [BotChatType.QQ_GROUP, BotChatType.QQ_PRIVATE]:
            return "qq"
        if self.chat_type in [BotChatType.CHANNEL, BotChatType.GROUP, BotChatType.SUPERGROUP, BotChatType.PRIVATE]:
            return "telegram"
        # 未识别类型时默认按 telegram 处理
        return "telegram"
    
    created_at = Column(DateTime, default=utcnow)
    updated_at = Column(DateTime, default=utcnow, onupdate=utcnow)

    bot_config = relationship("BotConfig", back_populates="chats")


class BotRuntime(Base):
    """Bot 运行时状态（单例表，只有一条记录）"""
    __tablename__ = "bot_runtime"
    
    id = Column(Integer, primary_key=True, default=1)
    
    # Bot 信息
    bot_id = Column(String(50))  # Telegram Bot ID
    bot_username = Column(String(100))  # @username
    bot_first_name = Column(String(200))  # Bot 显示名
    
    # 运行状态
    started_at = Column(DateTime)  # 进程启动时间
    last_heartbeat_at = Column(DateTime)  # 最后心跳时间
    version = Column(String(50))  # 版本号
    
    # 错误信息
    last_error = Column(Text)  # 最后错误信息
    last_error_at = Column(DateTime)  # 最后错误时间
    
    updated_at = Column(DateTime, default=utcnow, onupdate=utcnow)


class QueueItemStatus(str, Enum):
    """队列项状态"""
    PENDING = "pending"          # 待处理
    SCHEDULED = "scheduled"      # 已排期
    PROCESSING = "processing"    # 推送中
    SUCCESS = "success"          # 推送成功
    FAILED = "failed"            # 推送失败
    SKIPPED = "skipped"          # 已跳过（重复/NSFW等）
    CANCELED = "canceled"        # 已取消


class ContentQueueItem(Base):
    """内容队列项 - 每个 (Content × Rule × BotChat) 组合是独立的队列项"""
    __tablename__ = "content_queue_items"
    
    __table_args__ = (
        UniqueConstraint("content_id", "rule_id", "bot_chat_id", name="uq_queue_content_rule_chat"),
        Index("ix_queue_status_scheduled", "status", "scheduled_at"),
        Index("ix_queue_content_status", "content_id", "status"),
        Index("ix_queue_rule_status", "rule_id", "status"),
        Index("ix_queue_chat_status", "bot_chat_id", "status"),
        Index("ix_queue_next_attempt", "status", "next_attempt_at"),
    )
    
    id = Column(Integer, primary_key=True, index=True)
    
    # 三元组关联
    content_id = Column(Integer, ForeignKey("contents.id", ondelete="CASCADE"), nullable=False, index=True)
    rule_id = Column(Integer, ForeignKey("distribution_rules.id", ondelete="CASCADE"), nullable=False, index=True)
    bot_chat_id = Column(Integer, ForeignKey("bot_chats.id", ondelete="CASCADE"), nullable=False, index=True)
    
    # 缓存的目标信息（避免推送时额外查询）
    target_platform = Column(String(20), nullable=False)  # telegram | qq
    target_id = Column(String(200), nullable=False)  # chat_id
    
    # 状态
    status = Column(SQLEnum(QueueItemStatus, native_enum=False, values_callable=lambda x: [e.value for e in x]), default=QueueItemStatus.PENDING, nullable=False, index=True)
    priority = Column(Integer, default=0, index=True)
    scheduled_at = Column(DateTime, index=True)
    
    # 预处理缓存
    rendered_payload = Column(JSON)  # 预渲染的推送内容
    nsfw_routing_result = Column(JSON)  # NSFW 路由决策
    passed_rate_limit = Column(Boolean, default=True)
    rate_limit_reason = Column(String(200))
    
    # 审批
    needs_approval = Column(Boolean, default=False)
    approved_at = Column(DateTime)
    approved_by = Column(String(100))
    
    # 重试与锁
    attempt_count = Column(Integer, default=0)
    max_attempts = Column(Integer, default=3)
    next_attempt_at = Column(DateTime)
    locked_at = Column(DateTime)
    locked_by = Column(String(100))
    
    # 推送结果
    message_id = Column(String(200))
    last_error = Column(Text)
    last_error_type = Column(String(200))
    last_error_at = Column(DateTime)
    
    # 时间戳
    started_at = Column(DateTime)
    completed_at = Column(DateTime)
    created_at = Column(DateTime, default=utcnow)
    updated_at = Column(DateTime, default=utcnow, onupdate=utcnow)
    
    # 关系
    content = relationship("Content")
    rule = relationship("DistributionRule")
    bot_chat = relationship("BotChat")
