"""
基础模型定义和共享枚举
"""
from datetime import datetime, timezone
from enum import Enum
from typing import Optional, List, Any
from sqlalchemy import String, Text, JSON, Integer, Float, DateTime, Boolean, ForeignKey, Index, UniqueConstraint
from sqlalchemy import Enum as SQLEnum
from sqlalchemy.orm import DeclarativeBase, Mapped, mapped_column

from app.core.time_utils import utcnow


class Base(DeclarativeBase):
    pass

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
    TELEGRAM = "telegram"
    RSS = "rss"

class TaskStatus(str, Enum):
    """任务状态"""
    PENDING = "pending"
    RUNNING = "running"
    COMPLETED = "completed"
    FAILED = "failed"


class DiscoveryState(str, Enum):
    """发现缓冲区生命周期状态"""
    INGESTED = "ingested"    # 刚采集，等待 AI 评分
    SCORED = "scored"        # 已评分，低于阈值的自动标记 ignored
    VISIBLE = "visible"      # 通过阈值，可在探索界面展示
    PROMOTED = "promoted"    # 用户已收藏至主库
    IGNORED = "ignored"      # 用户手动忽略或低分自动忽略
    MERGED = "merged"        # 被合并入另一条内容，不再独立展示
    EXPIRED = "expired"      # 超过保留期限，等待清理任务删除


class DiscoverySourceKind(str, Enum):
    """发现来源类型"""
    RSS = "rss"
    HACKERNEWS = "hackernews"
    REDDIT = "reddit"
    GITHUB = "github"
    TELEGRAM_CHANNEL = "telegram_channel"
