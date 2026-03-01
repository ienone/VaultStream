"""
系统、任务与队列相关模型定义
"""
from datetime import datetime
from enum import Enum
from sqlalchemy import Column, Integer, String, DateTime, Boolean, Text, ForeignKey, Enum as SQLEnum, UniqueConstraint, JSON, Index
from sqlalchemy.orm import relationship

from app.core.time_utils import utcnow
from app.models.base import Base, TaskStatus


class Task(Base):
    """任务表（用于SQLite队列模式）"""
    __tablename__ = "tasks"
    
    id = Column(Integer, primary_key=True, index=True)
    task_type = Column(String(100), nullable=False)  # "parse_content"
    payload = Column(JSON, nullable=False)  # {"content_id": 123}
    status = Column(SQLEnum(TaskStatus, native_enum=False, values_callable=lambda x: [e.value for e in x]), default=TaskStatus.PENDING, index=True)
    priority = Column(Integer, default=0, index=True)
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
    value = Column(JSON, nullable=False)
    category = Column(String(50), index=True) # platform, storage, general, etc.
    description = Column(Text)
    updated_at = Column(DateTime, default=utcnow, onupdate=utcnow)


class PushedRecord(Base):
    """推送记录表（M4 扩展：记录 message_id 和 target_id）"""
    __tablename__ = "pushed_records"
    
    __table_args__ = (
        UniqueConstraint("content_id", "target_id", name="uq_pushed_records_content_target"),
        Index("ix_pushed_records_target_id", "target_id"),
    )
    
    id = Column(Integer, primary_key=True, index=True)
    content_id = Column(Integer, ForeignKey("contents.id"), nullable=False, index=True)
    
    # M4 扩展字段
    target_platform = Column(String(100), nullable=False)  # "telegram", "qq" 等
    target_id = Column(String(200), nullable=False)  # 频道/群组 ID
    message_id = Column(String(200))  # 推送后的消息ID
    
    # 推送状态
    push_status = Column(String(50), default="success")  # success/failed/pending
    error_message = Column(Text)  # 失败原因
    
    pushed_at = Column(DateTime, default=utcnow, index=True)
    
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
    
    id = Column(Integer, primary_key=True, index=True)
    
    # 三元组关联
    content_id = Column(Integer, ForeignKey("contents.id", ondelete="CASCADE"), nullable=False, index=True)
    rule_id = Column(Integer, ForeignKey("distribution_rules.id", ondelete="CASCADE"), nullable=False, index=True)
    bot_chat_id = Column(Integer, ForeignKey("bot_chats.id", ondelete="CASCADE"), nullable=False, index=True)
    
    # 缓存的目标信息
    target_platform = Column(String(20), nullable=False)
    target_id = Column(String(200), nullable=False)
    
    # 状态
    status = Column(SQLEnum(QueueItemStatus, native_enum=False, values_callable=lambda x: [e.value for e in x]), default=QueueItemStatus.PENDING, nullable=False, index=True)
    priority = Column(Integer, default=0, index=True)
    scheduled_at = Column(DateTime, index=True)
    
    # 预处理缓存
    rendered_payload = Column(JSON)
    nsfw_routing_result = Column(JSON)
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
