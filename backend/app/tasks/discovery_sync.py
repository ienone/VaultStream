"""
发现源定时同步任务

定期检查到期的发现源并抓取新内容入库。
"""
import asyncio
from datetime import timedelta

from loguru import logger
from sqlalchemy import select

from app.adapters.discovery.base import BaseDiscoveryScraper
from app.adapters.discovery.rss import RSSDiscoveryScraper
from app.core.db_adapter import AsyncSessionLocal
from app.core.time_utils import utcnow
from app.models import (
    Content,
    ContentStatus,
    DiscoverySource,
    DiscoverySourceKind,
    DiscoveryState,
    Platform,
)
from app.services.patrol_service import PatrolService
from app.services.settings_service import get_setting_value
from app.utils.url_utils import normalize_url_for_dedup


class DiscoverySyncTask:
    """发现源定时同步任务"""

    def __init__(self):
        self.running = False

    def start(self):
        self.running = True
        asyncio.create_task(self._sync_loop())

    async def stop(self):
        self.running = False

    async def _sync_loop(self):
        """Main loop: check sources due for sync every 60 seconds"""
        logger.info("Discovery sync task started")
        while self.running:
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

    async def _sync_single_source(self, db, source: DiscoverySource):
        """Sync a single discovery source"""
        scraper = self._get_scraper(source)
        if not scraper:
            return

        try:
            items, new_cursor = await scraper.fetch(last_cursor=source.last_cursor)

            ingested_count = 0
            for item in items:
                canonical = normalize_url_for_dedup(item.url)

                existing = await db.execute(
                    select(Content.id)
                    .where(Content.canonical_url == canonical)
                    .limit(1)
                )
                if existing.scalars().first() is not None:
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
                    source_type=source.kind.value,
                    discovery_state=DiscoveryState.INGESTED,
                    discovered_at=utcnow(),
                    published_at=item.published_at,
                    expire_at=utcnow() + timedelta(days=retention_days),
                    source_tags=item.source_tags,
                    status=ContentStatus.UNPROCESSED,
                )
                db.add(content)
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

                patrol = PatrolService()
                await patrol.score_pending(db)

        except Exception as e:
            source.last_error = str(e)[:500]
            source.last_sync_at = utcnow()
            await db.commit()
            logger.warning(f"Discovery sync [{source.name}] failed: {e}")

    def _get_scraper(self, source: DiscoverySource) -> BaseDiscoveryScraper | None:
        """Factory: return the correct scraper for the source kind"""
        if source.kind == DiscoverySourceKind.RSS:
            return RSSDiscoveryScraper(source.config or {})
        logger.warning(f"No scraper for source kind: {source.kind}")
        return None
