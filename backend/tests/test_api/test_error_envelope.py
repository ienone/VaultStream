from __future__ import annotations

from unittest.mock import AsyncMock, patch

import pytest
from httpx import ASGITransport, AsyncClient
from pydantic import SecretStr

from app.adapters.favorites.base import BaseFavoritesFetcher, FavoriteItem
from app.adapters.favorites.errors import FavoritesFetchError
from app.adapters.favorites.zhihu_fetcher import ZhihuFavoritesFetcher
from app.core.config import settings
from app.main import app


class _CliMissingFetcher(BaseFavoritesFetcher):
    def platform_name(self) -> str:
        return "twitter"

    async def check_auth(self) -> bool:
        raise FavoritesFetchError(
            code="cli_unavailable",
            message="twitter cli missing",
            hint="install twitter cli first",
        )

    async def fetch_favorites(
        self,
        *,
        max_items: int = 50,
        cursor: str | None = None,
    ) -> tuple[list[FavoriteItem], str | None]:
        return [], None


class _FakeFavoritesTask:
    async def load_enabled_platforms(self) -> list[str]:
        return ["twitter"]

    def get_supported_platforms(self) -> list[str]:
        return ["twitter"]

    def get_fetcher_cls(self, platform: str):
        return _CliMissingFetcher if platform == "twitter" else None

    def default_rate_for(self, platform: str) -> float:
        return 5.0

    def is_running(self) -> bool:
        return True


class _ShouldNotProbeFetcher(BaseFavoritesFetcher):
    def platform_name(self) -> str:
        return "twitter"

    async def check_auth(self) -> bool:
        raise AssertionError("check_auth should not be called for disabled platforms")

    async def fetch_favorites(
        self,
        *,
        max_items: int = 50,
        cursor: str | None = None,
    ) -> tuple[list[FavoriteItem], str | None]:
        return [], None


class _DisabledPlatformTask:
    async def load_enabled_platforms(self) -> list[str]:
        return []

    def get_supported_platforms(self) -> list[str]:
        return ["twitter"]

    def get_fetcher_cls(self, platform: str):
        return _ShouldNotProbeFetcher if platform == "twitter" else None

    def default_rate_for(self, platform: str) -> float:
        return 5.0

    def is_running(self) -> bool:
        return True


@pytest.mark.asyncio
async def test_unauthorized_error_uses_structured_envelope():
    transport = ASGITransport(app=app)
    original_token = settings.api_token
    settings.api_token = SecretStr("test_api_token_123")
    try:
        async with AsyncClient(transport=transport, base_url="http://test") as c:
            resp = await c.get("/api/v1/settings")
    finally:
        settings.api_token = original_token

    assert resp.status_code == 401
    body = resp.json()
    assert body["detail"] == "Invalid or missing API Token"
    assert body["error_message"] == "Invalid or missing API Token"
    assert body["error_code"] == "invalid_api_token"
    assert body["request_id"]


@pytest.mark.asyncio
async def test_favorites_status_contains_structured_status_error(client: AsyncClient):
    app.state.favorites_sync_task = _FakeFavoritesTask()

    async def _get_setting_value(key: str, default=None):
        if key == "favorites_sync_last_result_twitter":
            return None
        return default

    with patch(
        "app.services.settings_service.get_setting_value",
        new=AsyncMock(side_effect=_get_setting_value),
    ):
        resp = await client.get("/api/v1/favorites-sync/status")

    assert resp.status_code == 200
    body = resp.json()
    assert body["platforms"]
    platform = body["platforms"][0]
    assert platform["platform"] == "twitter"
    assert platform["available"] is False
    assert platform["status_error"]["error_code"] == "cli_unavailable"
    assert platform["status_error"]["error_hint"] == "install twitter cli first"


@pytest.mark.asyncio
async def test_method_not_allowed_preserves_allow_header(client: AsyncClient):
    resp = await client.get("/api/v1/favorites-sync/sync")
    assert resp.status_code == 405
    allow = resp.headers.get("allow", "")
    assert "POST" in allow.upper()


@pytest.mark.asyncio
async def test_favorites_status_skips_auth_probe_for_disabled_platforms(client: AsyncClient):
    app.state.favorites_sync_task = _DisabledPlatformTask()

    async def _get_setting_value(key: str, default=None):
        if key == "favorites_sync_last_result_twitter":
            return None
        return default

    with patch(
        "app.services.settings_service.get_setting_value",
        new=AsyncMock(side_effect=_get_setting_value),
    ):
        resp = await client.get("/api/v1/favorites-sync/status")

    assert resp.status_code == 200
    body = resp.json()
    assert body["platforms"]
    platform = body["platforms"][0]
    assert platform["platform"] == "twitter"
    assert platform["enabled"] is False
    assert platform["available"] is True
    assert platform["authenticated"] is False
    assert platform["status_error"] is None


def test_zhihu_refresh_page_url_maps_me_endpoint():
    assert (
        ZhihuFavoritesFetcher._to_refresh_page_url("https://www.zhihu.com/api/v4/me")
        == "https://www.zhihu.com/"
    )


def test_zhihu_refresh_page_url_maps_people_collections():
    url = "https://www.zhihu.com/api/v4/people/liu-kan-shan-78/collections?limit=20&offset=0"
    assert (
        ZhihuFavoritesFetcher._to_refresh_page_url(url)
        == "https://www.zhihu.com/people/liu-kan-shan-78/collections"
    )


def test_zhihu_refresh_page_url_maps_collection_items():
    url = "https://www.zhihu.com/api/v4/collections/123456/items?limit=20&offset=0"
    assert ZhihuFavoritesFetcher._to_refresh_page_url(url) == "https://www.zhihu.com/collection/123456"
