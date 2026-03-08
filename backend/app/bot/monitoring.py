"""
群组/频道消息监控模块

被动监听 is_monitoring=True 的群组消息，提取 URL 并写入发现缓冲区。
"""
from datetime import timedelta

from sqlalchemy import select
from telegram import Update

from app.core.logging import logger
from app.core.db_adapter import AsyncSessionLocal
from app.core.time_utils import utcnow
from app.models import Content, BotChat, DiscoveryState, Platform, ContentStatus
from app.utils.url_utils import extract_urls_from_text, normalize_url_for_dedup

_DEFAULT_RETENTION_DAYS = 7


def extract_urls(text: str) -> list[str]:
    """从文本中提取所有 HTTP/HTTPS URL。"""
    return extract_urls_from_text(text)


async def handle_monitored_message(update: Update, context) -> None:
    """
    MessageHandler 回调：监听群组消息，提取 URL 并写入 Content 表。

    静默处理，不回复消息。
    """
    message = update.effective_message
    if not message or not message.text:
        return

    chat = update.effective_chat
    if not chat:
        return

    chat_id_str = str(chat.id)
    bot_config_id = context.bot_data.get("bot_config_id")

    try:
        async with AsyncSessionLocal() as db:
            # 查询该 chat 是否开启了监控
            query = select(BotChat).where(
                BotChat.chat_id == chat_id_str,
                BotChat.is_monitoring == True,  # noqa: E712
            )
            if bot_config_id is not None:
                query = query.where(BotChat.bot_config_id == bot_config_id)

            result = await db.execute(query)
            bot_chat = result.scalars().first()

            if not bot_chat:
                return

            urls = extract_urls(message.text)
            if not urls:
                return

            now = utcnow()
            title_snippet = (message.text[:100] if len(message.text) > 100 else message.text)

            for url in urls:
                canonical = normalize_url_for_dedup(url)

                # 去重：同平台 + 相同 canonical_url 则跳过
                dup = await db.execute(
                    select(Content.id).where(
                        Content.canonical_url == canonical,
                    ).limit(1)
                )
                if dup.scalars().first() is not None:
                    logger.debug(f"监控去重跳过: {canonical}")
                    continue

                content = Content(
                    platform=Platform.UNIVERSAL,
                    url=url,
                    canonical_url=canonical,
                    status=ContentStatus.UNPROCESSED,
                    source_type="telegram_bot",
                    discovery_state=DiscoveryState.INGESTED,
                    discovered_at=now,
                    title=title_snippet,
                    expire_at=now + timedelta(days=_DEFAULT_RETENTION_DAYS),
                )
                db.add(content)

            await db.commit()

    except Exception:
        logger.exception(f"监控消息处理异常 chat_id={chat_id_str}")
