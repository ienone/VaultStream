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
    query = (
        select(BotConfig)
        .where(BotConfig.platform == platform)
        .where(BotConfig.is_primary == True)
        .order_by(BotConfig.id.asc())
        .limit(1)
    )
    if enabled_only:
        query = query.where(BotConfig.enabled == True)

    result = await db.execute(query)
    return result.scalar_one_or_none()


async def get_primary_telegram_runtime(
    db: AsyncSession,
) -> Tuple[Optional[BotConfig], Optional[str]]:
    """返回主 Telegram Bot 配置和默认 chat_id（用于 bot 命令上下文）。"""
    cfg = await get_primary_bot_config(db, BotConfigPlatform.TELEGRAM, enabled_only=True)
    if not cfg:
        return None, None

    chat_result = await db.execute(
        select(BotChat.chat_id)
        .where(BotChat.bot_config_id == cfg.id)
        .where(BotChat.enabled == True)
        .order_by(BotChat.id.asc())
        .limit(1)
    )
    default_chat_id = chat_result.scalar_one_or_none()
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
