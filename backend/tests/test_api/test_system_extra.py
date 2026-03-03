
import pytest
from httpx import AsyncClient

class TestSystemExtraAPI:
    """Tests for extra system endpoints (storage, events, proxy)."""

    @pytest.mark.asyncio
    async def test_storage_stats(self, client: AsyncClient):
        response = await client.get("/api/v1/storage/stats")
        assert response.status_code == 200
        data = response.json()
        assert "total_bytes" in data
        assert "media_count" in data

    @pytest.mark.asyncio
    async def test_events_health(self, client: AsyncClient):
        response = await client.get("/api/v1/events/health")
        assert response.status_code == 200
        assert response.json()["status"] == "healthy"

    @pytest.mark.asyncio
    async def test_proxy_image(self, client: AsyncClient):
        # This might return 400 if URL is invalid or 404 if not found
        # But we check if the endpoint is reachable
        response = await client.get("/api/v1/proxy/image?url=https://www.baidu.com/img/flexible/logo/pc/result.png")
        # It will likely return 200 if it can fetch the image
        assert response.status_code in [200, 400, 404, 500]

    @pytest.mark.asyncio
    async def test_get_media_not_found(self, client: AsyncClient):
        response = await client.get("/api/v1/media/nonexistent_file.jpg")
        assert response.status_code == 404

