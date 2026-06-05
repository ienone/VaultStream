"""
Media API Tests - Proxy and media serving
"""
import pytest
from fastapi import HTTPException
from httpx import AsyncClient

from app.adapters.storage import LocalStorageBackend
from app.routers.media import _resolve_local_media_path


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


def test_local_media_path_rejects_sibling_prefix(tmp_path):
    storage_root = tmp_path / "storage"
    sibling = tmp_path / "storage_evil"
    storage_root.mkdir()
    sibling.mkdir()
    escaped_file = sibling / "owned.jpg"
    escaped_file.write_bytes(b"not really an image")

    storage = LocalStorageBackend(str(storage_root))
    with pytest.raises(HTTPException) as exc_info:
        _resolve_local_media_path(storage, str(escaped_file))

    assert exc_info.value.status_code == 400


def test_local_media_path_allows_file_under_storage_root(tmp_path):
    storage_root = tmp_path / "storage"
    stored_file = storage_root / "ab" / "cd" / "image.jpg"
    stored_file.parent.mkdir(parents=True)
    stored_file.write_bytes(b"ok")

    storage = LocalStorageBackend(str(storage_root))

    assert _resolve_local_media_path(storage, "ab/cd/image.jpg") == stored_file.resolve()
