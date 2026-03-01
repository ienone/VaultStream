"""运行时 BotConfig 解析服务。"""

from __future__ import annotations

from typing import Optional, Tuple

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.db_adapter import AsyncSessionLocal
from app.models import BotConfig, BotConfigPlatform, BotChat


async def get_primary_bot_config(
    db: AsyncSession,
    platform: BotConfigPlatform,
    *,
    enabled_only: bool = True,
) -> Optional[BotConfig]:
    from app.repositories import BotRepository
    repo = BotRepository(db)
    return await repo.get_primary_config(platform, enabled_only=enabled_only)


async def get_primary_telegram_runtime(
    db: AsyncSession,
) -> Tuple[Optional[BotConfig], Optional[str]]:
    """返回主 Telegram Bot 配置和默认 chat_id（用于 bot 命令上下文）。"""
    cfg = await get_primary_bot_config(db, BotConfigPlatform.TELEGRAM, enabled_only=True)
    if not cfg:
        return None, None

    from app.repositories import BotRepository
    repo = BotRepository(db)
    chats = await repo.list_chats_for_config(cfg.id, enabled=True)
    
    default_chat_id = chats[0].chat_id if chats else None
    return cfg, default_chat_id


async def get_primary_telegram_token_from_db() -> str:
    async with AsyncSessionLocal() as db:
        cfg = await get_primary_bot_config(db, BotConfigPlatform.TELEGRAM, enabled_only=True)
        if not cfg or not cfg.bot_token:
            raise RuntimeError("Primary enabled Telegram bot config is missing")
        return cfg.bot_token


async def get_primary_qq_runtime_from_db() -> Tuple[str, Optional[str], Optional[str]]:
    """返回 (napcat_http_url, napcat_access_token, bot_id/uin)。"""
    async with AsyncSessionLocal() as db:
        cfg = await get_primary_bot_config(db, BotConfigPlatform.QQ, enabled_only=True)
        if not cfg or not cfg.napcat_http_url:
            raise RuntimeError("Primary enabled QQ bot config is missing")
        return cfg.napcat_http_url, cfg.napcat_access_token, cfg.bot_id
