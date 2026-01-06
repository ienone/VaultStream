"""
数据库模型定义
"""
from datetime import datetime, timezone
from enum import Enum
from typing import Optional, List
from sqlalchemy import Column, Integer, String, DateTime, Boolean, Text, ForeignKey, Enum as SQLEnum, UniqueConstraint, JSON
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
    """推送记录表"""
    __tablename__ = "pushed_records"
    
    id = Column(Integer, primary_key=True, index=True)
    content_id = Column(Integer, ForeignKey("contents.id"), nullable=False, index=True)
    target_platform = Column(String(100), nullable=False)  # TG_CHANNEL_A, QQ_GROUP_B 等
    message_id = Column(String(200))  # 推送后的消息ID
    pushed_at = Column(DateTime, default=utcnow, index=True)
    
    # 关系
    content = relationship("Content", back_populates="pushed_records")


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
