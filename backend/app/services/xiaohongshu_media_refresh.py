"""Refresh signed image locations for saved Xiaohongshu notes."""
from __future__ import annotations

import asyncio
from collections import OrderedDict
import re
import time
from urllib.parse import urlsplit

from sqlalchemy import select

from app.adapters.errors import NonRetryableAdapterError
from app.core.db_adapter import AsyncSessionLocal
from app.models import Content, Platform
from app.models.media import MediaAsset
from app.services.platform_parsing import open_configured_adapter

_refresh_lock = asyncio.Lock()
_note_images: OrderedDict[int, tuple[float, dict[str, str]]] = OrderedDict()


def _image_identity(url: str) -> str | None:
    """Signed webpic URLs retain the platform image ID before the transform."""
    parts = urlsplit(url)
    if parts.scheme not in {"http", "https"} or not re.fullmatch(
        r"sns-webpic-[a-z0-9-]+\.xhscdn\.com", parts.hostname or "",
    ):
        return None
    image_id = parts.path.rsplit("/", 1)[-1].split("!", 1)[0]
    return image_id if re.fullmatch(r"[a-z0-9]{20,}", image_id) else None


async def refresh_xiaohongshu_image_url(url: str) -> str | None:
    """Refresh only an exact saved source; never persist or reorder note content."""
    identity = _image_identity(url)
    if identity is None:
        return None
    async with AsyncSessionLocal() as db:
        row = (await db.execute(
            select(Content.id, Content.url, Content.platform_id)
            .join(MediaAsset, MediaAsset.content_id == Content.id)
            .where(
                MediaAsset.original_url == url,
                Content.platform == Platform.XIAOHONGSHU,
                Content.deleted_at.is_(None),
            ).order_by(Content.id).limit(1)
        )).first()
    if row is None:
        return None
    content_id, note_url, platform_id = row
    async with _refresh_lock:
        cached = _note_images.get(content_id)
        if cached is not None and cached[0] > time.monotonic():
            images = cached[1]
            _note_images.move_to_end(content_id)
        else:
            async with open_configured_adapter(Platform.XIAOHONGSHU) as adapter:
                parsed = await adapter.parse(note_url)
            if parsed.content_type != "note" or (platform_id and parsed.content_id != platform_id):
                raise NonRetryableAdapterError("小红书媒体刷新未返回原笔记")
            images: dict[str, str] = {}
            ambiguous: set[str] = set()
            for image_url in [parsed.cover_url, *(parsed.media_urls or [])]:
                if not image_url:
                    continue
                image_id = _image_identity(image_url)
                if image_id is None:
                    continue
                if image_id in images and images[image_id] != image_url:
                    ambiguous.add(image_id)
                else:
                    images[image_id] = image_url
            for image_id in ambiguous:
                images.pop(image_id, None)
            _note_images[content_id] = (time.monotonic() + 60, images)
            _note_images.move_to_end(content_id)
            while len(_note_images) > 64:
                _note_images.popitem(last=False)
    refreshed = images.get(identity)
    return refreshed if refreshed and refreshed != url else None
