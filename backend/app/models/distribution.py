"""
分发与规则模型定义
"""
from datetime import datetime
from sqlalchemy import Column, Integer, String, DateTime, Boolean, Text, ForeignKey, JSON, Index
from sqlalchemy.orm import relationship, backref

from app.core.time_utils import utcnow
from app.models.base import Base


class DistributionRule(Base):
    """分发规则表（M4 分发引擎）"""
    __tablename__ = "distribution_rules"
    
    id = Column(Integer, primary_key=True, index=True)
    
    name = Column(String(200), nullable=False, unique=True)
    description = Column(Text)
    
    match_conditions = Column(JSON, nullable=False)
    
    enabled = Column(Boolean, default=True, index=True)
    priority = Column(Integer, default=0, index=True)
    
    nsfw_policy = Column(String(50), default="block")
    
    approval_required = Column(Boolean, default=False)
    auto_approve_conditions = Column(JSON)
    
    rate_limit = Column(Integer)
    time_window = Column(Integer)
    
    template_id = Column(String(100))
    render_config = Column(JSON, nullable=True)

    created_at = Column(DateTime, default=utcnow)
    updated_at = Column(DateTime, default=utcnow, onupdate=utcnow)


class DistributionTarget(Base):
    """分发目标表（M4 分发引擎 - 重构后）"""
    __tablename__ = "distribution_targets"
    
    id = Column(Integer, primary_key=True, index=True)
    
    rule_id = Column(Integer, ForeignKey("distribution_rules.id", ondelete="CASCADE"), nullable=False, index=True)
    bot_chat_id = Column(Integer, ForeignKey("bot_chats.id", ondelete="CASCADE"), nullable=False, index=True)
    
    enabled = Column(Boolean, default=True, index=True)
    
    merge_forward = Column(Boolean, default=False)
    use_author_name = Column(Boolean, default=True)
    summary = Column(String(200))
    
    render_config_override = Column(JSON)
    
    created_at = Column(DateTime, default=utcnow)
    updated_at = Column(DateTime, default=utcnow, onupdate=utcnow)
    
    rule = relationship(
        "DistributionRule",
        backref=backref("distribution_targets", cascade="all, delete-orphan", passive_deletes=True),
    )
    bot_chat = relationship("BotChat", backref="distribution_targets")
    
    __table_args__ = (
        Index("idx_rule_chat", "rule_id", "bot_chat_id", unique=True),
    )
