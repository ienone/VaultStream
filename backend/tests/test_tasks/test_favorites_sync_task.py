from __future__ import annotations

from unittest.mock import AsyncMock, patch

import pytest

from app.adapters.favorites.base import BaseFavoritesFetcher, FavoriteItem
from app.adapters.favorites.errors import FavoritesFetchError
from app.tasks.favorites_sync import FavoritesSyncTask


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
    task = FavoritesSyncTask()

    async def _get_setting_value(key: str, default=None):
        if key == "favorites_sync_max_items":
            return 50
        if key.startswith("favorites_sync_rate_"):
            return 5
        if key.startswith("favorites_sync_cursor_"):
            return None
        return default

    with patch(
        "app.tasks.favorites_sync.get_setting_value_fresh",
        new=AsyncMock(side_effect=_get_setting_value),
    ):
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
    task = FavoritesSyncTask()

    async def _get_setting_value(key: str, default=None):
        if key == "favorites_sync_max_items":
            return 50
        if key.startswith("favorites_sync_rate_"):
            return 5
        if key.startswith("favorites_sync_cursor_"):
            return None
        return default

    with patch(
        "app.tasks.favorites_sync.get_setting_value_fresh",
        new=AsyncMock(side_effect=_get_setting_value),
    ), patch(
        "app.tasks.favorites_sync.set_setting_value",
        new=AsyncMock(),
    ), patch(
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

    with patch(
        "app.tasks.favorites_sync.set_setting_value",
        new=AsyncMock(),
    ):
        result = await task.sync_all_platforms_once()

    assert result["zhihu"]["status"] == "ok"
    assert result["twitter"]["status"] == "skipped"
    assert result["twitter"]["reason"] == "disabled"
    task._sync_platform_by_name_inner.assert_awaited_once_with("zhihu")
