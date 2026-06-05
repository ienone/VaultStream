import pytest
import httpx
from unittest.mock import patch, MagicMock, AsyncMock
from app.core.safe_fetch import SafeFetchResult
from app.media.processor import (
    _request_headers_for_url,
    _sha256_bytes,
    _content_addressed_key,
    _build_request_url,
)


def _safe_fetch_result(
    content: bytes = b"\x89PNG\r\n\x1a\n" + b"\x00" * 128,
    content_type: str = "image/png",
    url: str = "https://ok.example.com/good.jpg",
) -> SafeFetchResult:
    return SafeFetchResult(
        url=url,
        status_code=200,
        headers=httpx.Headers({"content-type": content_type}),
        content=content,
    )

@pytest.mark.parametrize("url, expected_header", [
    ("https://i0.hdslb.com/bfs/image.jpg", "https://www.bilibili.com/"),
    ("https://wx1.sinaimg.cn/large/abc.png", "https://weibo.com/"),
    ("https://pic1.zhimg.com/v2-xyz.webp", "https://www.zhihu.com/"),
    ("https://example.com/other.gif", None), # No special referer
])
def test_request_headers_for_url(url, expected_header):
    """Test specialized headers for various CDNs."""
    headers = _request_headers_for_url(url)
    if expected_header:
        assert headers["Referer"] == expected_header
    assert "User-Agent" in headers

def test_sha256_bytes():
    """Test internal SHA256 helper with correct expected hash."""
    data = b"hello vaultstream"
    import hashlib
    real_hash = hashlib.sha256(data).hexdigest()
    assert _sha256_bytes(data) == real_hash
    # The actual hash for b"hello vaultstream" is:
    # 083f636b478a36d1f71351a767c14b7463c4e271d40a1a9e221e409cd34085c4
    assert real_hash.startswith("083f636b")

def test_content_addressed_key():
    """Test generating storage keys based on hash."""
    sha = "083f636b478a36d1f71351a767c14b7463c4e271d40a1a9e221e409cd34085c4"
    key = _content_addressed_key("test_ns", sha, "webp")
    assert key == "test_ns/blobs/sha256/08/3f/083f636b478a36d1f71351a767c14b7463c4e271d40a1a9e221e409cd34085c4.webp"


def test_build_request_url_preserves_xhs_path_bang_suffix():
    source = (
        "http://sns-webpic-qc.xhscdn.com/202603192128/abc/"
        "1040g00831tqhc2ut7u005o9stqhgk6j9ofo0p2o!nd_dft_wlteh_webp_3"
    )
    normalized = _build_request_url(source)
    assert normalized == source
    assert "%21" not in normalized

@pytest.mark.asyncio
async def test_store_archive_images_skips_on_download_failure():
    """Test that store_archive_images_as_webp skips images that fail to download."""
    from app.media.processor import store_archive_images_as_webp

    archive = {
        "images": [
            {"url": "https://fail.example.com/bad.jpg"},
            {"url": "https://ok.example.com/good.jpg"},
        ]
    }

    mock_storage = MagicMock()
    mock_storage.put_bytes = AsyncMock()
    mock_storage.get_url = MagicMock(return_value="http://local/good.webp")

    with patch("httpx.AsyncClient") as mock_client_cls:
        mock_client = AsyncMock()
        mock_client_cls.return_value.__aenter__ = AsyncMock(return_value=mock_client)
        mock_client_cls.return_value.__aexit__ = AsyncMock(return_value=False)

        safe_fetch_mock = AsyncMock(side_effect=[
            Exception("Connection refused"),
            Exception("Connection refused"),
            Exception("Connection refused"),
            _safe_fetch_result(),
        ])
        with patch("app.media.processor.safe_client_get", safe_fetch_mock):
            with patch("app.media.processor._image_to_webp", return_value=(b"webp_data", 100, 100)):
                with patch("app.services.settings_service.get_setting_value", AsyncMock(return_value=None)):
                    result = await store_archive_images_as_webp(
                        archive=archive, storage=mock_storage, namespace="test"
                    )

    # First image skipped, second stored
    assert len(result.get("stored_images", [])) == 1
    assert result["stored_images"][0]["orig_url"] == "https://ok.example.com/good.jpg"


@pytest.mark.asyncio
async def test_store_archive_images_skips_unsafe_private_url():
    """Archive media downloading must not fetch internal/private URLs."""
    from app.media.processor import store_archive_images_as_webp

    archive = {"images": [{"url": "http://127.0.0.1/private.jpg"}]}
    mock_storage = MagicMock()
    mock_storage.put_bytes = AsyncMock()

    with patch("httpx.AsyncClient") as mock_client_cls:
        mock_client = AsyncMock()
        mock_client_cls.return_value.__aenter__ = AsyncMock(return_value=mock_client)
        mock_client_cls.return_value.__aexit__ = AsyncMock(return_value=False)
        safe_fetch_mock = AsyncMock(side_effect=Exception("unsafe url"))

        with patch("app.media.processor.safe_client_get", safe_fetch_mock):
            with patch("app.services.settings_service.get_setting_value", AsyncMock(return_value=None)):
                result = await store_archive_images_as_webp(
                    archive=archive, storage=mock_storage, namespace="test"
                )

    assert "stored_images" not in result
    mock_storage.put_bytes.assert_not_awaited()


@pytest.mark.asyncio
async def test_store_archive_images_rewrites_markdown_with_local_url():
    """Stored images should rewrite archive markdown URLs to local:// keys."""
    from app.media.processor import store_archive_images_as_webp

    source_url = "https://pic1.zhimg.com/v2-abc123_r.jpg"
    archive = {
        "images": [{"url": source_url}],
        "markdown": f"![img]({source_url})",
    }

    mock_storage = MagicMock()
    mock_storage.put_bytes = AsyncMock()
    mock_storage.get_url = MagicMock(return_value="http://local/ignored.webp")

    with patch("httpx.AsyncClient") as mock_client_cls:
        mock_client = AsyncMock()
        mock_client_cls.return_value.__aenter__ = AsyncMock(return_value=mock_client)
        mock_client_cls.return_value.__aexit__ = AsyncMock(return_value=False)

        with patch("app.media.processor.safe_client_get", AsyncMock(return_value=_safe_fetch_result(url=source_url))):
            with patch("app.media.processor._image_to_webp", return_value=(b"webp_data", 100, 100)):
                with patch("app.services.settings_service.get_setting_value", AsyncMock(return_value=None)):
                    result = await store_archive_images_as_webp(
                        archive=archive, storage=mock_storage, namespace="test"
                    )

    stored = result.get("stored_images", [])
    assert len(stored) == 1
    key = stored[0]["key"]
    assert key
    assert result["markdown"] == f"![img](local://{key})"


@pytest.mark.asyncio
async def test_store_archive_images_rewrites_markdown_from_existing_stored_key():
    """Already processed images should still rewrite markdown using existing stored_key."""
    from app.media.processor import store_archive_images_as_webp

    source_url = "https://pic1.zhimg.com/v2-existing_r.jpg"
    archive = {
        "images": [
            {
                "url": source_url,
                "stored_key": "vaultstream/blobs/sha256/aa/bb/existing.webp",
                "stored_url": "http://localhost:8000/media/vaultstream/blobs/sha256/aa/bb/existing.webp",
            }
        ],
        "markdown": f"![img]({source_url})",
    }

    mock_storage = MagicMock()
    mock_storage.put_bytes = AsyncMock()
    mock_storage.get_url = MagicMock()

    with patch("httpx.AsyncClient") as mock_client_cls:
        mock_client = AsyncMock()
        mock_client_cls.return_value.__aenter__ = AsyncMock(return_value=mock_client)
        mock_client_cls.return_value.__aexit__ = AsyncMock(return_value=False)

        safe_fetch_mock = AsyncMock()
        with patch("app.services.settings_service.get_setting_value", AsyncMock(return_value=None)):
            with patch("app.media.processor.safe_client_get", safe_fetch_mock):
                result = await store_archive_images_as_webp(
                    archive=archive, storage=mock_storage, namespace="test"
                )

    safe_fetch_mock.assert_not_awaited()
    assert result["markdown"] == "![img](local://vaultstream/blobs/sha256/aa/bb/existing.webp)"
    assert result["stored_images"][0]["key"] == "vaultstream/blobs/sha256/aa/bb/existing.webp"


@pytest.mark.asyncio
async def test_store_archive_images_keeps_bang_in_request_url():
    from app.media.processor import store_archive_images_as_webp

    source_url = (
        "http://sns-webpic-qc.xhscdn.com/202603192128/abc/"
        "1040g00831tqhc2ut7u005o9stqhgk6j9ofo0p2o!nd_dft_wlteh_webp_3"
    )
    archive = {"images": [{"url": source_url}]}

    mock_storage = MagicMock()
    mock_storage.put_bytes = AsyncMock()
    mock_storage.get_url = MagicMock(return_value="http://local/img.webp")

    with patch("httpx.AsyncClient") as mock_client_cls:
        mock_client = AsyncMock()
        mock_client_cls.return_value.__aenter__ = AsyncMock(return_value=mock_client)
        mock_client_cls.return_value.__aexit__ = AsyncMock(return_value=False)

        safe_fetch_mock = AsyncMock(return_value=_safe_fetch_result(url=source_url))
        with patch("app.media.processor.safe_client_get", safe_fetch_mock):
            with patch("app.media.processor._image_to_webp", return_value=(b"webp_data", 100, 100)):
                with patch("app.services.settings_service.get_setting_value", AsyncMock(return_value=None)):
                    await store_archive_images_as_webp(
                        archive=archive, storage=mock_storage, namespace="test"
                    )

    request_url = safe_fetch_mock.await_args.args[1]
    assert request_url.endswith("!nd_dft_wlteh_webp_3")
    assert "%21" not in request_url

def test_image_to_webp_ffmpeg_mocked():
    """Test ffmpeg bridge returns None on non-zero returncode."""
    from app.media.processor import _image_to_webp_ffmpeg
    import subprocess

    with patch("subprocess.run") as mock_run:
        mock_run.return_value = MagicMock(returncode=1, stderr=b"error")
        result = _image_to_webp_ffmpeg(b"fake_image_data")
        assert result is None
        mock_run.assert_called_once()
