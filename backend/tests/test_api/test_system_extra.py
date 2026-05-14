
import pytest
from httpx import AsyncClient
from fastapi import HTTPException

from app.routers.media import (
    _MAX_PROXY_IMAGE_PIXELS,
    _is_allowed_proxy_request_origin,
    _validate_proxy_image_pixels,
)
from app.routers import media


class _RequestStub:
    def __init__(self, headers):
        self.headers = headers

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


def test_proxy_image_pixel_guard_rejects_oversized_header(monkeypatch):
    class HugeImage:
        size = (_MAX_PROXY_IMAGE_PIXELS + 1, 1)

        def __enter__(self):
            return self

        def __exit__(self, exc_type, exc, tb):
            return False

        def verify(self):
            return None

    monkeypatch.setattr("PIL.Image.open", lambda _stream: HugeImage())

    with pytest.raises(HTTPException) as exc_info:
        _validate_proxy_image_pixels(b"fake-image")

    assert exc_info.value.status_code == 413


def test_proxy_image_pixel_guard_accepts_valid_header(monkeypatch):
    class ValidImage:
        size = (640, 480)

        def __enter__(self):
            return self

        def __exit__(self, exc_type, exc, tb):
            return False

        def verify(self):
            return None

    monkeypatch.setattr("PIL.Image.open", lambda _stream: ValidImage())

    assert _validate_proxy_image_pixels(b"fake-image") == (640, 480)


def test_proxy_image_origin_guard_rejects_untrusted_prod_origin(monkeypatch):
    monkeypatch.setattr(media.settings, "app_env", "prod")
    monkeypatch.setattr(media.settings, "cors_allowed_origins", "https://vault.example.com")
    monkeypatch.setattr(media.settings, "base_url", "https://vault.example.com")

    request = _RequestStub({"origin": "https://evil.example.com"})

    assert _is_allowed_proxy_request_origin(request) is False


def test_proxy_image_origin_guard_accepts_trusted_prod_referer(monkeypatch):
    monkeypatch.setattr(media.settings, "app_env", "prod")
    monkeypatch.setattr(media.settings, "cors_allowed_origins", "https://vault.example.com")
    monkeypatch.setattr(media.settings, "base_url", None)

    request = _RequestStub({"referer": "https://vault.example.com/content/1"})

    assert _is_allowed_proxy_request_origin(request) is True
