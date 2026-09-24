"""Native Telegram ingestion shares the normal content, media and scoring pipeline."""
from __future__ import annotations

import asyncio
from datetime import timedelta
from pathlib import Path

from sqlalchemy import select, func

from app.adapters.telegram_account import TelegramAccountReader
from app.adapters.storage import get_storage_backend
from app.core.config import settings
from app.core.db_adapter import AsyncSessionLocal
from app.core.time_utils import utcnow
from app.models import (Content, ContentSource, ContentDiscoveryLink, ContentStatus,
                        DiscoverySource, DiscoverySourceKind, DiscoveryState, LayoutType,
                        Platform, SystemSetting, TelegramMessage)
from app.models.media import (MediaAsset, MediaType, MediaRole, MediaArchiveStatus,
                              MediaVariant, MediaVariantKind, MediaVariantStatus)
from app.services.config_service import ConfigService
from app.services.post_ingest import PostIngestService
from app.media.processor import store_media_bytes
from app.utils.datetime_utils import normalize_datetime_for_db


class TelegramAccountSync:
    def __init__(self, client, *, session_factory=AsyncSessionLocal, storage=None):
        self.client = client
        self.reader = TelegramAccountReader(client)
        self.sessions = session_factory
        self.storage = storage or get_storage_backend()
        self.config = ConfigService(session_factory=session_factory)

    async def sync(self, *, channels: bool, saved: bool, source_id: int | None = None) -> dict:
        me = await self.client.get_me()
        if me is None or me.bot:
            raise ValueError("请先登录 Telegram 用户账号")
        account_id = me.id
        counts = {"channels": 0, "created": 0, "updated": 0, "saved": 0}
        if channels:
            for channel in await self.reader.subscribed_channels():
                source = await self._channel_source(account_id, channel)
                if source_id is not None and source.id != source_id:
                    continue
                if not channel["notifications_enabled"] or not source.enabled:
                    continue
                result = await self._sync_peer(account_id, channel["peer_id"], source=source)
                counts["channels"] += 1
                for key, value in result.items():
                    counts[key] += value
        if saved:
            result = await self._sync_peer(account_id, me.id, source=None)
            for key, value in result.items():
                counts[key] += value
        return counts

    async def _channel_source(self, account_id: int, channel: dict) -> DiscoverySource:
        async with self.sessions() as db:
            sources = (await db.scalars(select(DiscoverySource).where(
                DiscoverySource.kind == DiscoverySourceKind.TELEGRAM_CHANNEL,
            ))).all()
            source = next((s for s in sources if (s.config or {}).get("account_id") == account_id
                           and (s.config or {}).get("peer_id") == channel["peer_id"]), None)
            if source is None:
                source = DiscoverySource(kind=DiscoverySourceKind.TELEGRAM_CHANNEL,
                    name=channel["title"], enabled=True, sync_interval_minutes=5,
                    config={"transport": "mtproto", "account_id": account_id, "peer_id": channel["peer_id"]})
                db.add(source)
            source.name = channel["title"]
            source.config = {**source.config, "username": channel["username"],
                             "notifications_enabled": channel["notifications_enabled"]}
            await db.commit()
            await db.refresh(source)
            return source

    async def _sync_peer(self, account_id: int, peer_id: int, *, source: DiscoverySource | None) -> dict:
        cursor_key = f"telegram_saved_cursor_{account_id}"
        async with self.sessions() as db:
            state = await db.get(SystemSetting, cursor_key) if source is None else await db.get(DiscoverySource, source.id)
            if source is not None and (state is None or not state.enabled):
                return {"created": 0, "updated": 0, "saved": 0}
            value = state.value if source is None and state else state.last_cursor if state else None
        posts, cursor = await self.reader.read_page(peer_id, after=int(value) if value is not None else (0 if source is None else None))
        retention = int(await self.config.get_value_fresh("discovery_retention_days", 7))
        archive_config = await self.config.get_archive_media_config()
        counts = {"created": 0, "updated": 0, "saved": 0}
        changed = []
        for post in posts:
            chain = await self.reader.source_chain(post.messages[0])
            async with self.sessions() as db:
                content, action, is_saved = await self._ingest(db, account_id, post, source, chain, retention, archive_config)
                await db.commit()
                if action:
                    counts[action] += 1
                if action or is_saved:
                    changed.append((content.id, bool(action)))
                counts["saved"] += int(is_saved)
        # A failed page leaves its cursor unchanged; already committed messages are idempotent.
        async with self.sessions() as db:
            if source is None:
                state = await db.get(SystemSetting, cursor_key)
                if state is None:
                    db.add(SystemSetting(key=cursor_key, value=cursor or 0, category="telegram"))
                else:
                    state.value = cursor or 0
            else:
                state = await db.get(DiscoverySource, source.id)
                if state is not None:
                    state.last_cursor = str(cursor or 0)
                    state.last_sync_at = utcnow()
                    state.last_error = None
            await db.commit()
        pipeline = PostIngestService()
        for content_id, payload_changed in changed:
            async with self.sessions() as db:
                content = await db.get(Content, content_id)
                if content and not content.deleted_at:
                    await pipeline.run_for_content(db, content, source="telegram_account", summary=payload_changed, embedding=payload_changed, distribution=source is None)
        if source is not None and changed:
            async with self.sessions() as db:
                await pipeline.score_discovery(db)
        return counts

    async def _ingest(self, db, account_id, post, source, chain, retention, archive_config):
        address = post.address
        keys = [(account_id, address.peer_id, m.id) for m in post.messages]
        occurrence = await db.get(TelegramMessage, keys[0])
        content = await db.get(Content, occurrence.content_id) if occurrence else None
        # User deletion remains authoritative; a repeated remote copy does not restore it.
        if content and content.deleted_at:
            return content, None, False
        action = None
        origin = (post.origin or address).as_dict()
        if content is None:
            candidates = (await db.execute(select(TelegramMessage, Content).join(Content,
                Content.id == TelegramMessage.content_id).where(
                TelegramMessage.account_id == account_id,
                TelegramMessage.fingerprint == post.fingerprint,
                Content.deleted_at.is_(None)))).all()
            content = next((c for link, c in candidates if link.origin == origin
                           or any(m.photo or m.document for m in post.messages) or len(post.body) >= 80), None)
        elif occurrence.fingerprint != post.fingerprint:
            shared = await db.scalar(select(func.count()).select_from(TelegramMessage).where(
                TelegramMessage.content_id == content.id,
                (TelegramMessage.peer_id != address.peer_id) | TelegramMessage.message_id.not_in([m.id for m in post.messages])))
            if shared:
                # Editing one forwarded copy must not rewrite the other copies.
                content = None
            else:
                action = "updated"
        if content is None:
            identity = f"vaultstream://telegram/{account_id}/{address.peer_id}/{address.message_id}/{post.fingerprint}"
            content = Content(platform=Platform.TELEGRAM, url=identity, canonical_url=identity,
                platform_id=f"{address.peer_id}:{address.message_id}", status=ContentStatus.PARSE_SUCCESS,
                content_type="post", layout_type=LayoutType.ARTICLE,
                discovery_state=DiscoveryState.INGESTED if source else None,
                expire_at=utcnow()+timedelta(days=retention) if source else None,
                discovered_at=utcnow() if source else None,
                source_type="telegram_channel" if source else "telegram_saved")
            db.add(content)
            action = "created"
        if action:
            author = source.name if source else None
            if chain:
                author = chain[-1]["name"] or author
                content.resolved_url = chain[-1]["url"]
            elif source and source.config.get("username"):
                content.resolved_url = f"https://t.me/{source.config['username']}/{address.message_id}"
            values = {"title": None, "body": post.body or None, "author_name": author}
            conflicts = {}
            for key, value in values.items():
                if key in (content.manual_edit_fields or []):
                    if getattr(content, key) != value:
                        conflicts[key] = value
                else:
                    setattr(content, key, value)
            content.parse_candidate = {"created_at": utcnow().isoformat(), "fields": conflicts} if conflicts else None
            content.published_at = normalize_datetime_for_db(post.messages[0].date)
            content.context_data = {"telegram": {"account_id": account_id,
                "peer_id": address.peer_id, "message_ids": [m.id for m in post.messages],
                "source_chain": chain, "reply": post.reply}}
            # Downloads are only needed for newly materialized payloads, not every forward.
            if action == "created":
                await self._archive_media(db, content, post, archive_config)
        await db.flush()
        for key in keys:
            link = await db.get(TelegramMessage, key)
            if link is None:
                db.add(TelegramMessage(account_id=key[0], peer_id=key[1], message_id=key[2],
                    content_id=content.id, fingerprint=post.fingerprint, origin=origin))
            else:
                link.content_id, link.fingerprint, link.origin = content.id, post.fingerprint, origin
        newly_saved = False
        if source:
            existing = await db.scalar(select(ContentDiscoveryLink.id).where(
                ContentDiscoveryLink.content_id == content.id, ContentDiscoveryLink.discovery_source_id == source.id))
            if existing is None:
                db.add(ContentDiscoveryLink(content_id=content.id, discovery_source_id=source.id,
                    url=content.resolved_url))
        else:
            saved_source = f"telegram_saved:{account_id}"
            existing = await db.scalar(select(ContentSource.id).where(
                ContentSource.content_id == content.id, ContentSource.source == saved_source))
            if existing is None:
                db.add(ContentSource(content_id=content.id, source=saved_source,
                    client_context={"platform": "telegram", **address.as_dict()}))
                newly_saved = True
            content.discovery_state = DiscoveryState.PROMOTED
            content.promoted_at = content.promoted_at or utcnow()
            content.expire_at = None
        return content, action, newly_saved

    async def _archive_media(self, db, content, post, config):
        if not config.enabled:
            return
        counts = {"image": 0, "video": 0}
        for message in post.messages:
            media = message.photo or message.document
            if not media:
                continue
            mime = message.file.mime_type or "application/octet-stream"
            kind = "image" if mime.startswith("image/") else "video" if mime.startswith("video/") else "audio" if mime.startswith("audio/") else "document"
            if kind == "image" and (not config.images_enabled or (config.image_max_count is not None and counts[kind] >= config.image_max_count)):
                continue
            if kind == "video" and (not config.videos_enabled or (config.video_max_count is not None and counts[kind] >= config.video_max_count)):
                continue
            max_bytes = min(settings.capture_upload_max_bytes, 20*1024*1024) if kind == "image" else (config.video_max_bytes or settings.capture_upload_max_bytes)
            if message.file.size and message.file.size > max_bytes:
                continue
            async def chunks():
                async for chunk in self.client.iter_download(message.media):
                    yield chunk
            async with self.storage.stage_stream(chunks=chunks(), content_type=mime, max_bytes=max_bytes) as (stored, temp):
                if kind == "image":
                    data = await asyncio.to_thread(Path(temp).read_bytes)
                    info, _ = await store_media_bytes(data, content_type=mime, kind="image", quality=config.image_webp_quality, storage=self.storage, namespace="vaultstream")
                    key, mime, size = info["stored_key"], info["stored_content_type"], info["stored_size"]
                else:
                    await self.storage.publish_staged(stored, temp)
                    info = {}
                    key, size = stored.key, stored.size
            asset = MediaAsset(content=content, media_type=MediaType(kind),
                role=MediaRole.GALLERY if kind == "image" else MediaRole.ATTACHMENT,
                position=sum(counts.values()), archive_status=MediaArchiveStatus.READY,
                asset_metadata={"filename": message.file.name, "telegram": {
                    "peer_id": post.address.peer_id, "message_id": message.id, "media_id": media.id}},
                variants=[MediaVariant(variant_kind=MediaVariantKind.OPTIMIZED if kind == "image" else MediaVariantKind.ORIGINAL_ARCHIVE,
                    storage_key=key, mime_type=mime, size_bytes=size,
                    checksum=info.get("stored_sha256") or stored.sha256,
                    width=info.get("stored_width"), height=info.get("stored_height"),
                    status=MediaVariantStatus.READY)])
            if info.get("thumb_key") and info["thumb_key"] != key:
                asset.variants.append(MediaVariant(variant_kind=MediaVariantKind.THUMBNAIL,
                    storage_key=info["thumb_key"], mime_type="image/webp", status=MediaVariantStatus.READY))
            db.add(asset)
            counts[kind] = counts.get(kind, 0) + 1
        if counts.get("video"):
            content.layout_type, content.content_type = LayoutType.VIDEO, "video"
        elif counts.get("image"):
            content.layout_type = LayoutType.GALLERY
        elif counts.get("audio"):
            content.layout_type, content.content_type = LayoutType.AUDIO, "audio"
        elif counts.get("document"):
            content.content_type = "document"
