"""SSRF-aware helpers for server-side URL fetching."""

from __future__ import annotations

import asyncio
import ipaddress
import socket
from dataclasses import dataclass
from typing import Any, Mapping
from urllib.parse import urljoin, urlparse

import httpcore
import httpx


class UnsafeUrlError(ValueError):
    """Raised when a URL targets a disallowed network location."""


@dataclass(frozen=True)
class SafeFetchResult:
    url: str
    status_code: int
    headers: httpx.Headers
    content: bytes

    @property
    def text(self) -> str:
        encoding = "utf-8"
        content_type = self.headers.get("content-type", "")
        for part in content_type.split(";"):
            part = part.strip()
            if part.lower().startswith("charset="):
                encoding = part.split("=", 1)[1].strip() or encoding
                break
        return self.content.decode(encoding, errors="replace")


def _is_disallowed_ip(raw_ip: str) -> bool:
    addr = ipaddress.ip_address(raw_ip)

    # Fake-IP ranges are commonly used by local proxy stacks. They are not
    # routable private targets, and blocking them breaks otherwise safe proxy use.
    fake_ipv4 = addr.ipv4_mapped if isinstance(addr, ipaddress.IPv6Address) else addr
    if isinstance(fake_ipv4, ipaddress.IPv4Address) and fake_ipv4 in ipaddress.ip_network("198.18.0.0/15"):
        return False

    return (
        addr.is_private
        or addr.is_loopback
        or addr.is_link_local
        or addr.is_reserved
        or addr.is_multicast
        or addr.is_unspecified
    )


async def validate_safe_url(url: str) -> None:
    parsed = urlparse((url or "").strip())
    if parsed.scheme not in ("http", "https"):
        raise UnsafeUrlError("Only http and https URLs are allowed")
    if not parsed.hostname:
        raise UnsafeUrlError("URL hostname is required")

    try:
        infos = await asyncio.get_running_loop().getaddrinfo(parsed.hostname, parsed.port)
    except socket.gaierror as e:
        raise UnsafeUrlError("URL hostname cannot be resolved") from e

    for info in infos:
        if _is_disallowed_ip(info[4][0]):
            raise UnsafeUrlError("URL resolves to a disallowed address")


async def _resolve_safe_host(host: str, port: int | None = None) -> str:
    try:
        infos = await asyncio.get_running_loop().getaddrinfo(host, port)
    except socket.gaierror as e:
        raise UnsafeUrlError("URL hostname cannot be resolved") from e

    candidates: list[str] = []
    for info in infos:
        ip = info[4][0]
        if _is_disallowed_ip(ip):
            raise UnsafeUrlError(f"URL resolves to a disallowed address: {ip}")
        if ip not in candidates:
            candidates.append(ip)

    if not candidates:
        raise UnsafeUrlError("URL hostname cannot be resolved")
    return candidates[0]


async def is_safe_url(url: str) -> bool:
    try:
        await validate_safe_url(url)
        return True
    except (UnsafeUrlError, ValueError):
        return False


class SafeAsyncNetworkBackend(httpcore.AsyncNetworkBackend):
    """Validate direct destinations while allowing the configured proxy hop."""

    def __init__(
        self,
        backend: httpcore.AsyncNetworkBackend | None = None,
        *,
        proxy_address: tuple[str, int] | None = None,
    ) -> None:
        if backend is None:
            from httpcore._backends.auto import AutoBackend

            self._backend = AutoBackend()
        else:
            self._backend = backend
        self._proxy_address = proxy_address

    async def connect_tcp(
        self,
        host: str,
        port: int,
        timeout: float | None = None,
        local_address: str | None = None,
        socket_options: Any = None,
    ) -> httpcore.AsyncNetworkStream:
        # With HTTP/SOCKS proxies this TCP destination is the configured gateway,
        # not the fetched URL. Callers still validate targets and every redirect.
        resolved_ip = (
            host
            if (host, port) == self._proxy_address
            else await _resolve_safe_host(host, port)
        )
        return await self._backend.connect_tcp(
            resolved_ip,
            port,
            timeout=timeout,
            local_address=local_address,
            socket_options=socket_options,
        )

    async def sleep(self, seconds: float) -> None:
        await self._backend.sleep(seconds)


def create_safe_async_transport(**kwargs: Any) -> httpx.AsyncHTTPTransport:
    """Pin direct connections to safe DNS results; trust only the configured proxy."""

    transport = httpx.AsyncHTTPTransport(**kwargs)
    pool = getattr(transport, "_pool", None)
    if hasattr(pool, "_network_backend"):
        proxy = kwargs.get("proxy")
        proxy_address = None
        if proxy is not None:
            proxy_url = (proxy if isinstance(proxy, httpx.Proxy) else httpx.Proxy(proxy)).url
            proxy_address = (
                proxy_url.host,
                proxy_url.port
                or {"https": 443, "socks5": 1080, "socks5h": 1080}.get(
                    proxy_url.scheme, 80
                ),
            )
        # httpx does not expose httpcore's network_backend in 0.28.x. This
        # private assignment only replaces the TCP backend, not URL validation.
        pool._network_backend = SafeAsyncNetworkBackend(proxy_address=proxy_address)
    return transport


def _content_type_allowed(content_type: str, allowed_prefixes: tuple[str, ...] | None) -> bool:
    if not allowed_prefixes:
        return True
    normalized = (content_type or "").lower()
    return any(normalized.startswith(prefix.lower()) for prefix in allowed_prefixes)


async def safe_client_get(
    client: httpx.AsyncClient,
    url: str,
    *,
    headers: Mapping[str, str] | None = None,
    cookies: Mapping[str, str] | None = None,
    max_redirects: int = 5,
    max_bytes: int | None = None,
    allowed_content_type_prefixes: tuple[str, ...] | None = None,
) -> SafeFetchResult:
    """GET a URL with SSRF checks before the initial request and redirects."""

    current_url = url
    for _ in range(max_redirects + 1):
        await validate_safe_url(current_url)
        async with client.stream(
            "GET",
            current_url,
            headers=headers,
            cookies=cookies,
            follow_redirects=False,
        ) as resp:
            if 300 <= resp.status_code < 400:
                location = resp.headers.get("location")
                if not location:
                    raise httpx.HTTPStatusError(
                        "Redirect response missing Location",
                        request=resp.request,
                        response=resp,
                    )
                current_url = urljoin(current_url, location)
                continue

            content_type = resp.headers.get("content-type", "")
            if not _content_type_allowed(content_type, allowed_content_type_prefixes):
                raise UnsafeUrlError(f"Response content type is not allowed: {content_type}")

            chunks: list[bytes] = []
            total = 0
            async for chunk in resp.aiter_bytes():
                total += len(chunk)
                if max_bytes is not None and total > max_bytes:
                    raise httpx.HTTPStatusError(
                        "Response body exceeds configured size limit",
                        request=resp.request,
                        response=resp,
                    )
                chunks.append(chunk)

            return SafeFetchResult(
                url=str(resp.url),
                status_code=resp.status_code,
                headers=resp.headers,
                content=b"".join(chunks),
            )

    raise UnsafeUrlError("URL redirects too many times")
