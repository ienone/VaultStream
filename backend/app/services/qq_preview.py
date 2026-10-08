"""One automatic parse/reply path, independent of collection and Agent runs."""

import asyncio
import hashlib
import re
import time

from fastapi import HTTPException
from sqlalchemy import select, text

from app.adapters import AdapterFactory, managed_adapter
from app.adapters.bilibili_parser.video_parser import parse_video
from app.core.database import AsyncSessionLocal
from app.core.logging import logger
from app.models import BotChat, BotConfigPlatform, Platform, SystemSetting
from app.push.napcat import NapcatPushService
from app.schemas.qq_preview import QQPreviewItem, QQPreviewRequest, QQPreviewResponse
from app.services.bot_config_runtime import get_primary_bot_config
from app.services.config_service import ConfigService
from app.services.link_preview import build_link_preview_messages, prepare_link_preview_images
from app.services.parse_capabilities import resolve_dedicated_parse_capability
from app.services.platform_parsing import open_configured_adapter
from app.services.qq_policy import QQRateLimited
from app.utils.text_formatters import format_push_text


def explicit_parse_request(value: str) -> bool:
    return bool(re.match(r"^\s*(?:请|帮我|麻烦|能帮我)?\s*(?:解析|展开|解一下)", value))


async def claim_message(config_id: int, target: str, message_id: str) -> bool:
    key = f"qq_preview_receipts:{config_id}:{target}"
    identity = hashlib.sha256(message_id.encode()).hexdigest()
    now = time.time()
    async with AsyncSessionLocal() as db:
        await db.execute(text("BEGIN IMMEDIATE"))
        row = await db.get(SystemSetting, key)
        entries = {k: v for k, v in (row.value if row else {}).items() if v > now - 86400}
        if identity in entries:
            return False
        entries[identity] = now
        entries = dict(sorted(entries.items(), key=lambda item: item[1])[-500:])
        if row:
            row.value = entries
        else:
            db.add(SystemSetting(key=key, value=entries, category="runtime"))
        await db.commit()
    return True


async def preview_links(config_id: int, request: QQPreviewRequest) -> QQPreviewResponse:
    config = ConfigService()
    policy = await config.get_value_fresh("qq_link_parser", {})
    if not policy.get("enabled") or (request.private and not policy.get("private_enabled")):
        raise HTTPException(403, "Link parsing is disabled")
    if request.private and request.chat_id != request.user_id:
        raise HTTPException(403, "Private reply target must be the sender")
    if not request.private and request.chat_id not in {str(x) for x in policy.get("group_ids", [])}:
        raise HTTPException(403, "Group link parsing is disabled")
    async with AsyncSessionLocal() as db:
        bot = await get_primary_bot_config(db, BotConfigPlatform.QQ)
        if (not bot or bot.id != config_id or not bot.enabled or str(bot.bot_id) != request.bot_id
                or request.user_id == request.bot_id):
            raise HTTPException(403, "QQ Bot identity is not authorized")
        if not request.private:
            chat = await db.scalar(select(BotChat).where(
                BotChat.bot_config_id == config_id, BotChat.chat_id == request.chat_id,
                BotChat.enabled.is_(True),
            ))
            if chat is None:
                raise HTTPException(403, "QQ group is disabled")
    admin_policy = await config.get_value_fresh("qq_bot_agent", {})
    admin = admin_policy.get("enabled") is True and request.user_id in {str(x) for x in admin_policy.get("admin_qq", [])}
    allow_cleaning = admin and explicit_parse_request(request.request_text)
    policies = await config.get_value_fresh("qq_chat_policies", {})
    excluded = set(policies.get(request.chat_id, {}).get("excluded_parse_platforms", [])) if not request.private else set()
    target = f"private:{request.chat_id}" if request.private else request.chat_id
    if not await claim_message(config_id, target, request.message_id):
        return QQPreviewResponse(duplicate=True)

    api = NapcatPushService()
    items = []
    try:
        for url in dict.fromkeys(request.urls):
            try:
                async with asyncio.timeout(55):
                    capability = await resolve_dedicated_parse_capability(url)
                    if capability.platform in excluded:
                        items.append(QQPreviewItem(url=url, status="unsupported"))
                        continue
                    if not capability.supported and not allow_cleaning:
                        items.append(QQPreviewItem(url=url, status="unsupported"))
                        continue
                    platform = Platform(capability.platform) if capability.supported else Platform.UNIVERSAL
                    try:
                        if platform == Platform.TWITTER:
                            async with managed_adapter(AdapterFactory.create(platform, public_only=True)) as adapter:
                                parsed = await adapter.parse(capability.url)
                        else:
                            async with open_configured_adapter(platform) as adapter:
                                if platform == Platform.BILIBILI and capability.content_type == "video":
                                    clean_url = await adapter.clean_url(capability.url)
                                    parsed = await parse_video(clean_url, adapter.headers, adapter.cookies, include_media=False)
                                else:
                                    parsed = await adapter.parse(capability.url)
                    except Exception:
                        if not allow_cleaning or platform == Platform.UNIVERSAL:
                            raise
                        async with open_configured_adapter(Platform.UNIVERSAL) as adapter:
                            parsed = await adapter.parse(capability.url)
                messages = build_link_preview_messages(parsed)
                try:
                    await prepare_link_preview_images(messages)
                except Exception:
                    for message in messages:
                        message["media_items"] = []
                    messages[0]["body"] += "\n\n图片未能发送。"
                result_text = "\n\n".join(format_push_text(message, rich_text=False) for message in messages)
                try:
                    mid = await api.push_forward(messages, target, summary=parsed.title) if len(messages) > 1 else await api.push(messages[0], target)
                except QQRateLimited:
                    items.append(QQPreviewItem(url=parsed.clean_url, status="rate_limited"))
                    continue
                except Exception:
                    items.append(QQPreviewItem(url=parsed.clean_url, status="delivery_unknown"))
                    continue
                items.append(QQPreviewItem(url=parsed.clean_url, status="sent" if mid else "delivery_unknown",
                                           text=result_text if mid else "", message_id=mid))
            except Exception as error:
                logger.warning("QQ link parse failed: error={}", type(error).__name__)
                failure = "链接解析失败。\n" + url
                try:
                    mid = await api.push({"body": failure, "render_config": {"format": "full"}}, target)
                except QQRateLimited:
                    items.append(QQPreviewItem(url=url, status="rate_limited"))
                except Exception:
                    items.append(QQPreviewItem(url=url, status="delivery_unknown"))
                else:
                    items.append(QQPreviewItem(url=url, status="failed" if mid else "delivery_unknown", text=failure if mid else "", message_id=mid))
    finally:
        await api.close()
    return QQPreviewResponse(items=items)
