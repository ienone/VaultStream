from __future__ import annotations

import asyncio
import json
from collections.abc import Iterable
from typing import Optional

from app.adapters.favorites import (
    BaseFavoritesFetcher,
    TwitterFavoritesFetcher,
    XiaohongshuFavoritesFetcher,
    ZhihuFavoritesFetcher,
)
from app.core.database import AsyncSessionLocal
from app.core.logging import logger
from app.core.time_utils import utcnow
from app.services.content_service import ContentService
from app.services.settings_service import get_setting_value, set_setting_value


class FavoritesSyncTask:
    """定期同步各平台收藏到主库。"""

    _DEFAULT_INTERVAL_MINUTES = 360
    _DEFAULT_MAX_ITEMS = 50
    _DEFAULT_RATES = {
        "zhihu": 5.0,
        "xiaohongshu": 3.0,
        "twitter": 5.0,
    }

    def __init__(self):
        self._task: asyncio.Task | None = None
        self._lock = asyncio.Lock()
        self._fetchers = self.get_fetcher_registry()

    @staticmethod
    def get_fetcher_registry() -> dict[str, type[BaseFavoritesFetcher]]:
        return {
            "zhihu": ZhihuFavoritesFetcher,
            "xiaohongshu": XiaohongshuFavoritesFetcher,
            "twitter": TwitterFavoritesFetcher,
        }

    def get_supported_platforms(self) -> list[str]:
        return list(self._fetchers.keys())

    def get_fetcher_cls(self, platform: str) -> Optional[type[BaseFavoritesFetcher]]:
        return self._fetchers.get(platform)

    def default_rate_for(self, platform: str) -> float:
        return float(self._DEFAULT_RATES.get(platform, 5.0))

    def is_running(self) -> bool:
        return bool(self._task and not self._task.done())

    @staticmethod
    def _parse_enabled_platforms(raw_value: object) -> list[str]:
        if raw_value is None:
            return []
        if isinstance(raw_value, str):
            text = raw_value.strip()
            if not text:
                return []
            try:
                parsed = json.loads(text)
                if isinstance(parsed, list):
                    return [str(x).strip().lower() for x in parsed if str(x).strip()]
            except json.JSONDecodeError:
                pass
            return [x.strip().lower() for x in text.split(",") if x.strip()]
        if isinstance(raw_value, Iterable):
            values: list[str] = []
            for x in raw_value:
                sx = str(x).strip().lower()
                if sx:
                    values.append(sx)
            return values
        return []

    async def load_enabled_platforms(self) -> list[str]:
        raw = await get_setting_value("favorites_sync_platforms", [])
        parsed = self._parse_enabled_platforms(raw)
        return [p for p in parsed if p in self._fetchers]

    def start(self):
        if self.is_running():
            return
        self._task = asyncio.create_task(self._sync_loop())
        logger.info("FavoritesSyncTask started")

    async def stop(self):
        if self._task and not self._task.done():
            self._task.cancel()
            try:
                await self._task
            except asyncio.CancelledError:
                pass

    async def _sync_loop(self):
        while True:
            try:
                interval = int(
                    await get_setting_value(
                        "favorites_sync_interval_minutes",
                        self._DEFAULT_INTERVAL_MINUTES,
                    )
                )
                if interval <= 0:
                    interval = self._DEFAULT_INTERVAL_MINUTES
                await self.sync_all_platforms_once()
            except Exception as e:
                logger.error("Favorites sync loop failed: {}", e)
            await asyncio.sleep(interval * 60)

    async def sync_all_platforms_once(self) -> dict[str, dict]:
        async with self._lock:
            enabled = await self.load_enabled_platforms()
            results: dict[str, dict] = {}
            for platform in enabled:
                try:
                    results[platform] = await self._sync_platform_by_name_inner(platform)
                except Exception as e:
                    logger.error("Favorites sync [{}] failed: {}", platform, e)
                    results[platform] = {
                        "platform": platform,
                        "error": str(e),
                        "fetched": 0,
                        "imported": 0,
                        "failed": 0,
                    }

            now_iso = utcnow().isoformat()
            await set_setting_value(
                "favorites_sync_last_sync_at",
                now_iso,
                category="favorites_sync",
            )
            await set_setting_value(
                "favorites_sync_last_result",
                results,
                category="favorites_sync",
            )
            return results

    async def sync_platform_by_name(self, platform: str) -> dict:
        platform = (platform or "").strip().lower()
        if platform not in self._fetchers:
            raise ValueError(f"Unknown platform: {platform}")
        async with self._lock:
            return await self._sync_platform_by_name_inner(platform)

    async def _sync_platform_by_name_inner(self, platform: str) -> dict:
        fetcher_cls = self._fetchers[platform]
        result = await self._sync_platform(fetcher_cls())
        await set_setting_value(
            f"favorites_sync_last_result_{platform}",
            result,
            category="favorites_sync",
        )
        await set_setting_value(
            "favorites_sync_last_sync_at",
            utcnow().isoformat(),
            category="favorites_sync",
        )
        return result

    async def _sync_platform(self, fetcher: BaseFavoritesFetcher) -> dict:
        platform = fetcher.platform_name()
        if not await fetcher.check_auth():
            logger.warning("[{} favorites] not authenticated, skip", platform)
            return {
                "platform": platform,
                "authenticated": False,
                "fetched": 0,
                "imported": 0,
                "failed": 0,
                "skipped": 0,
                "at": utcnow().isoformat(),
            }

        max_items = int(
            await get_setting_value(
                "favorites_sync_max_items",
                self._DEFAULT_MAX_ITEMS,
            )
        )
        rate_limit = float(
            await get_setting_value(
                f"favorites_sync_rate_{platform}",
                self.default_rate_for(platform),
            )
        )
        delay = 60.0 / max(rate_limit, 0.1)
        cursor = await get_setting_value(f"favorites_sync_cursor_{platform}")
        if not isinstance(cursor, str):
            cursor = None

        items, next_cursor = await fetcher.fetch_favorites(
            max_items=max_items,
            cursor=cursor,
        )
        logger.info("[{} favorites] fetched {}", platform, len(items))

        imported = 0
        skipped = 0
        failed = 0
        seen_urls: set[str] = set()

        async with AsyncSessionLocal() as session:
            svc = ContentService(session)
            for item in items:
                if not item.url:
                    skipped += 1
                    continue
                if item.url in seen_urls:
                    skipped += 1
                    continue
                seen_urls.add(item.url)

                try:
                    await svc.create_share(
                        url=item.url,
                        tags=[],
                        source_name=f"favorites_sync:{platform}",
                    )
                    imported += 1
                except ValueError:
                    skipped += 1
                except Exception as e:
                    failed += 1
                    logger.warning("[{} favorites] import failed: {} ({})", platform, item.url, e)
                await asyncio.sleep(delay)

        if next_cursor is not None:
            await set_setting_value(
                f"favorites_sync_cursor_{platform}",
                next_cursor,
                category="favorites_sync",
            )

        result = {
            "platform": platform,
            "authenticated": True,
            "fetched": len(items),
            "imported": imported,
            "failed": failed,
            "skipped": skipped,
            "next_cursor": next_cursor,
            "at": utcnow().isoformat(),
        }
        logger.info(
            "[{} favorites] imported {}/{} (failed={}, skipped={})",
            platform,
            imported,
            len(items),
            failed,
            skipped,
        )
        return result
