from __future__ import annotations

import pytest
from pydantic import SecretStr

from app.services.config_service import ConfigService


class _MemoryConfigService(ConfigService):
    def __init__(self, values: dict[str, object]):
        super().__init__(cache={})
        self.values = values

    async def get_value(self, key: str, default=None):
        return self.values.get(key, default)

    async def get_value_fresh(self, key: str, default=None):
        return self.values.get(key, default)


def test_parse_favorites_sync_platforms_accepts_json_and_csv():
    assert ConfigService.parse_favorites_sync_platforms('["Zhihu", "twitter"]') == [
        "zhihu",
        "twitter",
    ]
    assert ConfigService.parse_favorites_sync_platforms("zhihu, twitter") == [
        "zhihu",
        "twitter",
    ]


@pytest.mark.asyncio
async def test_get_favorites_sync_config_filters_and_normalizes_values():
    service = _MemoryConfigService(
        {
            "favorites_sync_platforms": ["zhihu", "unknown", "twitter"],
            "favorites_sync_interval_minutes": "-1",
            "favorites_sync_max_items": "0",
            "favorites_sync_duplicate_strategy": "invalid",
            "favorites_sync_scope_strategy": "invalid",
            "favorites_sync_first_sync_strategy": "invalid",
            "favorites_sync_unfavorite_strategy": "invalid",
            "favorites_sync_last_sync_at": "2026-06-06T00:00:00Z",
        }
    )

    config = await service.get_favorites_sync_config(
        default_interval_minutes=360,
        default_max_items=50,
        default_duplicate_strategy="merge",
        supported_platforms=["zhihu", "twitter"],
        allowed_duplicate_strategies={"merge", "skip"},
    )

    assert config.enabled_platforms == ["zhihu", "twitter"]
    assert config.interval_minutes == 360
    assert config.max_items == 50
    assert config.duplicate_strategy == "merge"
    assert config.scope_strategy == "all_favorites"
    assert config.first_sync_strategy == "latest_page"
    assert config.unfavorite_strategy == "keep_local"
    assert config.last_sync_at == "2026-06-06T00:00:00Z"


@pytest.mark.asyncio
async def test_get_favorites_sync_config_accepts_product_policy_values():
    service = _MemoryConfigService(
        {
            "favorites_sync_platforms": ["zhihu"],
            "favorites_sync_duplicate_strategy": "skip",
            "favorites_sync_scope_strategy": "collections_api_placeholder",
            "favorites_sync_first_sync_strategy": "full_backfill_placeholder",
            "favorites_sync_unfavorite_strategy": "mark_archived_placeholder",
        }
    )

    config = await service.get_favorites_sync_config(
        default_interval_minutes=360,
        default_max_items=50,
        default_duplicate_strategy="merge",
        supported_platforms=["zhihu"],
        allowed_duplicate_strategies={"merge", "skip"},
    )

    assert config.duplicate_strategy == "skip"
    assert config.scope_strategy == "collections_api_placeholder"
    assert config.first_sync_strategy == "full_backfill_placeholder"
    assert config.unfavorite_strategy == "mark_archived_placeholder"


@pytest.mark.asyncio
async def test_get_favorites_sync_platform_state_normalizes_rate_and_cursor():
    service = _MemoryConfigService(
        {
            "favorites_sync_rate_zhihu": "bad",
            "favorites_sync_cursor_zhihu": 123,
            "favorites_sync_last_result_zhihu": {"status": "success"},
        }
    )

    state = await service.get_favorites_sync_platform_state(
        "zhihu",
        default_rate_per_minute=5.0,
    )

    assert state.platform == "zhihu"
    assert state.rate_per_minute == 5.0
    assert state.cursor is None
    assert state.last_result == {"status": "success"}


@pytest.mark.asyncio
async def test_get_http_proxy_normalizes_empty_and_socks_scheme():
    assert await _MemoryConfigService({"http_proxy": ""}).get_http_proxy() is None
    assert await _MemoryConfigService(
        {"http_proxy": " socks://127.0.0.1:1080 "}
    ).get_http_proxy(normalize_socks_scheme=True) == "socks5://127.0.0.1:1080"


@pytest.mark.asyncio
async def test_get_archive_media_config_normalizes_values():
    service = _MemoryConfigService(
        {
            "enable_archive_media_processing": "true",
            "enable_archive_image_processing": "false",
            "enable_archive_video_processing": "true",
            "archive_image_webp_quality": "180",
            "archive_image_max_count": "0",
            "archive_video_max_count": "4",
            "archive_video_max_bytes": "1048576",
        }
    )

    config = await service.get_archive_media_config()

    assert config.enabled is True
    assert config.images_enabled is False
    assert config.videos_enabled is True
    assert config.image_webp_quality == 100
    assert config.image_max_count is None
    assert config.video_max_count == 4
    assert config.video_max_bytes == 1048576


@pytest.mark.asyncio
async def test_get_platform_cookie_string_reads_setting_secret():
    service = _MemoryConfigService({"zhihu_cookie": SecretStr("z_c0=abc")})

    assert await service.get_platform_cookie_string("zhihu") == "z_c0=abc"
    assert await service.get_platform_cookie_string("") is None
