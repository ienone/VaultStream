"""
功能描述：媒体资源代理 API
包含：本地媒体代理、远程图片代理
调用方式：无需 API Token (方便前端直接加载)，但部分接口可能限制来源
"""
import os
import mimetypes
import urllib.parse
from pathlib import Path
from urllib.parse import urljoin, urlparse

import httpx
from fastapi import APIRouter, Depends, HTTPException, Query, Request
from fastapi.responses import FileResponse, StreamingResponse

from app.core.logging import logger
from app.core.config import settings
from app.core.dependencies import require_api_token
from app.core.safe_fetch import create_safe_async_transport, is_safe_url
from app.adapters.storage import get_storage_backend, LocalStorageBackend
from app.services.config_service import ConfigService

router = APIRouter()

_MAX_PROXY_IMAGE_BYTES = 10 * 1024 * 1024
_MAX_PROXY_REDIRECTS = 5
_MAX_PROXY_IMAGE_PIXELS = 40_000_000
_MAX_PROXY_CACHE_BYTES = 512 * 1024 * 1024


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

    import asyncio

    await asyncio.to_thread(trim_cache)


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
    from app.media.processor import (
        _image_to_webp,
        _request_headers_for_url,
    )
    
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
    cache_dir = storage._full_path(cache_namespace)
    if os.path.exists(cache_dir):
        # 查找以url_hash开头的文件
        cache_files = [f for f in os.listdir(cache_dir) if f.startswith(url_hash)]
        if cache_files:
            cached_file = os.path.join(cache_dir, cache_files[0])
            logger.debug(f"图片代理缓存命中: {url} -> {cached_file}")
            return FileResponse(
                cached_file,
                media_type="image/webp",
                headers={
                    "Cache-Control": "public, max-age=86400",
                    "X-Cache-Status": "HIT"
                }
            )
    
    # 3. 缓存未命中，下载并转码存储
    logger.info(f"图片代理缓存未命中，开始下载: {url}")
    
    headers = _request_headers_for_url(url)
    proxy = await ConfigService().get_http_proxy()
    
    try:
        transport = create_safe_async_transport(proxy=proxy) if proxy else create_safe_async_transport()
        async with httpx.AsyncClient(
            transport=transport,
            timeout=httpx.Timeout(10.0, connect=5.0),
        ) as client:
            original_data, content_type, final_url = await _download_remote_image(
                client,
                url,
                headers,
            )
            _validate_proxy_image_pixels(original_data)
            
            # 4. 转码为WebP（支持动画GIF）
            try:
                webp_data, width, height = _image_to_webp(original_data, quality=80)
                if width is not None and height is not None:
                    if int(width) * int(height) > _MAX_PROXY_IMAGE_PIXELS:
                        raise HTTPException(status_code=413, detail="图片像素尺寸过大")
                
                # 5. 存储到本地
                cache_key = f"{cache_namespace}/{url_hash}.webp"
                await storage.put_bytes(key=cache_key, data=webp_data, content_type="image/webp")
                await _enforce_proxy_cache_quota(storage)
                
                logger.info(
                    f"图片代理已缓存: {final_url} -> {cache_key} "
                    f"[{len(original_data)//1024}KB原始 -> {len(webp_data)//1024}KB WebP, "
                    f"{width}x{height}]"
                )
                
                # 6. 返回转码后的图片
                return StreamingResponse(
                    iter([webp_data]),
                    media_type="image/webp",
                    headers={
                        "Cache-Control": "public, max-age=86400",
                        "X-Cache-Status": "MISS",
                        "X-Original-Size": str(len(original_data)),
                        "X-Compressed-Size": str(len(webp_data)),
                    }
                )
            except HTTPException:
                raise
            
            except Exception as transcode_error:
                # 转码失败，返回原图
                logger.warning(f"图片转码失败，返回原图: {transcode_error}")
                
                # 存储原图
                ext = content_type.split("/")[-1].split(";")[0]
                if ext not in ["jpeg", "jpg", "png", "gif", "webp"]:
                    ext = "jpg"
                cache_key = f"{cache_namespace}/{url_hash}.{ext}"
                await storage.put_bytes(key=cache_key, data=original_data, content_type=content_type)
                await _enforce_proxy_cache_quota(storage)
                
                return StreamingResponse(
                    iter([original_data]),
                    media_type=content_type,
                    headers={
                        "Cache-Control": "public, max-age=86400",
                        "X-Cache-Status": "MISS-RAW",
                    }
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
