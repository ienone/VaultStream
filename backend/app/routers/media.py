"""
功能描述：媒体资源代理 API
包含：本地媒体代理、远程图片代理
调用方式：本地媒体需要 API Token；远程图片代理不要求 Token，但会限制来源和目标 URL。
"""
import asyncio
import mimetypes
import os
import threading
import urllib.parse
import weakref
from pathlib import Path
from urllib.parse import urljoin, urlparse

import httpx
from fastapi import APIRouter, Depends, HTTPException, Query, Request
from fastapi.responses import FileResponse, StreamingResponse
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.logging import logger
from app.core.config import settings
from app.core.api_errors import build_error_payload
from app.core.dependencies import require_api_token
from app.core.database import get_db
from app.core.safe_fetch import create_safe_async_transport, is_safe_url
from app.adapters.storage import get_storage_backend, LocalStorageBackend
from app.models.media import MediaArchiveStatus, MediaVariant, MediaVariantStatus
from app.schemas.media import (
    MediaAssetManifest,
    MediaBookmarkCreate,
    MediaBookmarkDeleteResponse,
    MediaBookmarkItem,
    MediaBookmarkListResponse,
    MediaBookmarkUpdate,
    MediaLocalFailureCode,
    MediaLocalFailureReport,
    MediaLocalFailureResult,
    MediaPurpose,
)
from app.services.media_bookmark_service import MediaBookmarkError, MediaBookmarkService
from app.services.config_service import ConfigService
from app.services.media_access import MediaSignatureError, verify_media_signature
from app.services.media_manifest import (
    build_media_manifest,
    get_media_asset,
    resolve_media_base_url,
)

router = APIRouter()

_MAX_PROXY_IMAGE_BYTES = 10 * 1024 * 1024
_MAX_PROXY_REDIRECTS = 5
_MAX_PROXY_IMAGE_PIXELS = 40_000_000
_MAX_PROXY_CACHE_BYTES = 512 * 1024 * 1024
_PROXY_CONNECT_RETRIES = 2
_PROXY_WORK_CONCURRENCY = 4
_PROXY_CACHE_QUOTA_CHECK_EVERY = 16

_proxy_coordination_guard = threading.Lock()
_proxy_locks_by_loop: weakref.WeakKeyDictionary = weakref.WeakKeyDictionary()
_proxy_semaphores_by_loop: weakref.WeakKeyDictionary = weakref.WeakKeyDictionary()
_proxy_cache_writes_since_quota_check = _PROXY_CACHE_QUOTA_CHECK_EVERY - 1


def _proxy_request_lock(url_hash: str) -> asyncio.Lock:
    """Return a loop-local, weakly held lock for one upstream URL."""
    loop = asyncio.get_running_loop()
    with _proxy_coordination_guard:
        locks = _proxy_locks_by_loop.get(loop)
        if locks is None:
            locks = weakref.WeakValueDictionary()
            _proxy_locks_by_loop[loop] = locks
        lock = locks.get(url_hash)
        if lock is None:
            lock = asyncio.Lock()
            locks[url_hash] = lock
        return lock


def _proxy_work_semaphore() -> asyncio.Semaphore:
    """Bound concurrent cold downloads and image decoding per event loop."""
    loop = asyncio.get_running_loop()
    with _proxy_coordination_guard:
        semaphore = _proxy_semaphores_by_loop.get(loop)
        if semaphore is None:
            semaphore = asyncio.Semaphore(_PROXY_WORK_CONCURRENCY)
            _proxy_semaphores_by_loop[loop] = semaphore
        return semaphore


def _should_enforce_proxy_cache_quota() -> bool:
    """Check once on first write, then once per bounded batch of writes."""
    global _proxy_cache_writes_since_quota_check
    with _proxy_coordination_guard:
        _proxy_cache_writes_since_quota_check += 1
        if _proxy_cache_writes_since_quota_check < _PROXY_CACHE_QUOTA_CHECK_EVERY:
            return False
        _proxy_cache_writes_since_quota_check = 0
        return True


def _media_error(message: str, code: str) -> dict[str, object]:
    return build_error_payload(message=message, code=code)


def _raise_bookmark_error(error: MediaBookmarkError) -> None:
    raise HTTPException(
        status_code=error.status_code,
        detail=_media_error(error.message, error.code),
    ) from error


def _resolve_local_media_path(storage: LocalStorageBackend, key: str) -> Path:
    if ".." in key:
        raise HTTPException(status_code=400, detail="Invalid media key")

    raw_key = Path(key)
    if raw_key.is_absolute() or key.startswith(("/", "\\")):
        raise HTTPException(status_code=400, detail="Invalid media key")

    storage_root = Path(storage.root_dir).resolve()
    file_path = Path(storage._full_path(key)).resolve()
    try:
        file_path.relative_to(storage_root)
    except ValueError as e:
        raise HTTPException(status_code=403, detail="Access denied") from e
    return file_path


def _is_safe_url(url: str) -> bool:
    """检查 URL 是否安全（防止 SSRF 访问内网）"""
    return is_safe_url(url)


def _allowed_proxy_origins() -> set[str]:
    origins = {
        origin.strip().rstrip("/")
        for origin in settings.cors_allowed_origins.split(",")
        if origin.strip() and origin.strip() != "*"
    }
    if settings.base_url:
        origins.add(settings.base_url.strip().rstrip("/"))
    return origins


def _origin_from_referer(referer: str | None) -> str | None:
    if not referer:
        return None
    parsed = urlparse(referer)
    if parsed.scheme not in ("http", "https") or not parsed.netloc:
        return None
    return f"{parsed.scheme}://{parsed.netloc}".rstrip("/")


def _is_allowed_proxy_request_origin(request: Request) -> bool:
    """In production, reject browser proxy requests from untrusted origins."""
    if settings.app_env != "prod":
        return True

    origin = request.headers.get("origin")
    if not origin:
        origin = _origin_from_referer(request.headers.get("referer"))

    if not origin:
        return True

    return origin.rstrip("/") in _allowed_proxy_origins()


async def _download_remote_image(
    client: httpx.AsyncClient,
    url: str,
    headers: dict[str, str],
) -> tuple[bytes, str, str]:
    """下载远程图片，并在每次重定向前重新执行 SSRF 与大小校验。"""
    current_url = url
    for _ in range(_MAX_PROXY_REDIRECTS + 1):
        if not _is_safe_url(current_url):
            raise HTTPException(
                status_code=400,
                detail="目标 URL 不允许访问（内网地址或无效协议）",
            )

        async with client.stream(
            "GET",
            current_url,
            headers=headers,
            follow_redirects=False,
        ) as resp:
            if 300 <= resp.status_code < 400:
                location = resp.headers.get("location")
                if not location:
                    raise HTTPException(
                        status_code=502,
                        detail="上游重定向缺少 Location",
                    )
                current_url = urljoin(current_url, location)
                continue

            if resp.status_code != 200:
                logger.error(f"图片代理上游错误 {resp.status_code}: {current_url}")
                raise HTTPException(
                    status_code=502,
                    detail=f"上游服务器返回错误: {resp.status_code}",
                )

            content_type = resp.headers.get("content-type", "image/jpeg")
            if not content_type.lower().startswith("image/"):
                raise HTTPException(status_code=415, detail="上游资源不是图片")

            content_length = resp.headers.get("content-length")
            if content_length:
                try:
                    if int(content_length) > _MAX_PROXY_IMAGE_BYTES:
                        raise HTTPException(status_code=413, detail="图片过大")
                except ValueError:
                    pass

            chunks: list[bytes] = []
            total = 0
            async for chunk in resp.aiter_bytes():
                total += len(chunk)
                if total > _MAX_PROXY_IMAGE_BYTES:
                    raise HTTPException(status_code=413, detail="图片过大")
                chunks.append(chunk)
            return b"".join(chunks), content_type, current_url

    raise HTTPException(status_code=400, detail="图片重定向次数过多")


def _validate_proxy_image_pixels(data: bytes) -> tuple[int | None, int | None]:
    """Validate decoded image dimensions before transcoding or caching."""
    try:
        from PIL import Image  # type: ignore
    except Exception as e:  # pragma: no cover
        raise HTTPException(status_code=500, detail="图片解码组件不可用") from e

    from io import BytesIO

    try:
        with Image.open(BytesIO(data)) as image:
            width, height = image.size
            pixels = int(width or 0) * int(height or 0)
            if pixels <= 0:
                raise HTTPException(status_code=415, detail="图片尺寸无效")
            if pixels > _MAX_PROXY_IMAGE_PIXELS:
                raise HTTPException(status_code=413, detail="图片像素尺寸过大")
            image.verify()
            return int(width), int(height)
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=415, detail="上游资源不是有效图片") from e


def _proxy_cache_root(storage: LocalStorageBackend) -> Path:
    root = Path(storage._full_path("proxy_cache")).resolve()
    storage_root = Path(storage.root_dir).resolve()
    try:
        root.relative_to(storage_root)
    except ValueError as e:  # pragma: no cover
        raise HTTPException(status_code=500, detail="图片缓存路径配置异常") from e
    root.mkdir(parents=True, exist_ok=True)
    return root


async def _enforce_proxy_cache_quota(storage: LocalStorageBackend) -> None:
    """Keep proxy image cache under a local quota using oldest-file eviction."""
    cache_root = _proxy_cache_root(storage)

    def trim_cache() -> None:
        files: list[tuple[float, int, Path]] = []
        total = 0
        for path in cache_root.rglob("*"):
            if not path.is_file():
                continue
            try:
                stat = path.stat()
            except OSError:
                continue
            total += stat.st_size
            files.append((stat.st_mtime, stat.st_size, path))

        if total <= _MAX_PROXY_CACHE_BYTES:
            return

        for _mtime, size, path in sorted(files, key=lambda item: item[0]):
            try:
                path.unlink()
                total -= size
            except OSError as e:
                logger.warning(f"图片代理缓存清理失败: {path}, {e}")
            if total <= _MAX_PROXY_CACHE_BYTES:
                break

        for directory in sorted(
            (p for p in cache_root.rglob("*") if p.is_dir()),
            key=lambda p: len(p.parts),
            reverse=True,
        ):
            try:
                directory.rmdir()
            except OSError:
                pass

    await asyncio.to_thread(trim_cache)


def _proxy_cache_media_type(path: str) -> str | None:
    """Infer the media type encoded by a cache filename, never assume WebP."""
    media_type, _ = mimetypes.guess_type(path)
    if media_type and media_type.startswith("image/"):
        return media_type
    return None


async def _find_proxy_cache_file(
    storage: LocalStorageBackend,
    cache_namespace: str,
    url_hash: str,
) -> tuple[str, str] | None:
    """Find a readable cached image without blocking the event loop."""
    cache_dir = storage._full_path(cache_namespace)

    def find_file() -> tuple[str, str] | None:
        if not os.path.exists(cache_dir):
            return None
        for filename in sorted(os.listdir(cache_dir)):
            if not filename.startswith(url_hash):
                continue
            cached_file = os.path.join(cache_dir, filename)
            media_type = _proxy_cache_media_type(cached_file)
            if media_type and os.path.isfile(cached_file):
                return cached_file, media_type
        return None

    return await asyncio.to_thread(find_file)


async def _persist_proxy_cache(
    storage: LocalStorageBackend,
    *,
    key: str,
    data: bytes,
    content_type: str,
) -> str:
    """Persist opportunistic cache data while exposing the exact failure stage."""
    try:
        await storage.put_bytes(key=key, data=data, content_type=content_type)
    except Exception as exc:
        logger.error("图片代理缓存写入失败: key={}, error={}", key, exc)
        return "write-failed"

    if not _should_enforce_proxy_cache_quota():
        return "stored"

    try:
        await _enforce_proxy_cache_quota(storage)
    except Exception as exc:
        logger.error("图片代理缓存配额维护失败: key={}, error={}", key, exc)
        return "quota-failed"
    return "stored"


def _raw_proxy_cache_extension(content_type: str) -> str | None:
    normalized = content_type.split(";", 1)[0].strip().lower()
    return {
        "image/jpeg": "jpg",
        "image/png": "png",
        "image/gif": "gif",
        "image/webp": "webp",
        "image/avif": "avif",
        "image/bmp": "bmp",
        "image/tiff": "tif",
    }.get(normalized)


async def _proxy_cache_hit_response(
    storage: LocalStorageBackend,
    cache_namespace: str,
    url_hash: str,
    *,
    url: str,
) -> FileResponse | None:
    cached = await _find_proxy_cache_file(storage, cache_namespace, url_hash)
    if cached is None:
        return None
    cached_file, cached_media_type = cached
    logger.debug(f"图片代理缓存命中: {url} -> {cached_file}")
    return FileResponse(
        cached_file,
        media_type=cached_media_type,
        headers={
            "Cache-Control": "public, max-age=86400",
            "X-Cache-Status": "HIT",
            "X-Cache-Persist": "stored",
        },
    )


async def _fetch_proxy_image_response(
    *,
    url: str,
    storage: LocalStorageBackend,
    cache_namespace: str,
    url_hash: str,
) -> StreamingResponse:
    """Fetch, validate, transcode and opportunistically cache one cold image."""
    from app.media.processor import (
        _image_to_webp,
        _request_headers_for_url,
    )

    logger.info(f"图片代理缓存未命中，开始下载: {url}")
    headers = _request_headers_for_url(url)
    proxy = await ConfigService().get_http_proxy()

    try:
        transport_kwargs = {"retries": _PROXY_CONNECT_RETRIES}
        if proxy:
            transport_kwargs["proxy"] = proxy
        transport = create_safe_async_transport(**transport_kwargs)
        async with httpx.AsyncClient(
            transport=transport,
            timeout=httpx.Timeout(10.0, connect=5.0),
        ) as client:
            original_data, content_type, final_url = await _download_remote_image(
                client,
                url,
                headers,
            )
            await asyncio.to_thread(_validate_proxy_image_pixels, original_data)

            try:
                webp_data, width, height = await asyncio.to_thread(
                    _image_to_webp,
                    original_data,
                    quality=80,
                )
                if width is not None and height is not None:
                    if int(width) * int(height) > _MAX_PROXY_IMAGE_PIXELS:
                        raise HTTPException(status_code=413, detail="图片像素尺寸过大")

                cache_key = f"{cache_namespace}/{url_hash}.webp"
                persist_status = await _persist_proxy_cache(
                    storage,
                    key=cache_key,
                    data=webp_data,
                    content_type="image/webp",
                )

                logger.info(
                    f"图片代理已缓存: {final_url} -> {cache_key} "
                    f"[{len(original_data)//1024}KB原始 -> {len(webp_data)//1024}KB WebP, "
                    f"{width}x{height}]"
                )

                return StreamingResponse(
                    iter([webp_data]),
                    media_type="image/webp",
                    headers={
                        "Cache-Control": "public, max-age=86400",
                        "X-Cache-Status": "MISS",
                        "X-Cache-Persist": persist_status,
                        "X-Original-Size": str(len(original_data)),
                        "X-Compressed-Size": str(len(webp_data)),
                    },
                )
            except HTTPException:
                raise
            except Exception as transcode_error:
                logger.warning(f"图片转码失败，返回原图: {transcode_error}")

                ext = _raw_proxy_cache_extension(content_type)
                persist_status = "unsupported-mime"
                if ext:
                    cache_key = f"{cache_namespace}/{url_hash}.{ext}"
                    persist_status = await _persist_proxy_cache(
                        storage,
                        key=cache_key,
                        data=original_data,
                        content_type=content_type,
                    )

                return StreamingResponse(
                    iter([original_data]),
                    media_type=content_type,
                    headers={
                        "Cache-Control": "public, max-age=86400",
                        "X-Cache-Status": "MISS-RAW",
                        "X-Cache-Persist": persist_status,
                        "X-Proxy-Warning": "transcode-failed",
                    },
                )
    except HTTPException:
        raise
    except httpx.TimeoutException:
        logger.error(f"图片代理请求超时: {url}")
        raise HTTPException(status_code=504, detail="上游服务器响应超时")
    except httpx.RequestError as e:
        logger.error(f"图片代理网络错误: {url}, {e}")
        raise HTTPException(status_code=502, detail=f"网络请求失败: {str(e)}")
    except Exception as e:
        logger.error(f"图片代理未知错误: {url}, {e}", exc_info=True)
        raise HTTPException(status_code=500, detail="图片代理服务内部错误")


@router.get(
    "/contents/{content_id}/media-bookmarks",
    response_model=MediaBookmarkListResponse,
    dependencies=[Depends(require_api_token)],
)
async def list_media_bookmarks(
    content_id: int,
    media_asset_id: int = Query(..., ge=1),
    db: AsyncSession = Depends(get_db),
):
    try:
        return await MediaBookmarkService(db).list_bookmarks(
            content_id=content_id,
            media_asset_id=media_asset_id,
        )
    except MediaBookmarkError as error:
        _raise_bookmark_error(error)


@router.post(
    "/contents/{content_id}/media-bookmarks",
    response_model=MediaBookmarkItem,
    status_code=201,
    dependencies=[Depends(require_api_token)],
)
async def create_media_bookmark(
    content_id: int,
    request: MediaBookmarkCreate,
    db: AsyncSession = Depends(get_db),
):
    try:
        return await MediaBookmarkService(db).create_bookmark(
            content_id=content_id,
            request=request,
        )
    except MediaBookmarkError as error:
        _raise_bookmark_error(error)


@router.patch(
    "/contents/{content_id}/media-bookmarks/{bookmark_id}",
    response_model=MediaBookmarkItem,
    dependencies=[Depends(require_api_token)],
)
async def update_media_bookmark(
    content_id: int,
    bookmark_id: int,
    request: MediaBookmarkUpdate,
    db: AsyncSession = Depends(get_db),
):
    try:
        return await MediaBookmarkService(db).update_bookmark(
            content_id=content_id,
            bookmark_id=bookmark_id,
            request=request,
        )
    except MediaBookmarkError as error:
        _raise_bookmark_error(error)


@router.delete(
    "/contents/{content_id}/media-bookmarks/{bookmark_id}",
    response_model=MediaBookmarkDeleteResponse,
    dependencies=[Depends(require_api_token)],
)
async def delete_media_bookmark(
    content_id: int,
    bookmark_id: int,
    db: AsyncSession = Depends(get_db),
):
    try:
        return await MediaBookmarkService(db).delete_bookmark(
            content_id=content_id,
            bookmark_id=bookmark_id,
        )
    except MediaBookmarkError as error:
        _raise_bookmark_error(error)


@router.get(
    "/media/assets/{asset_id}/manifest",
    response_model=MediaAssetManifest,
    dependencies=[Depends(require_api_token)],
)
async def get_asset_manifest(
    asset_id: int,
    request: Request,
    purpose: MediaPurpose = Query(MediaPurpose.DETAIL),
    db: AsyncSession = Depends(get_db),
):
    """刷新一个资产的有序读取候选；该控制面请求需要 API Token。"""
    asset = await get_media_asset(db, asset_id)
    if asset is None:
        raise HTTPException(
            status_code=404,
            detail=_media_error("Media asset not found", "media_asset_not_found"),
        )
    base_url = resolve_media_base_url(str(request.base_url))
    return build_media_manifest(asset, purpose=purpose, base_url=base_url)


def _local_image_is_decodable(file_path: Path) -> bool:
    from PIL import Image  # type: ignore

    try:
        with Image.open(file_path) as image:
            image.verify()
        return True
    except Exception:
        return False


@router.post(
    "/media/assets/{asset_id}/failures",
    response_model=MediaLocalFailureResult,
    dependencies=[Depends(require_api_token)],
)
async def report_local_media_failure(
    asset_id: int,
    report: MediaLocalFailureReport,
    db: AsyncSession = Depends(get_db),
    storage: LocalStorageBackend = Depends(get_storage_backend),
):
    """Verify a local client failure before marking a variant repairable."""
    if not isinstance(storage, LocalStorageBackend):
        raise HTTPException(
            status_code=400,
            detail=_media_error("Unsupported storage backend", "unsupported_storage_backend"),
        )
    asset = await get_media_asset(db, asset_id)
    if asset is None:
        raise HTTPException(
            status_code=404,
            detail=_media_error("Media asset not found", "media_asset_not_found"),
        )
    variant = next(
        (item for item in asset.variants if item.id == report.variant_id),
        None,
    )
    if variant is None:
        raise HTTPException(
            status_code=404,
            detail=_media_error("Media variant not found", "media_variant_not_found"),
        )

    file_path = _resolve_local_media_path(storage, variant.storage_key)
    outcome = "verified_healthy"
    next_status: MediaVariantStatus | None = None
    if report.error_code == MediaLocalFailureCode.BLOB_MISSING:
        if not file_path.exists():
            next_status = MediaVariantStatus.MISSING
            outcome = "marked_missing"
    elif report.error_code == MediaLocalFailureCode.DECODE_FAILED:
        if not file_path.exists():
            next_status = MediaVariantStatus.MISSING
            outcome = "marked_missing"
        elif asset.media_type.value == "image" and not await asyncio.to_thread(
            _local_image_is_decodable,
            file_path,
        ):
            next_status = MediaVariantStatus.FAILED
            outcome = "marked_failed"
        elif asset.media_type.value != "image":
            outcome = "not_server_verifiable"

    if next_status is not None:
        variant.status = next_status
        has_other_ready_variant = any(
            item.id != variant.id and item.status == MediaVariantStatus.READY
            for item in asset.variants
        )
        if has_other_ready_variant:
            asset.archive_status = MediaArchiveStatus.PARTIAL
        elif next_status == MediaVariantStatus.MISSING:
            asset.archive_status = MediaArchiveStatus.MISSING
        else:
            asset.archive_status = MediaArchiveStatus.FAILED
        asset.repairable = True
        asset.last_error = f"{report.error_code.value}:variant:{variant.id}"
        await db.commit()

    return MediaLocalFailureResult(
        asset_id=asset.id,
        variant_id=variant.id,
        outcome=outcome,
        variant_status=variant.status,
        archive_status=asset.archive_status,
        repairable=asset.repairable,
    )


@router.get("/media/blobs/{key:path}")
async def get_signed_media_blob(
    key: str,
    variant_id: int = Query(..., ge=1),
    expires: int = Query(..., ge=1),
    signature: str = Query(..., min_length=64, max_length=64),
    db: AsyncSession = Depends(get_db),
    storage: LocalStorageBackend = Depends(get_storage_backend),
):
    """通过资源级签名读取本地媒体，不接收控制面 API Token。"""
    if not isinstance(storage, LocalStorageBackend):
        raise HTTPException(
            status_code=400,
            detail=_media_error("Unsupported storage backend", "unsupported_storage_backend"),
        )
    try:
        verify_media_signature(key, variant_id, expires, signature)
    except MediaSignatureError as exc:
        status_code = 410 if exc.code == "media_signature_expired" else 403
        message = "Media signature expired" if status_code == 410 else "Invalid media signature"
        raise HTTPException(
            status_code=status_code,
            detail=_media_error(message, exc.code),
        ) from exc

    variant = (
        await db.execute(select(MediaVariant).where(MediaVariant.id == variant_id))
    ).scalar_one_or_none()
    if (
        variant is None
        or variant.storage_key != key
        or variant.status != MediaVariantStatus.READY
    ):
        raise HTTPException(
            status_code=404,
            detail=_media_error("Media variant not found", "media_variant_not_found"),
        )

    file_path = _resolve_local_media_path(storage, key)
    if not file_path.exists():
        raise HTTPException(
            status_code=404,
            detail=_media_error("Media blob is missing", "media_blob_missing"),
        )

    mime_type = variant.mime_type or mimetypes.guess_type(str(file_path))[0]
    return FileResponse(
        str(file_path),
        media_type=mime_type or "application/octet-stream",
        headers={
            "Cache-Control": "private, max-age=300",
            "ETag": f'"{variant.checksum or key}"',
        },
    )


@router.get("/media/{key:path}", dependencies=[Depends(require_api_token)])
async def proxy_media(
    key: str,
    size: str = Query("original", pattern=r"^(original|thumb)$"),
    storage: LocalStorageBackend = Depends(get_storage_backend),
):
    """
    媒体代理 API
    支持 Range 请求以加速播放视频预览。
    
    Query Parameters:
        size: original (默认) | thumb (缩略图，由前端控制尺寸)
        注：当前版本 size 参数传递给前端，由前端 CachedNetworkImage 控制加载尺寸
    """
    if not isinstance(storage, LocalStorageBackend):
        raise HTTPException(status_code=400, detail="Only local storage proxy is supported")

    # 路径穿越防护
    file_path = _resolve_local_media_path(storage, key)
    # 确保解析后的路径仍在存储根目录内
    if not file_path.exists():
        raise HTTPException(status_code=404, detail="Media not found")
        
    mime_type, _ = mimetypes.guess_type(str(file_path))
    if not mime_type:
        mime_type = "application/octet-stream"
    
    # 添加缓存头优化性能
    return FileResponse(
        str(file_path),
        media_type=mime_type,
        headers={
            "Cache-Control": "public, max-age=31536000, immutable",  # 1年缓存
            "ETag": f'"{key}"',
        }
    )

@router.get("/proxy/image")
async def proxy_image(
    request: Request,
    url: str = Query(..., description="要代理的图片 URL"),
    storage: LocalStorageBackend = Depends(get_storage_backend),
):
    """通用图片代理，用于解决跨域、Referer 校验或网络瓶颈
    
    优化机制：
    1. 首次访问：下载并转码为WebP存储到本地
    2. 后续访问：直接返回本地缓存（速度提升100倍+）
    """
    import hashlib

    # 还原 URL 编码以确保 hash 一致性 (前端通过 query 参数传过来往往会被 encode)
    url = urllib.parse.unquote(url)

    # SSRF 防护：禁止访问内网地址
    if not _is_safe_url(url):
        raise HTTPException(status_code=400, detail="目标 URL 不允许访问（内网地址或无效协议）")
    if not _is_allowed_proxy_request_origin(request):
        raise HTTPException(status_code=403, detail="图片代理来源不允许")

    # 1. 生成缓存key（使用URL的MD5作为命名空间）
    url_hash = hashlib.md5(url.encode(), usedforsecurity=False).hexdigest()
    cache_namespace = f"proxy_cache/{url_hash[:2]}/{url_hash[2:4]}"

    # 2. 检查是否已缓存（查找任意扩展名的文件）
    cached_response = await _proxy_cache_hit_response(
        storage,
        cache_namespace,
        url_hash,
        url=url,
    )
    if cached_response is not None:
        return cached_response

    # 同一 URL 的冷请求串行化；后继请求在锁内复查缓存，避免重复下载和解码。
    async with _proxy_request_lock(url_hash):
        cached_response = await _proxy_cache_hit_response(
            storage,
            cache_namespace,
            url_hash,
            url=url,
        )
        if cached_response is not None:
            return cached_response

        # 不同 URL 之间仍并行，但冷下载和 Pillow 工作有全局上限。
        async with _proxy_work_semaphore():
            return await _fetch_proxy_image_response(
                url=url,
                storage=storage,
                cache_namespace=cache_namespace,
                url_hash=url_hash,
            )
