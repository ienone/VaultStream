"""
数据库模型定义
"""
from datetime import datetime, timezone
from enum import Enum
from typing import Optional, List
from sqlalchemy import Column, Integer, String, DateTime, Boolean, Text, ForeignKey, Enum as SQLEnum, UniqueConstraint, JSON, Index
from sqlalchemy.dialects.postgresql import JSONB
from sqlalchemy.ext.declarative import declarative_base
from sqlalchemy.orm import relationship

Base = declarative_base()


def utcnow() -> datetime:
    """返回UTC 时间的当前时间戳。"""
    return datetime.now(timezone.utc).replace(tzinfo=None)


# JSON 类型适配器：PostgreSQL 用 JSONB，SQLite 用 JSON
def get_json_type():
    """根据数据库类型返回合适的 JSON 字段类型"""
    try:
        from app.config import settings
        if settings.database_type == "postgresql":
            return JSONB
    except:
        pass
    return JSON


class ContentStatus(str, Enum):
    """内容状态"""
    UNPROCESSED = "unprocessed"  # 未处理
    PROCESSING = "processing"    # 处理中
    PULLED = "pulled"            # 已抓取
    DISTRIBUTED = "distributed"  # 兼容旧数据：不再作为主状态机语义
    FAILED = "failed"            # 失败
    ARCHIVED = "archived"        # 已归档


class ReviewStatus(str, Enum):
    """内容审核状态（M4 审批流）"""
    PENDING = "PENDING"      # 待审核
    APPROVED = "APPROVED"    # 已批准
    REJECTED = "REJECTED"    # 已拒绝
    AUTO_APPROVED = "AUTO_APPROVED"  # 自动批准


class Platform(str, Enum):
    """支持的平台"""
    BILIBILI = "bilibili"
    TWITTER = "twitter"
    XIAOHONGSHU = "xiaohongshu"
    DOUYIN = "douyin"
    WEIBO = "weibo"
    ZHIHU = "zhihu"
    KU_AN="ku_an"


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
    )
    
    id = Column(Integer, primary_key=True, index=True)
    platform = Column(SQLEnum(Platform), nullable=False, index=True)
    url = Column(Text, nullable=False)  # 原始输入
    canonical_url = Column(Text, index=True)  # 用于去重的规范化URL
    clean_url = Column(Text)  # 解析后的净化URL
    status = Column(SQLEnum(ContentStatus), default=ContentStatus.UNPROCESSED, index=True)

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
    
    # 标签和分类
    tags = Column(JSON, default=list)  # 用户自定义标签
    is_nsfw = Column(Boolean, default=False)
    source = Column(String(100))  # 来源标识
    
    # 平台特有 ID (如 BV号, 推文ID)
    platform_id = Column(String(100), index=True)
    # 平台特有内容类型 (如 B站的 video, live, dynamic)
    content_type = Column(String(50), index=True)
    
    # 添加以下兼容性属性，以便 Pydantic 模型 ContentDetail 能够正确验证
    @property
    def bilibili_id(self):
        """映射 platform_id 到 bilibili_id（仅 B站有效）"""
        if self.platform == Platform.BILIBILI:
            return self.platform_id
        return None

    @property
    def bilibili_type(self):
        """映射 content_type 到 bilibili_type（仅 B站有效）"""
        if self.platform == Platform.BILIBILI:
            return self.content_type
        return None
    
    @property
    def author_avatar_url(self) -> Optional[str]:
        """从 raw_metadata 中提取作者头像 URL"""
        try:
            if not self.raw_metadata:
                return None
            
            if self.platform == Platform.WEIBO:
                # 微博博主主页
                if self.content_type == "user_profile":
                    return self.raw_metadata.get("avatar_hd")
                # 微博正文
                return self.raw_metadata.get("user", {}).get("avatar_hd") or \
                       self.raw_metadata.get("user", {}).get("profile_image_url")
            
            if self.platform == Platform.BILIBILI:
                return self.raw_metadata.get("author", {}).get("face") or \
                       self.raw_metadata.get("owner", {}).get("face")
            
            if self.platform == Platform.TWITTER:
                return self.raw_metadata.get("user", {}).get("profile_image_url_https")
                
        except Exception:
            pass
        return None
    
    # 通用互动数据
    view_count = Column(Integer, default=0)
    like_count = Column(Integer, default=0)
    collect_count = Column(Integer, default=0)
    share_count = Column(Integer, default=0)
    comment_count = Column(Integer, default=0)
    
    # 平台特有扩展数据 (如 B站投币、转发等)
    extra_stats = Column(JSON, default=dict)
    
    # 元数据（JSON存储）
    raw_metadata = Column(JSON)  # 原始平台数据
    
    # 提取的通用字段
    title = Column(Text)
    description = Column(Text)
    author_name = Column(String(200))
    author_id = Column(String(100))
    cover_url = Column(Text)
    cover_color = Column(String(20))  # M5: 封面主色调 (Hex)
    media_urls = Column(JSON, default=list)  # 媒体资源URL列表
    
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
    target_id = Column(String(200), nullable=False, index=True)  # 频道/群组 ID（如 @channel_name, -1001234567890）
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
    
    # 目标配置（JSON 数组）
    # 示例: [{"platform": "telegram", "target_id": "@my_channel", "enabled": true}]
    targets = Column(JSON, nullable=False, default=list)
    
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
    
    # 时间戳
    created_at = Column(DateTime, default=utcnow)
    updated_at = Column(DateTime, default=utcnow, onupdate=utcnow)


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
    status = Column(SQLEnum(TaskStatus), default=TaskStatus.PENDING, index=True)
    priority = Column(Integer, default=0, index=True)  # 越大越优先
    retry_count = Column(Integer, default=0)
    max_retries = Column(Integer, default=3)
    last_error = Column(Text)
    
    created_at = Column(DateTime, default=utcnow, index=True)
    started_at = Column(DateTime)
    completed_at = Column(DateTime)


class WeiboUser(Base):
    """微博用户存档表"""
    __tablename__ = "weibo_users"
    
    id = Column(Integer, primary_key=True, index=True)
    platform_id = Column(String(50), nullable=False, unique=True, index=True) # Weibo UID
    
    nick_name = Column(String(100), nullable=False)
    avatar_hd = Column(Text)
    description = Column(Text)
    
    followers_count = Column(Integer, default=0)
    friends_count = Column(Integer, default=0)
    statuses_count = Column(Integer, default=0)
    
    verified = Column(Boolean, default=False)
    verified_type = Column(Integer)
    verified_reason = Column(Text)
    
    gender = Column(String(10)) # m, f
    location = Column(String(100))
    
    # 原始数据
    raw_data = Column(JSON)
    
    created_at = Column(DateTime, default=utcnow)
    updated_at = Column(DateTime, default=utcnow, onupdate=utcnow)
