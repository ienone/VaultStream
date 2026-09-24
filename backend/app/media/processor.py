"""归档媒体：下载、压缩、原子存储，成功后发布本地引用。"""
from __future__ import annotations

import asyncio
import hashlib
from io import BytesIO
from typing import Any
from urllib.parse import quote, urlsplit, urlunsplit

import httpx
from PIL import Image, ImageOps

from app.adapters.storage import LocalStorageBackend
from app.core.logging import logger
from app.core.safe_fetch import SafeFetchResult, safe_client_get
from app.media.color import dominant_color
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


def _image_to_webp(data: bytes, quality: int = 80) -> tuple[bytes, int, int]:
    """代理和归档共用 Pillow 编码器；已编码的 WebP 直接复用。"""
    with Image.open(BytesIO(data)) as image:
        _validate_image(image)
        image.load()
        if image.format == "WEBP":
            return data, image.width, image.height
        encoded = _encode_webp(image, quality)
    with Image.open(BytesIO(encoded)) as result:
        return encoded, result.width, result.height


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
    if not await storage.exists(key=key):
        await storage.put_bytes(key=key, data=data, content_type="image/webp")
    with Image.open(BytesIO(data)) as image:
        width, height = image.size
    return {"thumb_key": key, "thumb_url": storage.get_url(key=key),
            "thumb_sha256": digest, "thumb_size": len(data),
            "thumb_width": width, "thumb_height": height}


def _prepare_image(data: bytes, quality: int) -> tuple[bytes, bytes | None, dict[str, Any]]:
    with Image.open(BytesIO(data)) as image:
        _validate_image(image)
        image.load()
        original_format = image.format
        encoded = data if original_format == "WEBP" else _encode_webp(image, quality)
        # 只保存一个主文件。转换没有节省空间时使用已验证的源图。
        source_extensions = {"JPEG": "jpg", "PNG": "png", "GIF": "gif", "WEBP": "webp", "AVIF": "avif"}
        use_source = original_format in source_extensions and len(data) <= len(encoded)
        main = data if use_source else encoded
        mime = Image.MIME[original_format] if use_source else "image/webp"
        ext = source_extensions[original_format] if use_source else "webp"
    with Image.open(BytesIO(main)) as result:
        result.load()
        metadata = {"width": result.width, "height": result.height,
                    "content_type": mime, "extension": ext,
                    "dominant_color": dominant_color(result)}
        thumb = _thumbnail(result) if max(result.size) > 300 else None
    return main, thumb, metadata


async def _download(client: httpx.AsyncClient, url: str, *, kind: str, max_bytes: int):
    request_url = _build_request_url(url)
    for attempt in range(3):
        try:
            response = await safe_client_get(
                client, request_url, headers=_request_headers_for_url(url),
                max_bytes=max_bytes, allowed_content_type_prefixes=(f"{kind}/",),
            )
            if response.status_code >= 400:
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
                if not response.content:
                    raise ValueError("Empty media response")
                return response
        except httpx.TransportError:
            if attempt == 2:
                raise
        await asyncio.sleep(0.8 * (attempt + 1))
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


async def _store_download(
    response: SafeFetchResult, *, kind: str, quality: int,
    storage: LocalStorageBackend, namespace: str,
) -> tuple[dict[str, Any], str | None]:
    """将一次下载转换为已落盘的结果，不修改归档和正文。"""
    color = None
    if kind == "image":
        data, thumbnail, info = await asyncio.to_thread(_prepare_image, response.content, quality)
        extension = info.pop("extension")
        color = info.pop("dominant_color")
    else:
        data = response.content
        mime = response.headers.get("content-type", "video/mp4").split(";")[0].strip()
        extension = {"video/mp4": "mp4", "video/webm": "webm", "video/ogg": "ogg",
                     "video/quicktime": "mov", "video/x-matroska": "mkv"}.get(mime, "mp4")
        info = {"content_type": mime}
    digest = hashlib.sha256(data).hexdigest()
    key = _content_addressed_key(namespace, digest, extension)
    if not await storage.exists(key=key):
        await storage.put_bytes(key=key, data=data, content_type=info["content_type"])
    result = {f"stored_{name}": value for name, value in info.items()}
    result.update(stored_key=key, stored_url=storage.get_url(key=key),
                  stored_sha256=digest, stored_size=len(data))
    if kind == "image":
        await _save_thumbnail(result, thumbnail, storage, namespace)
    return result, color


async def _store_archive_media(
    *, archive: dict[str, Any], storage: LocalStorageBackend, namespace: str,
    kind: str, quality: int, timeout_seconds: float, limit: int | None, max_bytes: int,
) -> dict[str, Any]:
    from app.media.references import rewrite_media_urls

    groups: dict[str, list[dict[str, Any]]] = {}
    for item in archive.get(f"{kind}s") or []:
        if isinstance(item, dict) and isinstance(item.get("url"), str) and item["url"].strip():
            groups.setdefault(item["url"].strip(), []).append(item)
    if not groups:
        return archive

    rewrites: dict[str, str] = {}
    attempts = 0
    proxy = await ConfigService().get_http_proxy()
    async with httpx.AsyncClient(proxy=proxy, timeout=timeout_seconds) as client:
        for url, items in groups.items():
            result, color = {}, None
            try:
                # 同一来源的任一条目有可用主文件即可复用，不受条目顺序影响。
                for item in items:
                    if item.get("stored_key") and await storage.exists(key=item["stored_key"]):
                        result = {name: value for name, value in item.items()
                                  if name.startswith(("stored_", "thumb_"))}
                        break
                if result:
                    if kind == "image":
                        await _restore_thumbnail(result, storage, namespace)
                elif limit is None or attempts < limit:
                    attempts += 1
                    response = await _download(client, url, kind=kind, max_bytes=max_bytes)
                    result, color = await _store_download(
                        response, kind=kind, quality=quality, storage=storage, namespace=namespace,
                    )
            except Exception as error:
                logger.warning("Archive {} failed ({}): {}", kind, type(error).__name__, str(error))

            local_url = f"local://{result['stored_key']}" if result else url
            if result:
                rewrites[url] = local_url
            for item in items:
                item["url"] = url
                previous_key = item.get("stored_key")
                if previous_key:
                    rewrites[f"local://{previous_key}"] = local_url
                for name in list(item):
                    if name.startswith(("stored_", "thumb_")):
                        item.pop(name)
                item.update(result)
            if color and not archive.get("dominant_color") and any(
                not item.get("is_avatar") and item.get("type") != "avatar" for item in items
            ):
                archive["dominant_color"] = color
    if isinstance(archive.get("markdown"), str):
        archive["markdown"] = rewrite_media_urls(archive["markdown"], rewrites)
    return archive


async def store_archive_images(
    *, archive: dict[str, Any], storage: LocalStorageBackend, namespace: str,
    quality: int = 80, timeout_seconds: float = 30.0, max_images: int | None = None,
) -> dict[str, Any]:
    return await _store_archive_media(
        archive=archive, storage=storage, namespace=namespace, kind="image", quality=quality,
        timeout_seconds=timeout_seconds, limit=max_images, max_bytes=_MAX_ARCHIVE_IMAGE_BYTES,
    )


async def store_archive_videos(
    *, archive: dict[str, Any], storage: LocalStorageBackend, namespace: str,
    timeout_seconds: float = 120.0, max_videos: int | None = None, max_bytes: int | None = None,
) -> dict[str, Any]:
    return await _store_archive_media(
        archive=archive, storage=storage, namespace=namespace, kind="video", quality=80,
        timeout_seconds=timeout_seconds, limit=max_videos,
        max_bytes=max_bytes if max_bytes is not None else _MAX_ARCHIVE_VIDEO_BYTES,
    )
