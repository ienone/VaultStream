"""Public QQ previews, with no Content writes or collection lookups."""

import asyncio
import hashlib
import time
from urllib.parse import urlsplit

from fastapi import HTTPException
from sqlalchemy import select, text

from app.adapters import AdapterFactory, managed_adapter
from app.adapters.errors import AdapterError
from app.core.database import AsyncSessionLocal
from app.core.logging import logger
from app.models import BotChat, BotConfig, BotConfigPlatform, Platform, SystemSetting
from app.schemas.qq_preview import QQPreviewItem, QQPreviewRequest, QQPreviewResponse
from app.services.config_service import ConfigService
from app.services.parse_capabilities import resolve_dedicated_parse_capability
from app.services.qq_policy import QQRateLimited, reserve_group_send
from app.utils.text_formatters import format_push_text, select_push_media


async def _claim_message(config_id: int, group_id: str, message_id: str) -> bool:
    """Bounded durable receipts prevent redelivery after HTTP/Koishi restarts.

    Claim before parsing/sending. An interrupted delivery is not automatically
    resent because QQ cannot prove whether the earlier send reached the group.
    """
    key = f"qq_preview_receipts:{config_id}:{group_id}"
    identity = hashlib.sha256(message_id.encode()).hexdigest()
    now = time.time()
    async with AsyncSessionLocal() as db:
        await db.execute(text("BEGIN IMMEDIATE"))
        row = await db.get(SystemSetting, key)
        entries = {key: value for key, value in (row.value if row else {}).items() if value > now - 86400}
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


def _web_media_url(value) -> str | None:
    if not isinstance(value, str):
        return None
    try:
        parsed = urlsplit(value)
        if parsed.scheme in {"http", "https"} and parsed.hostname and not parsed.username and not parsed.password:
            return value
    except ValueError:
        pass
    return None


async def _parse_one(url: str, excluded: set[str]) -> QQPreviewItem:
    platform = None
    try:
        async with asyncio.timeout(45):
            capability = await resolve_dedicated_parse_capability(url)
            platform = capability.platform
            if not capability.supported or platform in excluded:
                return QQPreviewItem(
                    url=url, status="unsupported", platform=platform,
                    reason="excluded_platform" if platform in excluded else capability.reason,
                )
            # Never use the account-bearing platform_parsing factory here.
            # These adapters explicitly suppress settings and DB account cookies.
            adapter = AdapterFactory.create(Platform(platform), public_only=True)
            async with managed_adapter(adapter):
                parsed = await adapter.parse(capability.url)

        metadata = parsed.archive_metadata or {}
        archive = metadata.get("archive") or {}
        photos = [
            {"type": "photo", "url": image["url"]}
            for image in archive.get("images", [])
            if isinstance(image, dict) and image.get("type") != "avatar" and _web_media_url(image.get("url"))
        ]
        if not photos and _web_media_url(parsed.cover_url) and parsed.cover_url != parsed.author_avatar_url:
            photos = [{"type": "photo", "url": parsed.cover_url}]
        payload = {
            "title": parsed.title, "body": parsed.body,
            "author_name": parsed.author_name, "clean_url": parsed.clean_url,
            "media_items": photos, "render_config": {"format": "summary"},
        }
        selected = select_push_media(payload)
        return QQPreviewItem(
            url=parsed.clean_url, status="parsed", platform=parsed.platform,
            content_type=parsed.content_type, title=parsed.title,
            body=(parsed.body or "")[:30000] or None, author=parsed.author_name,
            media_urls=list(dict.fromkeys(filter(None, (_web_media_url(item) for item in parsed.media_urls))))[:40],
            image_url=selected[0]["url"] if selected else None,
            text=format_push_text(payload, rich_text=False),
        )
    except AdapterError as error:
        reason = "public_access_required" if error.auth_required else "parse_failed"
    except TimeoutError:
        reason = "parse_timeout"
    except Exception as error:
        # Do not echo URLs with access tokens or platform responses into logs.
        logger.warning("QQ public preview failed: platform={} error={}", platform, type(error).__name__)
        reason = "parse_failed"
    return QQPreviewItem(
        url=url, status="failed", platform=platform, reason=reason,
        text="这条链接暂时无法公开解析。" if reason == "public_access_required" else "这条链接解析失败。",
    )


async def preview_group_links(config_id: int, request: QQPreviewRequest) -> QQPreviewResponse:
    config_service = ConfigService()
    options = await config_service.get_value_fresh("qq_bot_agent", {})
    groups = {str(value) for value in options.get("group_ids", ["1070760473"])}
    if not options.get("enabled", True) or request.group_id not in groups:
        raise HTTPException(403, "QQ group previews are not enabled for this group")
    async with AsyncSessionLocal() as db:
        bot = await db.get(BotConfig, config_id)
        if not bot or not bot.enabled or bot.platform != BotConfigPlatform.QQ:
            raise HTTPException(403, "QQ Bot is not enabled")
        chat = await db.scalar(select(BotChat).where(
            BotChat.bot_config_id == config_id, BotChat.chat_id == request.group_id,
        ))
        if chat is not None and not chat.enabled:
            raise HTTPException(403, "QQ group is disabled")
        if str(bot.bot_id or "") == request.user_id:
            raise HTTPException(403, "Bot messages cannot request previews")

    if request.reserve_send and not await _claim_message(config_id, request.group_id, request.message_id):
        return QQPreviewResponse(duplicate=True)
    policies = await config_service.get_value_fresh("qq_chat_policies", {})
    excluded = set(policies.get(request.group_id, {}).get("excluded_parse_platforms", [])) | {"bilibili"}
    semaphore = asyncio.Semaphore(4)

    async def parse(url: str) -> QQPreviewItem:
        async with semaphore:
            return await _parse_one(url, excluded)

    items = await asyncio.gather(*(parse(url) for url in dict.fromkeys(request.urls)))
    if request.reserve_send:
        for item in items:
            if item.status == "unsupported":
                continue
            try:
                await reserve_group_send(request.group_id)
            except QQRateLimited:
                item.reason = "rate_limited"
            else:
                item.send_allowed = True
    return QQPreviewResponse(items=items)
