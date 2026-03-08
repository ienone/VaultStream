"""
内容与来源相关模型定义
"""
from datetime import datetime
from enum import Enum
from typing import Optional, Any
from sqlalchemy import String, Text, JSON, Integer, Float, DateTime, Boolean, ForeignKey, Index, UniqueConstraint
from sqlalchemy import Enum as SQLEnum
from sqlalchemy.orm import relationship, Mapped, mapped_column

from app.core.time_utils import utcnow
from app.models.base import Base, Platform, ContentStatus, LayoutType, ReviewStatus, DiscoveryState, DiscoverySourceKind


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
        Index("ix_contents_platform_created_at", "platform", "created_at"),
        Index("ix_contents_status_created_at", "status", "created_at"),
        Index("ix_contents_is_nsfw_created_at", "is_nsfw", "created_at"),
        Index("ix_contents_layout_type_created_at", "layout_type", "created_at"),
    )
    
    id: Mapped[int] = mapped_column(Integer, primary_key=True, index=True)
    platform: Mapped[Platform] = mapped_column(SQLEnum(Platform, native_enum=False, values_callable=lambda x: [e.value for e in x]), index=True)
    url: Mapped[str] = mapped_column(Text)
    canonical_url: Mapped[Optional[str]] = mapped_column(Text, index=True, default=None)
    clean_url: Mapped[Optional[str]] = mapped_column(Text, default=None)
    status: Mapped[Optional[ContentStatus]] = mapped_column(
        SQLEnum(ContentStatus, native_enum=False, values_callable=lambda x: [e.value for e in x]),
        default=ContentStatus.UNPROCESSED,
        index=True,
    )
    
    layout_type: Mapped[Optional[LayoutType]] = mapped_column(SQLEnum(LayoutType, values_callable=lambda x: [e.value for e in x]), default=None, index=True)
    layout_type_override: Mapped[Optional[LayoutType]] = mapped_column(SQLEnum(LayoutType, values_callable=lambda x: [e.value for e in x]), default=None)
    content_type: Mapped[Optional[str]] = mapped_column(String(50), index=True, default=None)

    failure_count: Mapped[int] = mapped_column(Integer, default=0)
    last_error: Mapped[Optional[str]] = mapped_column(Text, default=None)
    last_error_type: Mapped[Optional[str]] = mapped_column(String(200), default=None)
    last_error_detail: Mapped[Optional[Any]] = mapped_column(JSON, default=None)
    last_error_at: Mapped[Optional[datetime]] = mapped_column(DateTime, default=None)
    
    review_status: Mapped[Optional[ReviewStatus]] = mapped_column(SQLEnum(ReviewStatus, native_enum=False, values_callable=lambda x: [e.value for e in x]), default=ReviewStatus.PENDING, index=True)
    reviewed_at: Mapped[Optional[datetime]] = mapped_column(DateTime, default=None)
    reviewed_by: Mapped[Optional[str]] = mapped_column(String(100), default=None)
    review_note: Mapped[Optional[str]] = mapped_column(Text, default=None)
    
    queue_priority: Mapped[int] = mapped_column(Integer, default=0, index=True)
    
    tags: Mapped[Optional[Any]] = mapped_column(JSON, default=list)
    is_nsfw: Mapped[bool] = mapped_column(Boolean, default=False)
    source: Mapped[Optional[str]] = mapped_column(String(100), default=None)
    source_type: Mapped[Optional[str]] = mapped_column(String(50), default="user_submit", index=True)
    ai_score: Mapped[Optional[float]] = mapped_column(Float, default=None)
    ai_reason: Mapped[Optional[str]] = mapped_column(Text, default=None)
    ai_tags: Mapped[Optional[Any]] = mapped_column(JSON, default=list)
    discovered_at: Mapped[Optional[datetime]] = mapped_column(DateTime, default=None)
    
    discovery_state: Mapped[Optional[DiscoveryState]] = mapped_column(
        SQLEnum(DiscoveryState, native_enum=False, values_callable=lambda x: [e.value for e in x]),
        default=None,
        index=True,
    )
    expire_at: Mapped[Optional[datetime]] = mapped_column(DateTime, default=None)
    promoted_at: Mapped[Optional[datetime]] = mapped_column(DateTime, default=None)
    
    platform_id: Mapped[Optional[str]] = mapped_column(String(100), index=True, default=None)
    
    view_count: Mapped[int] = mapped_column(Integer, default=0)
    like_count: Mapped[int] = mapped_column(Integer, default=0)
    collect_count: Mapped[int] = mapped_column(Integer, default=0)
    share_count: Mapped[int] = mapped_column(Integer, default=0)
    comment_count: Mapped[int] = mapped_column(Integer, default=0)
    
    extra_stats: Mapped[Optional[Any]] = mapped_column(JSON, default=dict)
    
    # 树状结构支持 (用于事件级聚合)
    parent_id: Mapped[Optional[int]] = mapped_column(Integer, ForeignKey("contents.id"), default=None, index=True)
    is_synthesis: Mapped[bool] = mapped_column(Boolean, default=False, index=True)

    title: Mapped[Optional[str]] = mapped_column(Text, default=None)
    body: Mapped[Optional[str]] = mapped_column(Text, default=None)
    summary: Mapped[Optional[str]] = mapped_column(Text, default=None)
    author_name: Mapped[Optional[str]] = mapped_column(String(200), default=None)
    author_id: Mapped[Optional[str]] = mapped_column(String(100), default=None)
    author_avatar_url: Mapped[Optional[str]] = mapped_column("author_avatar_url", Text, default=None)
    author_url: Mapped[Optional[str]] = mapped_column(Text, default=None)
    cover_url: Mapped[Optional[str]] = mapped_column(Text, default=None)
    source_tags: Mapped[Optional[Any]] = mapped_column(JSON, default=list)

    cover_color: Mapped[Optional[str]] = mapped_column(String(20), default=None)
    media_urls: Mapped[Optional[Any]] = mapped_column(JSON, default=list)
    
    context_data: Mapped[Optional[Any]] = mapped_column(JSON, default=None)
    rich_payload: Mapped[Optional[Any]] = mapped_column(JSON, default=None)
    archive_metadata: Mapped[Optional[Any]] = mapped_column(JSON, default=None)
    
    deleted_at: Mapped[Optional[datetime]] = mapped_column(DateTime, default=None)
    
    created_at: Mapped[Optional[datetime]] = mapped_column(DateTime, default=utcnow, index=True)
    updated_at: Mapped[Optional[datetime]] = mapped_column(DateTime, default=utcnow, onupdate=utcnow)
    published_at: Mapped[Optional[datetime]] = mapped_column(DateTime, default=None)
    
    pushed_records = relationship("PushedRecord", back_populates="content")
    sources = relationship("ContentSource", back_populates="content")


class ContentSource(Base):
    """每次分享触发记录"""
    __tablename__ = "content_sources"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, index=True)
    content_id: Mapped[int] = mapped_column(Integer, ForeignKey("contents.id"), index=True)

    source: Mapped[Optional[str]] = mapped_column(String(100), default=None)
    tags_snapshot: Mapped[Optional[Any]] = mapped_column(JSON, default=list)
    note: Mapped[Optional[str]] = mapped_column(Text, default=None)
    client_context: Mapped[Optional[Any]] = mapped_column(JSON, default=None)

    created_at: Mapped[Optional[datetime]] = mapped_column(DateTime, default=utcnow, index=True)

    content = relationship("Content", back_populates="sources")


class DiscoverySource(Base):
    """发现来源配置（统一管理 RSS/HN/Reddit/GitHub/Telegram 频道）"""
    __tablename__ = "discovery_sources"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, index=True)
    kind: Mapped[DiscoverySourceKind] = mapped_column(
        SQLEnum(DiscoverySourceKind, native_enum=False, values_callable=lambda x: [e.value for e in x]),
        index=True,
    )
    name: Mapped[str] = mapped_column(String(200))
    enabled: Mapped[bool] = mapped_column(Boolean, default=True, index=True)
    config: Mapped[Optional[Any]] = mapped_column(JSON, default=dict)

    last_sync_at: Mapped[Optional[datetime]] = mapped_column(DateTime, default=None)
    last_cursor: Mapped[Optional[str]] = mapped_column(String(500), default=None)
    last_error: Mapped[Optional[str]] = mapped_column(Text, default=None)
    sync_interval_minutes: Mapped[int] = mapped_column(Integer, default=60)

    created_at: Mapped[Optional[datetime]] = mapped_column(DateTime, default=utcnow)
    updated_at: Mapped[Optional[datetime]] = mapped_column(DateTime, default=utcnow, onupdate=utcnow)
