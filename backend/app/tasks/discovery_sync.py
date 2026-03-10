"""
发现源定时同步任务

定期检查到期的发现源并抓取新内容入库。
"""
import asyncio
from datetime import timedelta

from loguru import logger
from sqlalchemy import select
from sqlalchemy.orm.attributes import flag_modified

from app.adapters.discovery.base import BaseDiscoveryScraper
from app.adapters.discovery.rss import RSSDiscoveryScraper
from app.adapters.discovery.telegram import TelegramDiscoveryScraper
from app.core.db_adapter import AsyncSessionLocal
from app.core.time_utils import utcnow
from app.adapters.storage import get_storage_backend
from app.core.config import settings
from app.media.processor import store_archive_images_as_webp
from app.models import (
    Content,
    ContentDiscoveryLink,
    ContentStatus,
    DiscoverySource,
    DiscoverySourceKind,
    DiscoveryState,
    LayoutType,
    Platform,
)
from app.services.patrol_service import PatrolService
from app.services.settings_service import get_setting_value
from app.utils.url_utils import normalize_url_for_dedup
from app.utils.datetime_utils import normalize_datetime_for_db


class DiscoverySyncTask:
    """发现源定时同步任务"""

    def __init__(self):
        self._task: asyncio.Task | None = None

    def start(self):
        self._task = asyncio.create_task(self._sync_loop())

    async def stop(self):
        if self._task and not self._task.done():
            self._task.cancel()
            try:
                await self._task
            except asyncio.CancelledError:
                pass

    async def _sync_loop(self):
        """Main loop: check sources due for sync every 60 seconds"""
        logger.info("Discovery sync task started")
        while True:
            try:
                await self._sync_due_sources()
            except Exception as e:
                logger.error(f"Discovery sync error: {e}")
            await asyncio.sleep(60)

    async def _sync_due_sources(self):
        """Find sources where now > last_sync_at + sync_interval_minutes, and sync them"""
        async with AsyncSessionLocal() as db:
            stmt = select(DiscoverySource).where(
                DiscoverySource.enabled == True,  # noqa: E712
                DiscoverySource.kind.in_([k.value for k in DiscoverySourceKind]),
            )
            result = await db.execute(stmt)
            sources = result.scalars().all()

            now = utcnow()
            for source in sources:
                if source.last_sync_at:
                    next_sync = source.last_sync_at + timedelta(
                        minutes=source.sync_interval_minutes
                    )
                    if now < next_sync:
                        continue

                await self._sync_single_source(db, source)

    async def sync_source_by_id(self, source_id: int):
        """Manually trigger sync for a specific source, managing its own DB session."""
        async with AsyncSessionLocal() as db:
            result = await db.execute(
                select(DiscoverySource).where(DiscoverySource.id == source_id)
            )
            source = result.scalar_one_or_none()
            if source is None:
                logger.warning(f"Discovery manual sync: source {source_id} not found")
                return
            await self._sync_single_source(db, source)

    async def _sync_single_source(self, db, source: DiscoverySource):
        """Sync a single discovery source"""
        scraper = self._get_scraper(source)
        if not scraper:
            return

        try:
            items, new_cursor = await scraper.fetch(last_cursor=source.last_cursor)

            ingested_count = 0
            new_content_ids = []
            for item in items:
                canonical = normalize_url_for_dedup(item.url)
                cover_candidate = item.cover_url or (item.media_urls[0] if item.media_urls else None)

                # 检查 URL 是否已存在（主库或发现流）
                stmt = select(Content).where(Content.canonical_url == canonical).limit(1)
                result = await db.execute(stmt)
                existing_content = result.scalars().first()

                if existing_content is not None:
                    # 检查关联是否已存在
                    link_exists = (await db.execute(
                        select(ContentDiscoveryLink.id).where(
                            ContentDiscoveryLink.content_id == existing_content.id,
                            ContentDiscoveryLink.discovery_source_id == source.id,
                        ).limit(1)
                    )).scalar() is not None

                    if not link_exists:
                        db.add(ContentDiscoveryLink(
                            content_id=existing_content.id,
                            discovery_source_id=source.id,
                            url=item.url,
                        ))

                    # 回填冗余外键（首次被发现源匹配时设置）
                    if existing_content.discovery_source_id is None:
                        existing_content.discovery_source_id = source.id

                    existing_media_urls = (
                        existing_content.media_urls
                        if isinstance(existing_content.media_urls, list)
                        else []
                    )
                    existing_cover_is_fallback = bool(
                        existing_content.cover_url
                        and existing_media_urls
                        and existing_content.cover_url == existing_media_urls[0]
                    )

                    if item.cover_url and (
                        not existing_content.cover_url or existing_cover_is_fallback
                    ):
                        existing_content.cover_url = item.cover_url
                    elif cover_candidate and not existing_content.cover_url:
                        existing_content.cover_url = cover_candidate

                    if item.media_urls and not existing_content.media_urls:
                        existing_content.media_urls = item.media_urls

                    continue

                retention_days_raw = await get_setting_value("discovery_retention_days", 7)
                try:
                    retention_days = int(retention_days_raw)
                except (TypeError, ValueError):
                    retention_days = 7

                content = Content(
                    platform=Platform.UNIVERSAL,
                    url=item.url,
                    canonical_url=canonical,
                    title=item.title,
                    body=item.content if item.content else None,
                    author_name=item.author,
                    author_avatar_url=item.author_avatar_url,
                    author_url=item.author_url,
                    source_type=source.kind.value,
                    discovery_state=DiscoveryState.INGESTED,
                    discovered_at=utcnow(),
                    published_at=normalize_datetime_for_db(item.published_at),
                    updated_at=None,
                    expire_at=utcnow() + timedelta(days=retention_days),
                    source_tags=item.source_tags,
                    status=ContentStatus.PARSE_SUCCESS,
                    layout_type=LayoutType.ARTICLE,
                    cover_url=cover_candidate,
                    media_urls=item.media_urls,
                    rich_payload=item.rich_payload,
                    extra_stats=item.extra_stats,
                    context_data=None,
                    discovery_source_id=source.id,
                )
                db.add(content)
                await db.flush()
                db.add(ContentDiscoveryLink(
                    content_id=content.id,
                    discovery_source_id=source.id,
                    url=item.url,
                ))
                new_content_ids.append(content.id)
                ingested_count += 1

            source.last_sync_at = utcnow()
            if new_cursor:
                source.last_cursor = new_cursor
            source.last_error = None

            await db.commit()

            if ingested_count > 0:
                logger.info(
                    f"Discovery sync [{source.name}]: ingested {ingested_count} items"
                )

                try:
                    await self._archive_discovery_media(db, new_content_ids)
                except Exception as e:
                    logger.warning(f"Discovery media archiving [{source.name}] error: {e}")

                patrol = PatrolService()
                await patrol.score_pending(db)

        except Exception as e:
            source.last_error = str(e)[:500]
            source.last_sync_at = utcnow()
            await db.commit()
            logger.warning(f"Discovery sync [{source.name}] failed: {e}")

    async def _archive_discovery_media(self, db, content_ids: list[int]):
        """Download and convert images to WebP for newly ingested discovery items."""
        enable_processing = await get_setting_value(
            "enable_archive_media_processing",
            settings.enable_archive_media_processing,
        )
        if not enable_processing:
            return

        if not content_ids:
            return

        storage = get_storage_backend()
        ensure_bucket = getattr(storage, "ensure_bucket", None)
        if callable(ensure_bucket):
            await ensure_bucket()

        namespace = "vaultstream"
        quality = int(
            await get_setting_value(
                "archive_image_webp_quality",
                settings.archive_image_webp_quality,
            ) or 80
        )
        max_count = await get_setting_value(
            "archive_image_max_count",
            settings.archive_image_max_count,
        )
        if max_count is not None:
            max_count = int(max_count)

        stmt = select(Content).where(Content.id.in_(content_ids))
        result = await db.execute(stmt)
        contents = result.scalars().all()

        for content in contents:
            if not content.media_urls:
                continue
            try:
                archive = {
                    "images": [{"url": url, "type": "image"} for url in content.media_urls],
                }
                await store_archive_images_as_webp(
                    archive=archive,
                    storage=storage,
                    namespace=namespace,
                    quality=quality,
                    max_images=max_count,
                )

                stored_images = archive.get("stored_images", [])
                if not stored_images:
                    continue

                local_urls = []
                url_mapping = {}
                for img in stored_images:
                    if img.get("key"):
                        local_url = f"local://{img['key']}"
                        local_urls.append(local_url)
                        orig_url = img.get("orig_url") or img.get("url")
                        if orig_url:
                            url_mapping[orig_url] = local_url

                if local_urls:
                    content.media_urls = list(dict.fromkeys(local_urls))
                    flag_modified(content, "media_urls")

                if content.cover_url and content.cover_url in url_mapping:
                    content.cover_url = url_mapping[content.cover_url]
                elif not content.cover_url and local_urls:
                    content.cover_url = local_urls[0]

                # M4/M5: 提取并保留主色调 (cover_color)
                dominant_color = archive.get("dominant_color")
                if dominant_color:
                    content.cover_color = dominant_color

            except Exception as e:
                logger.warning(f"Discovery media archive failed for content {content.id}: {e}")
                continue

        await db.commit()

    def _get_scraper(self, source: DiscoverySource) -> BaseDiscoveryScraper | None:
        """Factory: return the correct scraper for the source kind"""
        if source.kind == DiscoverySourceKind.RSS:
            return RSSDiscoveryScraper(source.config or {})
        elif source.kind == DiscoverySourceKind.TELEGRAM_CHANNEL:
            return TelegramDiscoveryScraper(source.config or {})
        logger.warning(f"No scraper for source kind: {source.kind}")
        return None
