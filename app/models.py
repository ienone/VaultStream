"""
数据库模型定义
"""
from datetime import datetime
from enum import Enum
from typing import Optional, List
from sqlalchemy import Column, Integer, String, DateTime, Boolean, Text, ForeignKey, JSON, Enum as SQLEnum
from sqlalchemy.ext.declarative import declarative_base
from sqlalchemy.orm import relationship

Base = declarative_base()


class ContentStatus(str, Enum):
    """内容状态"""
    UNPROCESSED = "unprocessed"  # 未处理
    PROCESSING = "processing"    # 处理中
    PULLED = "pulled"            # 已抓取
    DISTRIBUTED = "distributed"  # 已分发
    FAILED = "failed"            # 失败
    ARCHIVED = "archived"        # 已归档


class Platform(str, Enum):
    """支持的平台"""
    BILIBILI = "bilibili"
    TWITTER = "twitter"
    XIAOHONGSHU = "xiaohongshu"
    WEIBO = "weibo"
    ZHIHU = "zhihu"


class BilibiliContentType(str, Enum):
    """B站内容类型"""
    VIDEO = "video"          # 视频
    ARTICLE = "article"      # 专栏文章
    DYNAMIC = "dynamic"      # 动态
    BANGUMI = "bangumi"      # 番剧
    AUDIO = "audio"          # 音频
    LIVE = "live"            # 直播
    CHEESE = "cheese"        # 课程


class Content(Base):
    """内容表"""
    __tablename__ = "contents"
    
    id = Column(Integer, primary_key=True, index=True)
    platform = Column(SQLEnum(Platform), nullable=False, index=True)
    url = Column(Text, nullable=False)
    clean_url = Column(Text)  # 净化后的URL
    status = Column(SQLEnum(ContentStatus), default=ContentStatus.UNPROCESSED, index=True)
    
    # 标签和分类
    tags = Column(JSON, default=list)  # 用户自定义标签
    is_nsfw = Column(Boolean, default=False)
    source = Column(String(100))  # 来源标识
    
    # 平台特有 ID (如 BV号, 推文ID)
    platform_id = Column(String(100), index=True)
    
    # 添加以下兼容性属性，以便 Pydantic 模型 ContentDetail 能够正确验证
    @property
    def bilibili_id(self):
        """映射 platform_id 到 bilibili_id"""
        return self.platform_id

    @property
    def bilibili_type(self):
        """从 raw_metadata 中提取类型，或者返回默认值"""
        if self.raw_metadata and isinstance(self.raw_metadata, dict):
            # 尝试从原始数据中获取分区名或类型
            return self.raw_metadata.get('tname') or "video"
        return "video"
    
    # 通用互动数据
    view_count = Column(Integer, default=0)
    like_count = Column(Integer, default=0)
    collect_count = Column(Integer, default=0)
    share_count = Column(Integer, default=0)
    comment_count = Column(Integer, default=0)
    
    # 平台特有扩展数据 (如 B站投币、转发等)
    extra_stats = Column(JSON, default=dict)
    
    # 元数据（JSONB存储）
    raw_metadata = Column(JSON)  # 原始平台数据
    
    # 提取的通用字段
    title = Column(Text)
    description = Column(Text)
    author_name = Column(String(200))
    author_id = Column(String(100))
    cover_url = Column(Text)
    media_urls = Column(JSON, default=list)  # 媒体资源URL列表
    
    # 时间戳
    created_at = Column(DateTime, default=datetime.utcnow, index=True)
    updated_at = Column(DateTime, default=datetime.utcnow, onupdate=datetime.utcnow)
    published_at = Column(DateTime)  # 原始发布时间
    
    # 关系
    pushed_records = relationship("PushedRecord", back_populates="content")


class PushedRecord(Base):
    """推送记录表"""
    __tablename__ = "pushed_records"
    
    id = Column(Integer, primary_key=True, index=True)
    content_id = Column(Integer, ForeignKey("contents.id"), nullable=False, index=True)
    target_platform = Column(String(100), nullable=False)  # TG_CHANNEL_A, QQ_GROUP_B 等
    message_id = Column(String(200))  # 推送后的消息ID
    pushed_at = Column(DateTime, default=datetime.utcnow, index=True)
    
    # 关系
    content = relationship("Content", back_populates="pushed_records")
