
import pytest
from httpx import ASGITransport, AsyncClient
from pydantic import SecretStr
from unittest.mock import AsyncMock, patch

from app.core.config import settings
from app.main import app
from app.services.browser_auth_service import AuthSessionStatus

class TestBrowserAuthAPI:
    """Tests for Browser Auth API endpoints with mocked service."""

    @pytest.mark.asyncio
    async def test_start_session(self, client: AsyncClient):
        with patch("app.routers.browser_auth.browser_auth_service.start_auth_session", new_callable=AsyncMock) as mock_start:
            mock_start.return_value = AuthSessionStatus(
                session_id="test-session-123",
                platform="bilibili",
                status="waiting_scan",
                qrcode_b64="fake-qrcode"
            )
            
            # Note: The router might check if platform is supported.
            # Looking at browser_auth_service, it supports xiaohongshu, zhihu, weibo.
            response = await client.post("/api/v1/browser-auth/session/xiaohongshu")
            assert response.status_code == 200
            data = response.json()
            assert data["session_id"] == "test-session-123"
            assert data["status"] == "waiting_scan"

    @pytest.mark.asyncio
    async def test_get_session_status(self, client: AsyncClient):
        with patch("app.routers.browser_auth.browser_auth_service.get_session_status", new_callable=AsyncMock) as mock_status:
            mock_status.return_value = AuthSessionStatus(
                session_id="test-session-123",
                platform="xiaohongshu",
                status="success",
                message="Logged in"
            )
            
            response = await client.get("/api/v1/browser-auth/session/test-session-123/status")
            assert response.status_code == 200
            assert response.json()["status"] == "success"

    @pytest.mark.asyncio
    async def test_get_session_qrcode(self, client: AsyncClient):
        with patch("app.routers.browser_auth.browser_auth_service.get_session_qrcode", new_callable=AsyncMock) as mock_qr:
            mock_qr.return_value = "fake-qrcode-data"
            
            response = await client.get("/api/v1/browser-auth/session/test-session-123/qrcode")
            assert response.status_code == 200
            # The router might return a Response(content=...) or a JSON depending on implementation.
            # Checking browser_auth.py... it returns FileResponse or similar?
            # Actually let's check browser_auth.py again.
            
    @pytest.mark.asyncio
    async def test_check_platform(self, client: AsyncClient):
        with patch("app.routers.browser_auth.browser_auth_service.check_platform_status", new_callable=AsyncMock) as mock_check:
            mock_check.return_value = True
            
            response = await client.post("/api/v1/browser-auth/xiaohongshu/check")
            assert response.status_code == 200
            assert response.json()["is_valid"] is True

    @pytest.mark.asyncio
    async def test_logout_platform(self, client: AsyncClient):
        with patch("app.routers.browser_auth.browser_auth_service.logout_platform", new_callable=AsyncMock) as mock_logout:
            response = await client.post("/api/v1/browser-auth/xiaohongshu/logout")
            assert response.status_code == 200
            mock_logout.assert_called_once_with("xiaohongshu")

    @pytest.mark.asyncio
    async def test_delete_platform(self, client: AsyncClient):
        with patch("app.routers.browser_auth.browser_auth_service.logout_platform", new_callable=AsyncMock) as mock_logout:
            response = await client.delete("/api/v1/browser-auth/xiaohongshu")
            assert response.status_code == 200
            mock_logout.assert_called_once_with("xiaohongshu")

    @pytest.mark.asyncio
    async def test_cancel_auth_session(self, client: AsyncClient):
        with patch(
            "app.routers.browser_auth.browser_auth_service.cancel_session",
            new_callable=AsyncMock,
        ) as mock_cancel:
            response = await client.delete(
                "/api/v1/browser-auth/session/test-session-123"
            )
            assert response.status_code == 200
            mock_cancel.assert_awaited_once_with("test-session-123")

    @pytest.mark.asyncio
    @pytest.mark.parametrize(
        ("method", "path"),
        [
            ("POST", "/api/v1/browser-auth/session/xiaohongshu"),
            ("GET", "/api/v1/browser-auth/session/test-session-123/status"),
            ("GET", "/api/v1/browser-auth/session/test-session-123/qrcode"),
            ("DELETE", "/api/v1/browser-auth/session/test-session-123"),
            ("POST", "/api/v1/browser-auth/xiaohongshu/check"),
            ("POST", "/api/v1/browser-auth/xiaohongshu/logout"),
            ("DELETE", "/api/v1/browser-auth/xiaohongshu"),
            ("POST", "/api/v1/browser-auth/zhihu/refresh-zse"),
        ],
    )
    async def test_browser_auth_requires_api_token(self, monkeypatch, method: str, path: str):
        monkeypatch.setattr(settings, "api_token", SecretStr("required-token"))
        transport = ASGITransport(app=app)
        async with AsyncClient(transport=transport, base_url="http://test") as unauthenticated:
            response = await unauthenticated.request(method, path)

        assert response.status_code == 401
        body = response.json()
        assert body["detail"] == "Invalid or missing API Token"
        assert body["error_code"] == "invalid_api_token"
