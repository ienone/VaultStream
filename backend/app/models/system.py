"""
系统、任务与队列相关模型定义
"""
from datetime import datetime
from enum import Enum
from typing import Optional, Any
from sqlalchemy import String, Text, JSON, Integer, DateTime, Boolean, ForeignKey, Index, UniqueConstraint
from sqlalchemy import Enum as SQLEnum
from sqlalchemy.orm import relationship, Mapped, mapped_column

from app.core.time_utils import utcnow
from app.models.base import Base, TaskStatus


class Task(Base):
    """任务表（用于SQLite队列模式）"""
    __tablename__ = "tasks"
    
    id: Mapped[int] = mapped_column(Integer, primary_key=True, index=True)
    task_type: Mapped[str] = mapped_column(String(100))  # "parse_content"
    payload: Mapped[Any] = mapped_column(JSON)  # {"content_id": 123}
    status: Mapped[Optional[TaskStatus]] = mapped_column(SQLEnum(TaskStatus, native_enum=False, values_callable=lambda x: [e.value for e in x]), default=TaskStatus.PENDING, index=True)
    priority: Mapped[int] = mapped_column(Integer, default=0, index=True)
    retry_count: Mapped[int] = mapped_column(Integer, default=0)
    max_retries: Mapped[int] = mapped_column(Integer, default=3)
    last_error: Mapped[Optional[str]] = mapped_column(Text, default=None)
    
    created_at: Mapped[Optional[datetime]] = mapped_column(DateTime, default=utcnow, index=True)
    started_at: Mapped[Optional[datetime]] = mapped_column(DateTime, default=None)
    completed_at: Mapped[Optional[datetime]] = mapped_column(DateTime, default=None)


class SystemSetting(Base):
    """系统动态设置表"""
    __tablename__ = "system_settings"
    
    key: Mapped[str] = mapped_column(String(100), primary_key=True)
    value: Mapped[Any] = mapped_column(JSON)
    category: Mapped[Optional[str]] = mapped_column(String(50), index=True, default=None) # platform, storage, general, etc.
    description: Mapped[Optional[str]] = mapped_column(Text, default=None)
    updated_at: Mapped[Optional[datetime]] = mapped_column(DateTime, default=utcnow, onupdate=utcnow)


class PushedRecord(Base):
    """推送记录表（M4 扩展：记录 message_id 和 target_id）"""
    __tablename__ = "pushed_records"
    
    __table_args__ = (
        UniqueConstraint("content_id", "target_id", name="uq_pushed_records_content_target"),
        Index("ix_pushed_records_target_id", "target_id"),
    )
    
    id: Mapped[int] = mapped_column(Integer, primary_key=True, index=True)
    content_id: Mapped[int] = mapped_column(Integer, ForeignKey("contents.id"), index=True)
    
    # M4 扩展字段
    target_platform: Mapped[str] = mapped_column(String(100))  # "telegram", "qq" 等
    target_id: Mapped[str] = mapped_column(String(200))  # 频道/群组 ID
    message_id: Mapped[Optional[str]] = mapped_column(String(200), default=None)  # 推送后的消息ID
    
    # 推送状态
    push_status: Mapped[Optional[str]] = mapped_column(String(50), default="success")  # success/failed/pending
    error_message: Mapped[Optional[str]] = mapped_column(Text, default=None)  # 失败原因
    
    pushed_at: Mapped[Optional[datetime]] = mapped_column(DateTime, default=utcnow, index=True)
    
    # 关系
    content = relationship("Content", back_populates="pushed_records")


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
    
    id: Mapped[int] = mapped_column(Integer, primary_key=True, index=True)
    
    # 三元组关联
    content_id: Mapped[int] = mapped_column(Integer, ForeignKey("contents.id", ondelete="CASCADE"), index=True)
    rule_id: Mapped[int] = mapped_column(Integer, ForeignKey("distribution_rules.id", ondelete="CASCADE"), index=True)
    bot_chat_id: Mapped[int] = mapped_column(Integer, ForeignKey("bot_chats.id", ondelete="CASCADE"), index=True)
    
    # 缓存的目标信息
    target_platform: Mapped[str] = mapped_column(String(20))
    target_id: Mapped[str] = mapped_column(String(200))
    
    # 状态
    status: Mapped[QueueItemStatus] = mapped_column(SQLEnum(QueueItemStatus, native_enum=False, values_callable=lambda x: [e.value for e in x]), default=QueueItemStatus.PENDING, index=True)
    priority: Mapped[int] = mapped_column(Integer, default=0, index=True)
    scheduled_at: Mapped[Optional[datetime]] = mapped_column(DateTime, index=True, default=None)
    
    # 预处理缓存
    rendered_payload: Mapped[Optional[Any]] = mapped_column(JSON, default=None)
    nsfw_routing_result: Mapped[Optional[Any]] = mapped_column(JSON, default=None)
    passed_rate_limit: Mapped[bool] = mapped_column(Boolean, default=True)
    rate_limit_reason: Mapped[Optional[str]] = mapped_column(String(200), default=None)
    
    # 审批
    needs_approval: Mapped[bool] = mapped_column(Boolean, default=False)
    approved_at: Mapped[Optional[datetime]] = mapped_column(DateTime, default=None)
    approved_by: Mapped[Optional[str]] = mapped_column(String(100), default=None)
    
    # 重试与锁
    attempt_count: Mapped[int] = mapped_column(Integer, default=0)
    max_attempts: Mapped[int] = mapped_column(Integer, default=3)
    next_attempt_at: Mapped[Optional[datetime]] = mapped_column(DateTime, default=None)
    locked_at: Mapped[Optional[datetime]] = mapped_column(DateTime, default=None)
    locked_by: Mapped[Optional[str]] = mapped_column(String(100), default=None)
    
    # 推送结果
    message_id: Mapped[Optional[str]] = mapped_column(String(200), default=None)
    last_error: Mapped[Optional[str]] = mapped_column(Text, default=None)
    last_error_type: Mapped[Optional[str]] = mapped_column(String(200), default=None)
    last_error_at: Mapped[Optional[datetime]] = mapped_column(DateTime, default=None)
    
    # 时间戳
    started_at: Mapped[Optional[datetime]] = mapped_column(DateTime, default=None)
    completed_at: Mapped[Optional[datetime]] = mapped_column(DateTime, default=None)
    created_at: Mapped[Optional[datetime]] = mapped_column(DateTime, default=utcnow)
    updated_at: Mapped[Optional[datetime]] = mapped_column(DateTime, default=utcnow, onupdate=utcnow)
    
    # 关系
    content = relationship("Content")
    rule = relationship("DistributionRule")
    bot_chat = relationship("BotChat")
