import pytest
from httpx import AsyncClient


class TestDiscoverySourcesAPI:
    @pytest.mark.asyncio
    async def test_create_source_rejects_unimplemented_kind(self, client: AsyncClient):
        response = await client.post(
            "/api/v1/discovery/sources",
            json={
                "kind": "github",
                "name": "GitHub roadmap source",
                "enabled": True,
                "config": {"url": "https://github.com/trending"},
                "sync_interval_minutes": 60,
            },
        )

        assert response.status_code == 400
        data = response.json()
        assert data["error_code"] == "source_kind_not_supported"
        assert data["supported_kinds"] == ["rss", "telegram_channel"]

    @pytest.mark.asyncio
    async def test_create_source_allows_supported_rss_kind(self, client: AsyncClient):
        response = await client.post(
            "/api/v1/discovery/sources",
            json={
                "kind": "rss",
                "name": "API test RSS source",
                "enabled": True,
                "config": {"url": "https://example.com/feed.xml"},
                "sync_interval_minutes": 60,
            },
        )

        assert response.status_code == 201
        data = response.json()
        assert data["kind"] == "rss"
        assert data["name"] == "API test RSS source"
        assert data["config"]["url"] == "https://example.com/feed.xml"
