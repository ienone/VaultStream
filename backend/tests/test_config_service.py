from __future__ import annotations

import pytest

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
    assert config.last_sync_at == "2026-06-06T00:00:00Z"


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
