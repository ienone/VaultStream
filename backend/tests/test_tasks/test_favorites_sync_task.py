from __future__ import annotations

from unittest.mock import AsyncMock, patch

import pytest

from app.adapters.favorites.base import BaseFavoritesFetcher, FavoriteItem
from app.adapters.favorites.errors import FavoritesFetchError
from app.services.config_service import FavoritesSyncConfig, FavoritesSyncPlatformState
from app.tasks.favorites_sync import FavoritesSyncTask


class _FakeFavoritesConfigService:
    def __init__(
        self,
        *,
        enabled_platforms: list[str] | None = None,
        max_items: int = 50,
        rate_per_minute: float = 5,
        duplicate_strategy: str = "merge",
        cursor: str | None = None,
    ) -> None:
        self.enabled_platforms = enabled_platforms or []
        self.max_items = max_items
        self.rate_per_minute = rate_per_minute
        self.duplicate_strategy = duplicate_strategy
        self.cursor = cursor
        self.writes: list[tuple[str, object]] = []

    async def get_favorites_sync_config(self, **kwargs) -> FavoritesSyncConfig:
        strategy = self.duplicate_strategy
        allowed = kwargs.get("allowed_duplicate_strategies")
        if allowed and strategy not in allowed:
            strategy = kwargs["default_duplicate_strategy"]
        supported = set(kwargs.get("supported_platforms") or [])
        enabled = [
            platform for platform in self.enabled_platforms if not supported or platform in supported
        ]
        return FavoritesSyncConfig(
            enabled_platforms=enabled,
            interval_minutes=kwargs["default_interval_minutes"],
            max_items=self.max_items,
            duplicate_strategy=strategy,
            last_sync_at=None,
        )

    async def get_favorites_sync_platform_state(
        self,
        platform: str,
        **kwargs,
    ) -> FavoritesSyncPlatformState:
        return FavoritesSyncPlatformState(
            platform=platform,
            rate_per_minute=self.rate_per_minute,
            cursor=self.cursor,
            last_result=None,
        )

    async def set_favorites_sync_last_sync_at(self, value):
        self.writes.append(("last_sync_at", value))

    async def set_favorites_sync_last_result(self, value):
        self.writes.append(("last_result", value))

    async def set_favorites_sync_platform_last_result(self, platform, value):
        self.writes.append((f"last_result_{platform}", value))

    async def set_favorites_sync_cursor(self, platform, value):
        self.writes.append((f"cursor_{platform}", value))


class _AuthMissingFetcher(BaseFavoritesFetcher):
    def platform_name(self) -> str:
        return "dummy"

    async def check_auth(self) -> bool:
        return False

    async def fetch_favorites(
        self,
        *,
        max_items: int = 50,
        cursor: str | None = None,
    ) -> tuple[list[FavoriteItem], str | None]:
        raise AssertionError("fetch_favorites should not be called when auth is missing")


class _ErrorFetcher(BaseFavoritesFetcher):
    def platform_name(self) -> str:
        return "dummy"

    async def check_auth(self) -> bool:
        return True

    async def fetch_favorites(
        self,
        *,
        max_items: int = 50,
        cursor: str | None = None,
    ) -> tuple[list[FavoriteItem], str | None]:
        raise FavoritesFetchError(
            code="rate_limited",
            message="rate limit hit",
            hint="slow down and retry later",
            retryable=True,
        )


class _OneItemFetcher(BaseFavoritesFetcher):
    def platform_name(self) -> str:
        return "dummy"

    async def check_auth(self) -> bool:
        return True

    async def fetch_favorites(
        self,
        *,
        max_items: int = 50,
        cursor: str | None = None,
    ) -> tuple[list[FavoriteItem], str | None]:
        return [FavoriteItem(url="https://example.com/favorite")], None


class _TwoItemFetcher(BaseFavoritesFetcher):
    def platform_name(self) -> str:
        return "dummy"

    async def check_auth(self) -> bool:
        return True

    async def fetch_favorites(
        self,
        *,
        max_items: int = 50,
        cursor: str | None = None,
    ) -> tuple[list[FavoriteItem], str | None]:
        return (
            [
                FavoriteItem(
                    url="https://example.com/ok",
                    title="正常收藏",
                    item_id="ok-1",
                ),
                FavoriteItem(
                    url="https://example.com/fail",
                    title="失败收藏",
                    item_id="fail-1",
                ),
            ],
            None,
        )


class _ManyFailingItemsFetcher(BaseFavoritesFetcher):
    def platform_name(self) -> str:
        return "dummy"

    async def check_auth(self) -> bool:
        return True

    async def fetch_favorites(
        self,
        *,
        max_items: int = 50,
        cursor: str | None = None,
    ) -> tuple[list[FavoriteItem], str | None]:
        return (
            [
                FavoriteItem(
                    url=f"https://example.com/fail-{index}",
                    title=f"失败收藏 {index}",
                    item_id=f"fail-{index}",
                )
                for index in range(55)
            ],
            None,
        )


@pytest.mark.asyncio
async def test_sync_platform_returns_unified_auth_failure_payload():
    task = FavoritesSyncTask()

    result = await task._sync_platform(_AuthMissingFetcher())

    assert result["status"] == "failed"
    assert result["platform"] == "dummy"
    assert result["authenticated"] is False
    assert result["error_code"] == "auth_required"
    assert result["auth_required"] is True
    assert result["error_hint"]
    assert result["fetched"] == 0
    assert result["imported"] == 0


@pytest.mark.asyncio
async def test_sync_platform_preserves_structured_fetch_error():
    task = FavoritesSyncTask(config_service=_FakeFavoritesConfigService())

    result = await task._sync_platform(_ErrorFetcher())

    assert result["status"] == "failed"
    assert result["platform"] == "dummy"
    assert result["authenticated"] is True
    assert result["error_code"] == "rate_limited"
    assert result["error_message"] == "rate limit hit"
    assert result["error_hint"] == "slow down and retry later"
    assert result["retryable"] is True
    assert result["auth_required"] is False


@pytest.mark.asyncio
async def test_sync_platform_imports_favorites_through_content_service():
    task = FavoritesSyncTask(config_service=_FakeFavoritesConfigService())

    with patch(
        "app.services.content_service.ContentService.create_share",
        new=AsyncMock(),
    ) as create_share:
        result = await task._sync_platform(_OneItemFetcher())

    assert result["status"] == "success"
    assert result["imported"] == 1
    create_share.assert_awaited_once_with(
        url="https://example.com/favorite",
        tags=[],
        source_name="favorites_sync:dummy",
    )


@pytest.mark.asyncio
async def test_sync_platform_records_failed_item_samples():
    task = FavoritesSyncTask(
        config_service=_FakeFavoritesConfigService(rate_per_minute=1000000)
    )

    with patch(
        "app.services.content_service.ContentService.create_share",
        new=AsyncMock(side_effect=[object(), RuntimeError("import exploded")]),
    ):
        result = await task._sync_platform(_TwoItemFetcher())

    assert result["status"] == "partial_success"
    assert result["imported"] == 1
    assert result["failed"] == 1
    assert result["failed_items"] == [
        {
            "url": "https://example.com/fail",
            "title": "失败收藏",
            "item_id": "fail-1",
            "error": "import exploded",
            "error_code": "RuntimeError",
        }
    ]
    assert result["failed_items_total"] == 1
    assert result["failed_items_truncated"] is False


@pytest.mark.asyncio
async def test_sync_platform_records_bounded_failed_item_list():
    task = FavoritesSyncTask(
        config_service=_FakeFavoritesConfigService(
            max_items=100,
            rate_per_minute=1000000,
        )
    )

    with patch(
        "app.services.content_service.ContentService.create_share",
        new=AsyncMock(side_effect=RuntimeError("import exploded")),
    ):
        result = await task._sync_platform(_ManyFailingItemsFetcher())

    assert result["status"] == "partial_success"
    assert result["failed"] == 55
    assert result["failed_items_total"] == 55
    assert result["failed_items_truncated"] is True
    assert len(result["failed_items"]) == 50
    assert result["failed_items"][-1]["url"] == "https://example.com/fail-49"


@pytest.mark.asyncio
async def test_sync_all_platforms_once_rechecks_enabled_before_each_platform():
    task = FavoritesSyncTask()
    task._fetchers = {
        "zhihu": _AuthMissingFetcher,
        "twitter": _AuthMissingFetcher,
    }

    enabled_snapshots = iter(
        [
            ["zhihu", "twitter"],  # initial list for this round
            ["zhihu", "twitter"],  # recheck before zhihu
            ["zhihu"],             # recheck before twitter (disabled at runtime)
        ]
    )

    async def _load_enabled():
        return next(enabled_snapshots)

    task.load_enabled_platforms = AsyncMock(side_effect=_load_enabled)  # type: ignore[method-assign]
    task._sync_platform_by_name_inner = AsyncMock(return_value={"status": "ok"})  # type: ignore[method-assign]
    task._config_service = _FakeFavoritesConfigService()

    result = await task.sync_all_platforms_once()

    assert result["zhihu"]["status"] == "ok"
    assert result["twitter"]["status"] == "skipped"
    assert result["twitter"]["reason"] == "disabled"
    task._sync_platform_by_name_inner.assert_awaited_once_with("zhihu")
