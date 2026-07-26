import socket
from unittest.mock import AsyncMock

import httpx
import pytest

from app.core.safe_fetch import (
    SafeAsyncNetworkBackend,
    UnsafeUrlError,
    _is_disallowed_ip,
    safe_client_get,
    validate_safe_url,
)


def _fake_getaddrinfo(host: str, port=None, *args, **kwargs):
    ip = {
        "example.test": "93.184.216.34",
        "private.test": "10.0.0.2",
        "127.0.0.1": "127.0.0.1",
    }[host]
    return [(socket.AF_INET, socket.SOCK_STREAM, 0, "", (ip, port or 80))]


def test_validate_safe_url_blocks_private_address(monkeypatch):
    monkeypatch.setattr(socket, "getaddrinfo", _fake_getaddrinfo)

    with pytest.raises(UnsafeUrlError):
        validate_safe_url("http://private.test/data")


def test_ipv4_mapped_fake_ip_is_allowed():
    assert _is_disallowed_ip("198.18.0.1") is False
    assert _is_disallowed_ip("::ffff:198.18.0.1") is False
    assert _is_disallowed_ip("::ffff:127.0.0.1") is True


@pytest.mark.asyncio
async def test_safe_network_backend_connects_to_validated_ip(monkeypatch):
    monkeypatch.setattr(socket, "getaddrinfo", _fake_getaddrinfo)
    inner_backend = AsyncMock()
    inner_backend.connect_tcp = AsyncMock(return_value="stream")
    backend = SafeAsyncNetworkBackend(inner_backend)

    result = await backend.connect_tcp("example.test", 443, timeout=1.0)

    assert result == "stream"
    inner_backend.connect_tcp.assert_awaited_once_with(
        "93.184.216.34",
        443,
        timeout=1.0,
        local_address=None,
        socket_options=None,
    )


@pytest.mark.asyncio
async def test_safe_network_backend_blocks_private_resolution(monkeypatch):
    monkeypatch.setattr(socket, "getaddrinfo", _fake_getaddrinfo)
    inner_backend = AsyncMock()
    inner_backend.connect_tcp = AsyncMock()
    backend = SafeAsyncNetworkBackend(inner_backend)

    with pytest.raises(UnsafeUrlError):
        await backend.connect_tcp("private.test", 80)

    inner_backend.connect_tcp.assert_not_awaited()


@pytest.mark.asyncio
async def test_safe_client_get_blocks_redirect_to_private_address(monkeypatch):
    monkeypatch.setattr(socket, "getaddrinfo", _fake_getaddrinfo)
    requested: list[str] = []

    def handler(request: httpx.Request) -> httpx.Response:
        requested.append(str(request.url))
        return httpx.Response(302, headers={"location": "http://127.0.0.1/private"})

    async with httpx.AsyncClient(transport=httpx.MockTransport(handler)) as client:
        with pytest.raises(UnsafeUrlError):
            await safe_client_get(client, "https://example.test/image.png")

    assert requested == ["https://example.test/image.png"]


@pytest.mark.asyncio
async def test_safe_client_get_rejects_unexpected_content_type(monkeypatch):
    monkeypatch.setattr(socket, "getaddrinfo", _fake_getaddrinfo)

    def handler(request: httpx.Request) -> httpx.Response:
        return httpx.Response(200, headers={"content-type": "text/html"}, content=b"<html></html>")

    async with httpx.AsyncClient(transport=httpx.MockTransport(handler)) as client:
        with pytest.raises(UnsafeUrlError):
            await safe_client_get(
                client,
                "https://example.test/image.png",
                allowed_content_type_prefixes=("image/",),
            )


@pytest.mark.asyncio
async def test_safe_client_get_rejects_oversized_body(monkeypatch):
    monkeypatch.setattr(socket, "getaddrinfo", _fake_getaddrinfo)

    def handler(request: httpx.Request) -> httpx.Response:
        return httpx.Response(200, headers={"content-type": "image/png"}, content=b"abcdef")

    async with httpx.AsyncClient(transport=httpx.MockTransport(handler)) as client:
        with pytest.raises(httpx.HTTPStatusError):
            await safe_client_get(
                client,
                "https://example.test/image.png",
                max_bytes=3,
                allowed_content_type_prefixes=("image/",),
            )
