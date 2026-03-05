"""
Media API Tests - Proxy and media serving
"""
import pytest
from httpx import AsyncClient


class TestMediaAPI:
    """Test suite for media endpoints"""
    
    @pytest.mark.asyncio
    async def test_stored_media_not_found(self, client: AsyncClient):
        """Test that accessing a non-existent stored media file returns 404."""
        response = await client.get("/api/v1/media/nonexistent_file_12345.jpg")
        assert response.status_code == 404
        assert response.json()["detail"] == "Media not found"

    @pytest.mark.asyncio
    async def test_stored_media_path_traversal_blocked(self, client: AsyncClient):
        """Test that path traversal attempts are rejected with 400."""
        response = await client.get("/api/v1/media/foo/..%2F..%2Fetc%2Fpasswd")
        assert response.status_code == 400
        assert response.json()["detail"] == "Invalid media key"
