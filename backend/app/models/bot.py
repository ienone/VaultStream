"""
机器人与聊天模型定义
"""
from datetime import datetime
from enum import Enum
from typing import Optional, Any
from sqlalchemy import String, Text, JSON, Integer, DateTime, Boolean, ForeignKey, Index
from sqlalchemy import Enum as SQLEnum
from sqlalchemy.orm import relationship, Mapped, mapped_column

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

    id: Mapped[int] = mapped_column(Integer, primary_key=True, index=True)
    platform: Mapped[BotConfigPlatform] = mapped_column(
        SQLEnum(BotConfigPlatform, native_enum=False, values_callable=lambda x: [e.value for e in x]),
        index=True,
    )
    name: Mapped[str] = mapped_column(String(100))

    bot_token: Mapped[Optional[str]] = mapped_column(String(300), default=None)

    napcat_http_url: Mapped[Optional[str]] = mapped_column(String(300), default=None)
    napcat_ws_url: Mapped[Optional[str]] = mapped_column(String(300), default=None)
    napcat_access_token: Mapped[Optional[str]] = mapped_column(String(300), default=None)

    enabled: Mapped[bool] = mapped_column(Boolean, default=True, index=True)
    is_primary: Mapped[bool] = mapped_column(Boolean, default=False, index=True)

    bot_id: Mapped[Optional[str]] = mapped_column(String(50), default=None)
    bot_username: Mapped[Optional[str]] = mapped_column(String(100), default=None)

    created_at: Mapped[Optional[datetime]] = mapped_column(DateTime, default=utcnow)
    updated_at: Mapped[Optional[datetime]] = mapped_column(DateTime, default=utcnow, onupdate=utcnow)

    chats = relationship("BotChat", back_populates="bot_config")


class BotChat(Base):
    """Bot 关联的聊天/群组/频道"""
    __tablename__ = "bot_chats"
    
    id: Mapped[int] = mapped_column(Integer, primary_key=True, index=True)

    __table_args__ = (
        Index("ix_bot_chats_bot_config_chat", "bot_config_id", "chat_id", unique=True),
    )

    bot_config_id: Mapped[int] = mapped_column(Integer, ForeignKey("bot_configs.id", ondelete="CASCADE"), index=True)
    
    chat_id: Mapped[str] = mapped_column(String(50), index=True)
    chat_type: Mapped[BotChatType] = mapped_column(SQLEnum(BotChatType, native_enum=False, values_callable=lambda x: [e.value for e in x]))
    title: Mapped[Optional[str]] = mapped_column(String(200), default=None)
    username: Mapped[Optional[str]] = mapped_column(String(100), default=None)
    description: Mapped[Optional[str]] = mapped_column(Text, default=None)
    
    member_count: Mapped[Optional[int]] = mapped_column(Integer, default=None)
    
    is_admin: Mapped[bool] = mapped_column(Boolean, default=False)
    can_post: Mapped[bool] = mapped_column(Boolean, default=False)
    
    enabled: Mapped[bool] = mapped_column(Boolean, default=True, index=True)
    is_monitoring: Mapped[bool] = mapped_column(Boolean, default=False)
    is_push_target: Mapped[bool] = mapped_column(Boolean, default=False)
    
    nsfw_chat_id: Mapped[Optional[str]] = mapped_column(String(50), default=None)
    
    total_pushed: Mapped[int] = mapped_column(Integer, default=0)
    last_pushed_at: Mapped[Optional[datetime]] = mapped_column(DateTime, default=None)
    
    raw_data: Mapped[Optional[Any]] = mapped_column(JSON, default=None)
    
    is_accessible: Mapped[bool] = mapped_column(Boolean, default=True)
    last_sync_at: Mapped[Optional[datetime]] = mapped_column(DateTime, default=None)
    sync_error: Mapped[Optional[str]] = mapped_column(String(500), default=None)
    
    @property
    def platform_type(self) -> str:
        """根据 chat_type 自动推断平台"""
        if self.chat_type in [BotChatType.QQ_GROUP, BotChatType.QQ_PRIVATE]:
            return "qq"
        if self.chat_type in [BotChatType.CHANNEL, BotChatType.GROUP, BotChatType.SUPERGROUP, BotChatType.PRIVATE]:
            return "telegram"
        return "telegram"
    
    created_at: Mapped[Optional[datetime]] = mapped_column(DateTime, default=utcnow)
    updated_at: Mapped[Optional[datetime]] = mapped_column(DateTime, default=utcnow, onupdate=utcnow)

    bot_config = relationship("BotConfig", back_populates="chats")


class BotRuntime(Base):
    """Bot 运行时状态（单例表，只有一条记录）"""
    __tablename__ = "bot_runtime"
    
    id: Mapped[int] = mapped_column(Integer, primary_key=True, default=1)
    
    bot_id: Mapped[Optional[str]] = mapped_column(String(50), default=None)
    bot_username: Mapped[Optional[str]] = mapped_column(String(100), default=None)
    bot_first_name: Mapped[Optional[str]] = mapped_column(String(200), default=None)
    
    started_at: Mapped[Optional[datetime]] = mapped_column(DateTime, default=None)
    last_heartbeat_at: Mapped[Optional[datetime]] = mapped_column(DateTime, default=None)
    version: Mapped[Optional[str]] = mapped_column(String(50), default=None)
    
    last_error: Mapped[Optional[str]] = mapped_column(Text, default=None)
    last_error_at: Mapped[Optional[datetime]] = mapped_column(DateTime, default=None)
    
    updated_at: Mapped[Optional[datetime]] = mapped_column(DateTime, default=utcnow, onupdate=utcnow)
