"""
Telegram 群组同步服务 — 统一 BotChat 元信息刷新逻辑
"""
from typing import List, Dict, Any, Optional

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.events import event_bus
from app.core.logging import logger
from app.core.time_utils import utcnow
from app.models import BotChat, BotChatType, BotConfig


async def refresh_telegram_chats(
    db: AsyncSession,
    *,
    bot_config: BotConfig,
    chat_id_filter: Optional[str] = None,
    enabled_only: bool = True,
    fetch_permissions: bool = False,
) -> dict:
    """
    刷新 Telegram BotChat 元信息。

    Args:
        bot_config: 包含 bot_token 的 BotConfig
        chat_id_filter: 仅同步指定 chat_id（可选）
        enabled_only: 是否仅同步 enabled=True 的群组
        fetch_permissions: 是否获取 member_count / is_admin / can_post

    Returns:
        {"total": int, "updated": int, "created": int, "failed": int,
         "inaccessible": int, "details": list}
    """
    from telegram import Bot
    from telegram.error import TelegramError

    if not bot_config.bot_token:
        raise ValueError("bot_token is required for telegram sync")

    bot = Bot(token=bot_config.bot_token)
    now = utcnow()

    # 验证 token
    try:
        me = await bot.get_me()
        bot_config.bot_id = str(me.id)
        bot_config.bot_username = me.username
    except Exception as e:
        raise ValueError(f"Invalid telegram bot token: {e}")

    # 构建查询
    query = select(BotChat).where(BotChat.bot_config_id == bot_config.id)
    if chat_id_filter:
        query = query.where(BotChat.chat_id == chat_id_filter)
    elif enabled_only:
        query = query.where(BotChat.enabled == True)

    chats = (await db.execute(query)).scalars().all()

    updated = 0
    failed = 0
    inaccessible = 0
    details: List[Dict[str, Any]] = []

    for chat in chats:
        try:
            tg_chat = await bot.get_chat(chat.chat_id)
            chat.title = tg_chat.title
            chat.username = tg_chat.username
            chat.description = tg_chat.description
            chat.chat_type = BotChatType(tg_chat.type)
            chat.last_sync_at = now
            chat.is_accessible = True
            chat.sync_error = None

            if fetch_permissions:
                try:
                    chat.member_count = await bot.get_chat_member_count(chat.chat_id)
                except Exception:
                    pass
                try:
                    bot_member = await bot.get_chat_member(chat.chat_id, me.id)
                    chat.is_admin = bot_member.status in ["administrator", "creator"]
                    chat.can_post = (
                        getattr(bot_member, "can_post_messages", True)
                        if chat.is_admin
                        else False
                    )
                except Exception:
                    pass

            updated += 1
            details.append({"chat_id": chat.chat_id, "title": chat.title, "status": "updated"})
            await event_bus.publish("bot_sync_progress", {
                "bot_config_id": bot_config.id,
                "chat_id": chat.chat_id,
                "title": chat.title,
                "status": "updated",
                "updated": updated,
                "failed": failed,
                "inaccessible": inaccessible,
                "total": len(chats),
                "timestamp": now.isoformat(),
            })

        except TelegramError as e:
            error_msg = str(e)
            if "chat not found" in error_msg.lower() or "forbidden" in error_msg.lower():
                chat.is_accessible = False
                inaccessible += 1
            else:
                failed += 1
            chat.sync_error = error_msg
            chat.last_sync_at = now
            details.append({"chat_id": chat.chat_id, "title": chat.title, "status": "failed", "error": error_msg})
            await event_bus.publish("bot_sync_progress", {
                "bot_config_id": bot_config.id,
                "chat_id": chat.chat_id,
                "title": chat.title,
                "status": "failed",
                "error": error_msg,
                "updated": updated,
                "failed": failed,
                "inaccessible": inaccessible,
                "total": len(chats),
                "timestamp": now.isoformat(),
            })
            logger.warning(f"同步群组失败 {chat.chat_id}: {e}")

        except Exception as e:
            failed += 1
            chat.sync_error = str(e)
            chat.last_sync_at = now
            details.append({"chat_id": chat.chat_id, "title": chat.title, "status": "error", "error": str(e)})
            await event_bus.publish("bot_sync_progress", {
                "bot_config_id": bot_config.id,
                "chat_id": chat.chat_id,
                "title": chat.title,
                "status": "error",
                "error": str(e),
                "updated": updated,
                "failed": failed,
                "inaccessible": inaccessible,
                "total": len(chats),
                "timestamp": now.isoformat(),
            })
            logger.error(f"同步群组异常 {chat.chat_id}: {e}")

    await db.commit()
    await bot.close()

    await event_bus.publish("bot_sync_completed", {
        "bot_config_id": bot_config.id,
        "total": len(chats),
        "updated": updated,
        "failed": failed,
        "inaccessible": inaccessible,
        "created": 0,
        "timestamp": now.isoformat(),
    })

    return {
        "total": len(chats),
        "updated": updated,
        "created": 0,
        "failed": failed,
        "inaccessible": inaccessible,
        "details": details,
    }
