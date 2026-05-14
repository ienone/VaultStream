import socket

import httpx
import pytest
from fastapi import HTTPException

from app.routers import media


def test_is_safe_url_blocks_private_ip_even_when_debug(monkeypatch):
    monkeypatch.setattr(media.settings, "debug", True)
    monkeypatch.setattr(
        media.socket,
        "getaddrinfo",
        lambda host, _port: [(socket.AF_INET, socket.SOCK_STREAM, 0, "", ("127.0.0.1", 0))],
    )

    assert media._is_safe_url("http://example.test/image.png") is False


@pytest.mark.asyncio
async def test_download_remote_image_blocks_redirect_to_private_host(monkeypatch):
    def is_safe_url(url: str) -> bool:
        return not url.startswith("http://127.0.0.1")

    monkeypatch.setattr(media, "_is_safe_url", is_safe_url)

    def handler(request: httpx.Request) -> httpx.Response:
        assert str(request.url) == "https://example.test/image.png"
        return httpx.Response(302, headers={"location": "http://127.0.0.1/private.png"})

    async with httpx.AsyncClient(transport=httpx.MockTransport(handler)) as client:
        with pytest.raises(HTTPException) as exc_info:
            await media._download_remote_image(client, "https://example.test/image.png", {})

    assert exc_info.value.status_code == 400


@pytest.mark.asyncio
async def test_download_remote_image_rejects_large_content_length(monkeypatch):
    monkeypatch.setattr(media, "_is_safe_url", lambda url: True)

    def handler(request: httpx.Request) -> httpx.Response:
        return httpx.Response(
            200,
            headers={
                "content-type": "image/png",
                "content-length": str(media._MAX_PROXY_IMAGE_BYTES + 1),
            },
        )

    async with httpx.AsyncClient(transport=httpx.MockTransport(handler)) as client:
        with pytest.raises(HTTPException) as exc_info:
            await media._download_remote_image(client, "https://example.test/image.png", {})

    assert exc_info.value.status_code == 413
