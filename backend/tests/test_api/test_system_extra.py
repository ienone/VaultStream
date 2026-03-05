
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
    async def test_proxy_image_success(self, client: AsyncClient):
        """Test proxy image returns 200 with valid external URL."""
        response = await client.get("/api/v1/proxy/image?url=https://www.baidu.com/img/flexible/logo/pc/result.png")
        assert response.status_code == 200
        assert response.headers.get("content-type") == "image/webp"

    @pytest.mark.asyncio
    async def test_proxy_image_rejects_non_http_scheme(self, client: AsyncClient):
        """Test proxy image blocks non-http/https schemes (SSRF)."""
        response = await client.get("/api/v1/proxy/image?url=file:///etc/passwd")
        assert response.status_code == 400
        assert "不允许访问" in response.json()["detail"]

    @pytest.mark.asyncio
    async def test_get_media_not_found(self, client: AsyncClient):
        response = await client.get("/api/v1/media/nonexistent_file.jpg")
        assert response.status_code == 404

