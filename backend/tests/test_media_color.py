from unittest.mock import AsyncMock, patch

import httpx
import pytest

from app.core.safe_fetch import SafeFetchResult
from app.media import color


def test_try_read_local_media_blocks_path_traversal(tmp_path, monkeypatch):
    storage_root = tmp_path / "storage"
    storage_root.mkdir()
    secret = tmp_path / "secret.jpg"
    secret.write_bytes(b"secret")
    monkeypatch.setattr(color.settings, "storage_local_root", str(storage_root))

    assert color._try_read_local_media("/media/../secret.jpg") is None


@pytest.mark.asyncio
async def test_extract_cover_color_uses_safe_fetch_for_remote_url():
    fetch_result = SafeFetchResult(
        url="https://example.test/image.png",
        status_code=200,
        headers=httpx.Headers({"content-type": "image/png"}),
        content=b"image-bytes",
    )

    with patch("app.media.color._try_read_local_media", return_value=None):
        with patch("app.media.color.safe_client_get", AsyncMock(return_value=fetch_result)) as mock_fetch:
            with patch("app.media.color._get_dominant_color", return_value="#010203"):
                result = await color.extract_cover_color("https://example.test/image.png")

    assert result == "#010203"
    assert mock_fetch.await_args.args[1] == "https://example.test/image.png"
    assert mock_fetch.await_args.kwargs["allowed_content_type_prefixes"] == ("image/",)
