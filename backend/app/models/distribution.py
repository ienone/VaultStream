"""
分发与规则模型定义
"""
from datetime import datetime
from typing import Optional, Any
from sqlalchemy import String, Text, JSON, Integer, DateTime, Boolean, ForeignKey, Index
from sqlalchemy.orm import relationship, backref, Mapped, mapped_column

from app.core.time_utils import utcnow
from app.models.base import Base


class DistributionRule(Base):
    """分发规则表（M4 分发引擎）"""
    __tablename__ = "distribution_rules"
    
    id: Mapped[int] = mapped_column(Integer, primary_key=True, index=True)
    
    name: Mapped[str] = mapped_column(String(200), unique=True)
    description: Mapped[Optional[str]] = mapped_column(Text, default=None)
    
    match_conditions: Mapped[Any] = mapped_column(JSON)
    
    enabled: Mapped[bool] = mapped_column(Boolean, default=True, index=True)
    priority: Mapped[int] = mapped_column(Integer, default=0, index=True)
    
    nsfw_policy: Mapped[Optional[str]] = mapped_column(String(50), default="block")
    
    approval_required: Mapped[bool] = mapped_column(Boolean, default=False)
    auto_approve_conditions: Mapped[Optional[Any]] = mapped_column(JSON, default=None)
    
    rate_limit: Mapped[Optional[int]] = mapped_column(Integer, default=None)
    time_window: Mapped[Optional[int]] = mapped_column(Integer, default=None)
    
    template_id: Mapped[Optional[str]] = mapped_column(String(100), default=None)
    render_config: Mapped[Optional[Any]] = mapped_column(JSON, default=None)

    created_at: Mapped[Optional[datetime]] = mapped_column(DateTime, default=utcnow)
    updated_at: Mapped[Optional[datetime]] = mapped_column(DateTime, default=utcnow, onupdate=utcnow)


class DistributionTarget(Base):
    """分发目标表（M4 分发引擎 - 重构后）"""
    __tablename__ = "distribution_targets"
    
    id: Mapped[int] = mapped_column(Integer, primary_key=True, index=True)
    
    rule_id: Mapped[int] = mapped_column(Integer, ForeignKey("distribution_rules.id", ondelete="CASCADE"), index=True)
    bot_chat_id: Mapped[int] = mapped_column(Integer, ForeignKey("bot_chats.id", ondelete="CASCADE"), index=True)
    
    enabled: Mapped[bool] = mapped_column(Boolean, default=True, index=True)
    
    merge_forward: Mapped[bool] = mapped_column(Boolean, default=False)
    use_author_name: Mapped[bool] = mapped_column(Boolean, default=True)
    summary: Mapped[Optional[str]] = mapped_column(String(200), default=None)
    
    render_config_override: Mapped[Optional[Any]] = mapped_column(JSON, default=None)
    
    created_at: Mapped[Optional[datetime]] = mapped_column(DateTime, default=utcnow)
    updated_at: Mapped[Optional[datetime]] = mapped_column(DateTime, default=utcnow, onupdate=utcnow)
    
    rule = relationship(
        "DistributionRule",
        backref=backref("distribution_targets", cascade="all, delete-orphan", passive_deletes=True),
    )
    bot_chat = relationship("BotChat", backref="distribution_targets")
    
    __table_args__ = (
        Index("idx_rule_chat", "rule_id", "bot_chat_id", unique=True),
    )
