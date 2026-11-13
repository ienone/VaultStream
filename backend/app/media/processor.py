"""归档媒体：下载、压缩、原子存储，成功后发布本地引用。"""
from __future__ import annotations

import asyncio
import hashlib
from pathlib import Path
from io import BytesIO
from typing import Any
from urllib.parse import quote, urlsplit, urlunsplit

import httpx
from PIL import Image, ImageOps

from app.adapters.storage import LocalStorageBackend
from app.core.logging import logger
from app.core.safe_fetch import safe_client_get
from app.media.color import _color_from_bytes
from app.media.proxy_cache import find_proxy_cache_file, proxy_cache_location
from app.services.config_service import ConfigService

_MAX_ARCHIVE_IMAGE_BYTES = 20 * 1024 * 1024
_MAX_ARCHIVE_VIDEO_BYTES = 200 * 1024 * 1024
_MAX_IMAGE_PIXELS = 40_000_000


def _request_headers_for_url(url: str) -> dict[str, str]:
    """根据URL生成请求头（某些CDN如B站需要浏览器样式的请求头）"""
    headers: dict[str, str] = {
        "User-Agent": (
            "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 "
            "(KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
        ),
        "Accept": "image/avif,image/webp,image/apng,image/*,*/*;q=0.8",
    }

    lowered = (url or "").lower()
    if "hdslb.com/" in lowered:
        headers["Referer"] = "https://www.bilibili.com/"
        headers["Origin"] = "https://www.bilibili.com"
    elif "sinaimg.cn" in lowered or "weibocdn.com" in lowered:
        headers["Referer"] = "https://weibo.com/"
    elif "zhimg.com" in lowered or "zhihu.com" in lowered:
        headers["Referer"] = "https://www.zhihu.com/"
        headers["Origin"] = "https://www.zhihu.com"

    return headers


def _build_request_url(raw_url: str) -> str:
    parts = urlsplit(raw_url.strip())
    return urlunsplit((
        parts.scheme, parts.netloc,
        quote(parts.path, safe="/%:@!$&'()*+,;=-._~"),
        quote(parts.query, safe="/?:@!$&'()*+,;=-._~%="),
        parts.fragment,
    ))


def _content_addressed_key(namespace: str, sha256_hex: str, ext: str) -> str:
    """生成基于内容寻址的存储key"""
    ns = (namespace or "").strip("/")
    prefix = f"{ns}/" if ns else ""
    return f"{prefix}blobs/sha256/{sha256_hex[:2]}/{sha256_hex[2:4]}/{sha256_hex}.{ext.lstrip('.')}"


def _encode_webp(image: Image.Image, quality: int) -> bytes:
    options: dict[str, Any] = {"quality": quality, "method": 4}
    if getattr(image, "n_frames", 1) > 1:
        durations = []
        for index in range(image.n_frames):
            image.seek(index)
            durations.append(image.info.get("duration", 100))
        image.seek(0)
        options.update(save_all=True, duration=durations, loop=image.info.get("loop", 0))
    else:
        image = ImageOps.exif_transpose(image)
    out = BytesIO()
    image.save(out, format="WEBP", **options)
    return out.getvalue()


def _validate_image(image: Image.Image) -> None:
    if not 0 < image.width * image.height <= _MAX_IMAGE_PIXELS:
        raise ValueError("Image exceeds archive pixel limit")


def _thumbnail(image: Image.Image) -> bytes:
    image = ImageOps.exif_transpose(image)
    image.thumbnail((300, 300), Image.Resampling.LANCZOS)
    out = BytesIO()
    image.save(out, format="WEBP", quality=70, method=4)
    return out.getvalue()


def _thumbnail_from_bytes(data: bytes) -> bytes | None:
    with Image.open(BytesIO(data)) as image:
        _validate_image(image)
        return _thumbnail(image) if max(image.size) > 300 else None


async def _store_thumbnail(storage: LocalStorageBackend, namespace: str, data: bytes) -> dict[str, Any]:
    digest = hashlib.sha256(data).hexdigest()
    key = _content_addressed_key(namespace, digest, "webp")
    await storage.put_bytes(key=key, data=data, content_type="image/webp")
    with Image.open(BytesIO(data)) as image:
        width, height = image.size
    return {"thumb_key": key, "thumb_url": storage.get_url(key=key),
            "thumb_sha256": digest, "thumb_size": len(data),
            "thumb_width": width, "thumb_height": height}


def _prepare_image(data: bytes, quality: int) -> tuple[bytes, dict[str, Any]]:
    with Image.open(BytesIO(data)) as image:
        _validate_image(image)
        image.load()
        fmt = image.format
        extensions = {"JPEG": "jpg", "PNG": "png", "GIF": "gif", "WEBP": "webp", "AVIF": "avif"}
        extension = extensions.get(fmt)
        if fmt != "WEBP":
            try:
                encoded = _encode_webp(image, quality)
            except (ValueError, OSError, RuntimeError):
                if not extension:
                    raise
            else:
                if not extension or len(encoded) < len(data):
                    data, fmt, extension = encoded, "WEBP", "webp"
        return data, {"width": image.width, "height": image.height,
                      "content_type": Image.MIME[fmt], "extension": extension}


async def _download(client: httpx.AsyncClient, url: str, *, kind: str, max_bytes: int):
    request_url = _build_request_url(url)
    source_refreshed = False
    attempt = 0
    while attempt < 3:
        try:
            # CDN errors may omit Content-Type; classify status before media MIME.
            response = await safe_client_get(
                client, request_url, headers=_request_headers_for_url(url),
                max_bytes=max_bytes,
            )
            if response.status_code >= 400:
                if response.status_code == 403 and kind == "image" and not source_refreshed:
                    from app.services.xiaohongshu_media_refresh import refresh_xiaohongshu_image_url

                    source_refreshed = True
                    refreshed = await refresh_xiaohongshu_image_url(url)
                    if refreshed:
                        request_url = _build_request_url(refreshed)
                        continue
                error = httpx.HTTPStatusError(
                    f"Media upstream status {response.status_code}",
                    request=httpx.Request("GET", request_url),
                    response=httpx.Response(response.status_code),
                )
                if response.status_code != 429 and response.status_code < 500:
                    raise error
                if attempt == 2:
                    raise error
            else:
                if kind != "image" and not response.headers.get("content-type", "").lower().startswith(f"{kind}/"):
                    raise ValueError(f"Media response is not {kind}")
                if not response.content:
                    raise ValueError("Empty media response")
                return response
        except httpx.TransportError:
            if attempt == 2:
                raise
        await asyncio.sleep(0.8 * (attempt + 1))
        attempt += 1
    raise AssertionError("unreachable")


async def _save_thumbnail(
    result: dict[str, Any], thumbnail: bytes | None,
    storage: LocalStorageBackend, namespace: str,
) -> None:
    """缩略图失败不撤销已经成功保存的主文件。"""
    try:
        if thumbnail:
            result.update(await _store_thumbnail(storage, namespace, thumbnail))
        else:
            result.update(thumb_key=result["stored_key"], thumb_url=result.get("stored_url"))
    except OSError as error:
        logger.warning("Thumbnail storage failed: {}", type(error).__name__)


async def _restore_thumbnail(
    result: dict[str, Any], storage: LocalStorageBackend, namespace: str,
) -> None:
    key = result.get("thumb_key")
    if key and await storage.exists(key=key):
        return
    for name in list(result):
        if name.startswith("thumb_"):
            result.pop(name)
    try:
        data = await storage.get_bytes(result["stored_key"])
        thumbnail = await asyncio.to_thread(_thumbnail_from_bytes, data)
        await _save_thumbnail(result, thumbnail, storage, namespace)
    except (OSError, ValueError) as error:
        logger.warning("Thumbnail repair failed: {}", type(error).__name__)


async def store_media_bytes(
    data: bytes, *, content_type: str, kind: str, quality: int,
    storage: LocalStorageBackend, namespace: str,
) -> tuple[dict[str, Any], str | None]:
    """HTTP 和原生平台下载共用同一转码、缩略图和内容寻址存储。"""
    color = None
    if kind == "image":
        data, info = await asyncio.to_thread(_prepare_image, data, quality)
        extension = info.pop("extension")
    else:
        mime = content_type.split(";")[0].strip()
        extension = {"video/mp4": "mp4", "video/webm": "webm", "video/ogg": "ogg",
                     "video/quicktime": "mov", "video/x-matroska": "mkv"}.get(mime, "mp4")
        info = {"content_type": mime}
    digest = hashlib.sha256(data).hexdigest()
    key = _content_addressed_key(namespace, digest, extension)
    await storage.put_bytes(key=key, data=data, content_type=info["content_type"])
    result = {f"stored_{name}": value for name, value in info.items()}
    result.update(stored_key=key, stored_url=storage.get_url(key=key),
                  stored_sha256=digest, stored_size=len(data))
    if kind == "image":
        try:
            thumbnail = await asyncio.to_thread(_thumbnail_from_bytes, data)
            await _save_thumbnail(result, thumbnail, storage, namespace)
        except (OSError, ValueError, RuntimeError) as error:
            logger.warning("Thumbnail unavailable: {}", error)
        try:
            color = await asyncio.to_thread(_color_from_bytes, data)
        except (OSError, ValueError, RuntimeError) as error:
            logger.warning("Image color unavailable: {}", error)
    return result, color


async def archive_media_file(url: str, *, kind: str, main_key: str | None, storage: LocalStorageBackend,
                             quality: int, video_max_bytes: int | None) -> tuple[dict, str | None]:
    """Return the stored versions of one asset, reusing a surviving main file or proxy copy."""
    if main_key and await storage.exists(key=main_key):
        info = {"stored_key": main_key}
        if kind == "image":
            await _restore_thumbnail(info, storage, "vaultstream")
        return info, None
    if kind == "image":
        cached = await find_proxy_cache_file(storage, *proxy_cache_location(url))
        if cached:
            try:
                data = await asyncio.to_thread(Path(cached[0]).read_bytes)
                return await store_media_bytes(data, content_type=cached[1], kind=kind,
                    quality=quality, storage=storage, namespace="vaultstream")
            except (OSError, ValueError):
                pass
    if not url:
        raise ValueError("Missing archive source")
    limit = _MAX_ARCHIVE_IMAGE_BYTES if kind == "image" else video_max_bytes or _MAX_ARCHIVE_VIDEO_BYTES
    proxy = await ConfigService().get_http_proxy()
    async with httpx.AsyncClient(proxy=proxy, timeout=30 if kind == "image" else 120) as client:
        response = await _download(client, url, kind=kind, max_bytes=limit)
    return await store_media_bytes(response.content, content_type=response.headers.get("content-type", ""),
        kind=kind, quality=quality, storage=storage, namespace="vaultstream")
