"""
机器人与聊天模型定义
"""
from datetime import datetime
from enum import Enum
from sqlalchemy import Column, Integer, String, DateTime, Boolean, Text, ForeignKey, Enum as SQLEnum, JSON, Index
from sqlalchemy.orm import relationship

from app.core.time_utils import utcnow
from app.models.base import Base


class BotChatType(str, Enum):
    """Bot 聊天类型"""
    CHANNEL = "channel"     # TG 频道
    GROUP = "group"         # TG 普通群组
    SUPERGROUP = "supergroup"  # TG 超级群组
    PRIVATE = "private"     # TG 私聊
    QQ_GROUP = "qq_group"   # QQ 群
    QQ_PRIVATE = "qq_private"  # QQ 私聊


class BotConfigPlatform(str, Enum):
    """Bot 配置平台"""
    TELEGRAM = "telegram"
    QQ = "qq"


class BotConfig(Base):
    """Bot 配置（支持多 Bot 管理）"""
    __tablename__ = "bot_configs"

    id = Column(Integer, primary_key=True, index=True)
    platform = Column(
        SQLEnum(BotConfigPlatform, native_enum=False, values_callable=lambda x: [e.value for e in x]),
        nullable=False,
        index=True,
    )
    name = Column(String(100), nullable=False)

    bot_token = Column(String(300))

    napcat_http_url = Column(String(300))
    napcat_ws_url = Column(String(300))
    napcat_access_token = Column(String(300))

    enabled = Column(Boolean, default=True, index=True)
    is_primary = Column(Boolean, default=False, index=True)

    bot_id = Column(String(50))
    bot_username = Column(String(100))

    created_at = Column(DateTime, default=utcnow)
    updated_at = Column(DateTime, default=utcnow, onupdate=utcnow)

    chats = relationship("BotChat", back_populates="bot_config")


class BotChat(Base):
    """Bot 关联的聊天/群组/频道"""
    __tablename__ = "bot_chats"
    
    id = Column(Integer, primary_key=True, index=True)

    __table_args__ = (
        Index("ix_bot_chats_bot_config_chat", "bot_config_id", "chat_id", unique=True),
    )

    bot_config_id = Column(Integer, ForeignKey("bot_configs.id", ondelete="CASCADE"), nullable=False, index=True)
    
    chat_id = Column(String(50), nullable=False, index=True)
    chat_type = Column(SQLEnum(BotChatType, native_enum=False, values_callable=lambda x: [e.value for e in x]), nullable=False)
    title = Column(String(200))
    username = Column(String(100))
    description = Column(Text)
    
    member_count = Column(Integer)
    
    is_admin = Column(Boolean, default=False)
    can_post = Column(Boolean, default=False)
    
    enabled = Column(Boolean, default=True, index=True)
    
    nsfw_chat_id = Column(String(50))
    
    total_pushed = Column(Integer, default=0)
    last_pushed_at = Column(DateTime)
    
    raw_data = Column(JSON)
    
    is_accessible = Column(Boolean, default=True)
    last_sync_at = Column(DateTime)
    sync_error = Column(String(500))
    
    @property
    def platform_type(self) -> str:
        """根据 chat_type 自动推断平台"""
        if self.chat_type in [BotChatType.QQ_GROUP, BotChatType.QQ_PRIVATE]:
            return "qq"
        if self.chat_type in [BotChatType.CHANNEL, BotChatType.GROUP, BotChatType.SUPERGROUP, BotChatType.PRIVATE]:
            return "telegram"
        return "telegram"
    
    created_at = Column(DateTime, default=utcnow)
    updated_at = Column(DateTime, default=utcnow, onupdate=utcnow)

    bot_config = relationship("BotConfig", back_populates="chats")


class BotRuntime(Base):
    """Bot 运行时状态（单例表，只有一条记录）"""
    __tablename__ = "bot_runtime"
    
    id = Column(Integer, primary_key=True, default=1)
    
    bot_id = Column(String(50))
    bot_username = Column(String(100))
    bot_first_name = Column(String(200))
    
    started_at = Column(DateTime)
    last_heartbeat_at = Column(DateTime)
    version = Column(String(50))
    
    last_error = Column(Text)
    last_error_at = Column(DateTime)
    
    updated_at = Column(DateTime, default=utcnow, onupdate=utcnow)
