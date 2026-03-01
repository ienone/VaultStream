"""
内容与来源相关模型定义
"""
from datetime import datetime
from enum import Enum
from sqlalchemy import Column, Integer, String, DateTime, Boolean, Text, ForeignKey, Enum as SQLEnum, UniqueConstraint, JSON, Index, Float
from sqlalchemy.orm import relationship

from app.core.time_utils import utcnow
from app.models.base import Base, Platform, ContentStatus, LayoutType, ReviewStatus


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
    
    id = Column(Integer, primary_key=True, index=True)
    platform = Column(SQLEnum(Platform, native_enum=False, values_callable=lambda x: [e.value for e in x]), nullable=False, index=True)
    url = Column(Text, nullable=False)
    canonical_url = Column(Text, index=True)
    clean_url = Column(Text)
    status = Column(
        SQLEnum(ContentStatus, native_enum=False, values_callable=lambda x: [e.value for e in x]),
        default=ContentStatus.UNPROCESSED,
        index=True,
    )
    
    layout_type = Column(SQLEnum(LayoutType, values_callable=lambda x: [e.value for e in x]), nullable=True, index=True)
    layout_type_override = Column(SQLEnum(LayoutType, values_callable=lambda x: [e.value for e in x]), nullable=True)
    content_type = Column(String(50), index=True)

    failure_count = Column(Integer, default=0)
    last_error = Column(Text)
    last_error_type = Column(String(200))
    last_error_detail = Column(JSON)
    last_error_at = Column(DateTime)
    
    review_status = Column(SQLEnum(ReviewStatus, native_enum=False, values_callable=lambda x: [e.value for e in x]), default=ReviewStatus.PENDING, index=True)
    reviewed_at = Column(DateTime)
    reviewed_by = Column(String(100))
    review_note = Column(Text)
    
    queue_priority = Column(Integer, default=0, index=True)
    
    tags = Column(JSON, default=list)
    is_nsfw = Column(Boolean, default=False)
    source = Column(String(100))
    source_type = Column(String(50), default="user_submit", index=True)
    ai_score = Column(Float, nullable=True)
    discovered_at = Column(DateTime)
    
    platform_id = Column(String(100), index=True)
    
    view_count = Column(Integer, default=0)
    like_count = Column(Integer, default=0)
    collect_count = Column(Integer, default=0)
    share_count = Column(Integer, default=0)
    comment_count = Column(Integer, default=0)
    
    extra_stats = Column(JSON, default=dict)
    
    title = Column(Text)
    body = Column(Text)
    summary = Column(Text)
    author_name = Column(String(200))
    author_id = Column(String(100))
    author_avatar_url = Column("author_avatar_url", Text)
    author_url = Column(Text)
    cover_url = Column(Text)
    source_tags = Column(JSON, default=list)

    cover_color = Column(String(20))
    media_urls = Column(JSON, default=list)
    
    context_data = Column(JSON, nullable=True)
    rich_payload = Column(JSON, nullable=True)
    archive_metadata = Column(JSON)
    
    deleted_at = Column(DateTime, nullable=True)
    
    created_at = Column(DateTime, default=utcnow, index=True)
    updated_at = Column(DateTime, default=utcnow, onupdate=utcnow)
    published_at = Column(DateTime)
    
    pushed_records = relationship("PushedRecord", back_populates="content")
    sources = relationship("ContentSource", back_populates="content")


class ContentSource(Base):
    """每次分享触发记录"""
    __tablename__ = "content_sources"

    id = Column(Integer, primary_key=True, index=True)
    content_id = Column(Integer, ForeignKey("contents.id"), nullable=False, index=True)

    source = Column(String(100))
    tags_snapshot = Column(JSON, default=list)
    note = Column(Text)
    client_context = Column(JSON)

    created_at = Column(DateTime, default=utcnow, index=True)

    content = relationship("Content", back_populates="sources")
