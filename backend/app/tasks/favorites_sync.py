from __future__ import annotations

import asyncio
import json
from collections.abc import Iterable
from typing import Any, Optional

from sqlalchemy import and_, or_, select

from app.adapters import AdapterFactory, open_adapter
from app.adapters.favorites import (
    BaseFavoritesFetcher,
    TwitterFavoritesFetcher,
    XiaohongshuFavoritesFetcher,
    ZhihuFavoritesFetcher,
)
from app.adapters.favorites.errors import FavoritesFetchError
from app.core.database import AsyncSessionLocal
from app.core.logging import ensure_task_id, log_context, logger
from app.models import Content
from app.core.time_utils import utcnow
from app.services.background_task_state import (
    record_task_run_error,
    record_task_run_started,
    record_task_run_success,
    record_task_error,
    record_task_started,
    record_task_success,
)
from app.services.content_service import ContentService
from app.services.settings_service import (
    get_setting_value_fresh,
    set_setting_value,
)


class FavoritesSyncTask:
    """定期同步各平台收藏到主库。"""

    _DEFAULT_INTERVAL_MINUTES = 360
    _DEFAULT_MAX_ITEMS = 50
    _FAILED_ITEMS_RECORD_LIMIT = 50
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

    async def create_run(
        self,
        *,
        platform: str | None,
        trigger: str,
        retry_of: str | None = None,
    ) -> dict:
        scope = (platform or "all").strip().lower()
        metadata = {"scope": scope, "trigger": trigger}
        if retry_of:
            metadata["retry_of"] = retry_of
        return await record_task_run_started("favorites_sync", **metadata)

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
        # Read from DB directly to avoid stale in-process cache when running multi workers.
        raw = await get_setting_value_fresh("favorites_sync_platforms", [])
        parsed = self._parse_enabled_platforms(raw)
        return [p for p in parsed if p in self._fetchers]

    def start(self):
        if self.is_running():
            return
        self._task = asyncio.create_task(self._sync_loop())
        asyncio.create_task(record_task_started("favorites_sync"))
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
                    await get_setting_value_fresh(
                        "favorites_sync_interval_minutes",
                        self._DEFAULT_INTERVAL_MINUTES,
                    )
                )
                if interval <= 0:
                    interval = self._DEFAULT_INTERVAL_MINUTES
                await self.sync_all_platforms_once()
            except Exception as e:
                logger.exception("Favorites sync loop failed: {}", e)
                await record_task_error("favorites_sync", e)
            await asyncio.sleep(interval * 60)

    async def sync_all_platforms_once(
        self,
        *,
        run_id: str | None = None,
        trigger: str = "scheduler",
    ) -> dict[str, dict]:
        task_id = ensure_task_id()
        with log_context(task_id=task_id):
            async with self._lock:
                run = await record_task_run_started(
                    "favorites_sync",
                    run_id=run_id,
                    scope="all",
                    trigger=trigger,
                )
                run_id = str(run["run_id"])
                enabled = await self.load_enabled_platforms()
                results: dict[str, dict] = {}
                for platform in enabled:
                    # Re-check enabled list before each platform to honor runtime toggles ASAP.
                    latest_enabled = await self.load_enabled_platforms()
                    if platform not in latest_enabled:
                        logger.info("[favorites sync] platform disabled at runtime, skip {}", platform)
                        results[platform] = {
                            "platform": platform,
                            "status": "skipped",
                            "reason": "disabled",
                            "at": utcnow().isoformat(),
                        }
                        continue
                    try:
                        results[platform] = await self._sync_platform_by_name_inner(platform)
                    except FavoritesFetchError as e:
                        logger.bind(
                            event="favorites_sync_failed",
                            platform=platform,
                            error_code=e.code,
                            retryable=e.retryable,
                            auth_required=e.auth_required,
                        ).error("Favorites sync failed: {}", e)
                        results[platform] = self._build_failure_result(platform, e)
                    except Exception as e:
                        logger.bind(
                            event="favorites_sync_failed",
                            platform=platform,
                            error_code="internal_error",
                        ).exception("Favorites sync failed unexpectedly: {}", e)
                        results[platform] = self._build_failure_result(
                            platform,
                            FavoritesFetchError(
                                code="internal_error",
                                message=str(e),
                                hint="同步任务内部异常，请查看后端日志",
                                retryable=True,
                            ),
                        )

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
                failed_platforms = [
                    platform
                    for platform, result in results.items()
                    if result.get("status") not in ("success", "skipped")
                ]
                await record_task_success(
                    "favorites_sync",
                    platform_count=len(results),
                    failed_platforms=failed_platforms,
                )
                if failed_platforms:
                    await record_task_error(
                        "favorites_sync",
                        f"Failed platforms: {', '.join(failed_platforms)}",
                        failed_platforms=failed_platforms,
                    )
                    await record_task_run_error(
                        "favorites_sync",
                        run_id,
                        f"Failed platforms: {', '.join(failed_platforms)}",
                        platform_count=len(results),
                        failed_platforms=failed_platforms,
                        results=results,
                    )
                else:
                    await record_task_run_success(
                        "favorites_sync",
                        run_id,
                        platform_count=len(results),
                        failed_platforms=[],
                        results=results,
                    )
                return results

    async def sync_platform_by_name(
        self,
        platform: str,
        *,
        run_id: str | None = None,
        trigger: str = "manual",
    ) -> dict:
        platform = (platform or "").strip().lower()
        if platform not in self._fetchers:
            raise ValueError(f"Unknown platform: {platform}")
        async with self._lock:
            run = await record_task_run_started(
                "favorites_sync",
                run_id=run_id,
                scope=platform,
                trigger=trigger,
            )
            run_id = str(run["run_id"])
            try:
                result = await self._sync_platform_by_name_inner(platform)
                await record_task_success(
                    "favorites_sync",
                    platform_count=1,
                    last_platform=platform,
                    failed_platforms=[] if result.get("status") == "success" else [platform],
                )
                if result.get("status") != "success":
                    error = result.get("error") or result.get("error_message") or result.get("status")
                    await record_task_error(
                        "favorites_sync",
                        error,
                        failed_platforms=[platform],
                        last_platform=platform,
                    )
                    await record_task_run_error(
                        "favorites_sync",
                        run_id,
                        error,
                        platform=platform,
                        result=result,
                    )
                else:
                    await record_task_run_success(
                        "favorites_sync",
                        run_id,
                        platform=platform,
                        result=result,
                    )
                return result
            except Exception as e:
                await record_task_run_error("favorites_sync", run_id, e, platform=platform)
                raise

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

    async def preview_all_platforms(self) -> dict:
        enabled = await self.load_enabled_platforms()
        previews = []
        for platform in enabled:
            previews.append(await self.preview_platform_by_name(platform))
        return self._build_preview_summary("all", previews)

    async def preview_platform_by_name(self, platform: str) -> dict:
        platform = (platform or "").strip().lower()
        fetcher_cls = self._fetchers.get(platform)
        if fetcher_cls is None:
            raise ValueError(f"Unknown platform: {platform}")
        return await self._preview_platform(fetcher_cls())

    @staticmethod
    def _build_preview_summary(platform: str, previews: list[dict]) -> dict:
        has_failure = any(item.get("status") == "failed" for item in previews)
        return {
            "platform": platform,
            "status": "failed" if has_failure else "success",
            "fetched": sum(int(item.get("fetched") or 0) for item in previews),
            "unique": sum(int(item.get("unique") or 0) for item in previews),
            "existing": sum(int(item.get("existing") or 0) for item in previews),
            "estimated_new": sum(int(item.get("estimated_new") or 0) for item in previews),
            "skipped": sum(int(item.get("skipped") or 0) for item in previews),
            "platforms": previews,
        }

    async def _preview_platform(self, fetcher: BaseFavoritesFetcher) -> dict:
        platform = fetcher.platform_name()
        max_items = int(
            await get_setting_value_fresh(
                "favorites_sync_max_items",
                self._DEFAULT_MAX_ITEMS,
            )
        )
        cursor = await get_setting_value_fresh(f"favorites_sync_cursor_{platform}")
        if not isinstance(cursor, str):
            cursor = None

        try:
            is_authenticated = await fetcher.check_auth()
        except FavoritesFetchError as e:
            return self._build_preview_failure(platform, max_items, bool(cursor), e)
        except Exception as e:
            return self._build_preview_failure(
                platform,
                max_items,
                bool(cursor),
                FavoritesFetchError(
                    code="auth_check_failed",
                    message=str(e),
                    hint="认证状态检查失败，请稍后重试",
                    retryable=True,
                ),
            )

        if not is_authenticated:
            return self._build_preview_failure(
                platform,
                max_items,
                bool(cursor),
                FavoritesFetchError(
                    code="auth_required",
                    message="Authentication required",
                    hint="登录状态不可用，请先完成该平台登录",
                    auth_required=True,
                ),
            )

        try:
            items, next_cursor = await fetcher.fetch_favorites(
                max_items=max_items,
                cursor=cursor,
            )
        except FavoritesFetchError as e:
            return self._build_preview_failure(platform, max_items, bool(cursor), e)
        except Exception as e:
            return self._build_preview_failure(
                platform,
                max_items,
                bool(cursor),
                FavoritesFetchError(
                    code="fetch_failed",
                    message=str(e),
                    hint="拉取收藏失败，请查看日志并稍后重试",
                    retryable=True,
                ),
            )

        seen_urls: set[str] = set()
        unique_items = []
        skipped = 0
        for item in items:
            url = (item.url or "").strip()
            if not url or url in seen_urls:
                skipped += 1
                continue
            seen_urls.add(url)
            unique_items.append(item)

        sample_items: list[dict[str, Any]] = []
        existing = 0
        async with AsyncSessionLocal() as session:
            for item in unique_items:
                exists = await self._favorite_item_exists(session, item.url)
                if exists:
                    existing += 1
                if len(sample_items) < 5:
                    sample_items.append(
                        {
                            "url": item.url,
                            "title": item.title,
                            "author": item.author,
                            "content_type": item.content_type,
                            "exists": exists,
                        }
                    )

        return {
            "platform": platform,
            "status": "success",
            "authenticated": True,
            "max_items": max_items,
            "cursor_present": bool(cursor),
            "fetched": len(items),
            "unique": len(unique_items),
            "existing": existing,
            "estimated_new": max(0, len(unique_items) - existing),
            "skipped": skipped,
            "next_cursor_available": next_cursor is not None,
            "error": None,
            "error_code": None,
            "error_message": None,
            "error_hint": None,
            "retryable": False,
            "auth_required": False,
            "items": sample_items,
        }

    @staticmethod
    async def _favorite_item_exists(session, url: str) -> bool:
        platform = AdapterFactory.detect_platform(url)
        canonical_url = url
        if platform is not None:
            try:
                async with open_adapter(platform) as adapter:
                    canonical_url = await adapter.clean_url(url)
            except Exception:
                canonical_url = url

        filters = [Content.url == url, Content.clean_url == canonical_url]
        if platform is not None:
            filters.append(
                and_(Content.platform == platform, Content.canonical_url == canonical_url)
            )
        stmt = select(Content.id).where(or_(*filters)).limit(1)
        return (await session.execute(stmt)).scalar_one_or_none() is not None

    @staticmethod
    def _build_preview_failure(
        platform: str,
        max_items: int,
        cursor_present: bool,
        error: FavoritesFetchError,
    ) -> dict:
        return {
            "platform": platform,
            "status": "failed",
            "authenticated": not error.auth_required,
            "max_items": max_items,
            "cursor_present": cursor_present,
            "fetched": 0,
            "unique": 0,
            "existing": 0,
            "estimated_new": 0,
            "skipped": 0,
            "next_cursor_available": False,
            "error": error.message,
            **error.as_dict(),
            "items": [],
        }

    @staticmethod
    def _build_failure_result(platform: str, error: FavoritesFetchError) -> dict:
        return {
            "platform": platform,
            "status": "failed",
            "authenticated": not error.auth_required,
            "fetched": 0,
            "imported": 0,
            "failed": 0,
            "skipped": 0,
            "error": error.message,
            **error.as_dict(),
            "at": utcnow().isoformat(),
        }

    async def _sync_platform(self, fetcher: BaseFavoritesFetcher) -> dict:
        platform = fetcher.platform_name()
        try:
            is_authenticated = await fetcher.check_auth()
        except FavoritesFetchError as e:
            logger.bind(
                event="favorites_auth_check_failed",
                platform=platform,
                error_code=e.code,
                retryable=e.retryable,
                auth_required=e.auth_required,
            ).warning("Favorites auth check failed: {}", e)
            return self._build_failure_result(platform, e)
        except Exception as e:
            logger.bind(
                event="favorites_auth_check_failed",
                platform=platform,
                error_code="auth_check_failed",
            ).exception("Favorites auth check failed unexpectedly: {}", e)
            return self._build_failure_result(
                platform,
                FavoritesFetchError(
                    code="auth_check_failed",
                    message=str(e),
                    hint="认证状态检查失败，请稍后重试",
                    retryable=True,
                ),
            )

        if not is_authenticated:
            logger.warning("[{} favorites] not authenticated, skip", platform)
            return self._build_failure_result(
                platform,
                FavoritesFetchError(
                    code="auth_required",
                    message="Authentication required",
                    hint="登录状态不可用，请先完成该平台登录",
                    auth_required=True,
                ),
            )

        max_items = int(
            await get_setting_value_fresh(
                "favorites_sync_max_items",
                self._DEFAULT_MAX_ITEMS,
            )
        )
        rate_limit = float(
            await get_setting_value_fresh(
                f"favorites_sync_rate_{platform}",
                self.default_rate_for(platform),
            )
        )
        delay = 60.0 / max(rate_limit, 0.1)
        cursor = await get_setting_value_fresh(f"favorites_sync_cursor_{platform}")
        if not isinstance(cursor, str):
            cursor = None

        try:
            items, next_cursor = await fetcher.fetch_favorites(
                max_items=max_items,
                cursor=cursor,
            )
        except FavoritesFetchError as e:
            logger.bind(
                event="favorites_fetch_failed",
                platform=platform,
                error_code=e.code,
                retryable=e.retryable,
                auth_required=e.auth_required,
            ).warning("Favorites fetch failed: {}", e)
            return self._build_failure_result(platform, e)
        except Exception as e:
            logger.bind(
                event="favorites_fetch_failed",
                platform=platform,
                error_code="fetch_failed",
            ).exception("Favorites fetch failed unexpectedly: {}", e)
            return self._build_failure_result(
                platform,
                FavoritesFetchError(
                    code="fetch_failed",
                    message=str(e),
                    hint="拉取收藏失败，请查看日志并稍后重试",
                    retryable=True,
                ),
            )
        logger.info("[{} favorites] fetched {}", platform, len(items))

        imported = 0
        skipped = 0
        failed = 0
        failed_items: list[dict[str, Any]] = []
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
                    if len(failed_items) < self._FAILED_ITEMS_RECORD_LIMIT:
                        failed_items.append(
                            {
                                "url": item.url,
                                "title": item.title,
                                "item_id": item.item_id,
                                "error": str(e)[:500],
                                "error_code": e.__class__.__name__,
                            }
                        )
                    logger.bind(
                        event="favorites_import_failed",
                        platform=platform,
                        item_url=item.url,
                    ).exception("Favorites import failed: {}", e)
                await asyncio.sleep(delay)

        if next_cursor is not None:
            await set_setting_value(
                f"favorites_sync_cursor_{platform}",
                next_cursor,
                category="favorites_sync",
            )

        result = {
            "platform": platform,
            "status": "success" if failed == 0 else "partial_success",
            "authenticated": True,
            "fetched": len(items),
            "imported": imported,
            "failed": failed,
            "failed_items": failed_items,
            "failed_items_total": failed,
            "failed_items_truncated": failed > len(failed_items),
            "skipped": skipped,
            "next_cursor": next_cursor,
            "error": None,
            "error_code": None,
            "error_message": None,
            "error_hint": None,
            "retryable": False,
            "auth_required": False,
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
