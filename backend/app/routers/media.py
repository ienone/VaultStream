"""
功能描述：媒体资源代理 API
包含：本地媒体代理、远程图片代理
调用方式：无需 API Token (方便前端直接加载)，但部分接口可能限制来源
"""
import os
import ipaddress
import mimetypes
import socket
import urllib.parse
from urllib.parse import urlparse

import httpx
from fastapi import APIRouter, Depends, HTTPException, Query
from fastapi.responses import FileResponse, StreamingResponse

from app.core.logging import logger
from app.core.config import settings
from app.core.storage import get_storage_backend, LocalStorageBackend

router = APIRouter()


def _is_safe_url(url: str) -> bool:
    """检查 URL 是否安全（防止 SSRF 访问内网）"""
    try:
        parsed = urlparse(url)
        if parsed.scheme not in ("http", "https"):
            return False
        hostname = parsed.hostname
        if not hostname:
            return False
        # 解析域名到 IP 并检查是否为私有/保留地址
        for info in socket.getaddrinfo(hostname, None):
            addr = ipaddress.ip_address(info[4][0])
            
            # 调试模式下放行所有 IP，避免 Fake-IP (TUN 模式) 或 Loopback 被误判拦截
            if settings.debug:
                continue

            # 放行 Fake-IP 常见网段 (Clash / V2Ray 等代理环境)
            if addr.version == 4 and addr in ipaddress.ip_network('198.18.0.0/15'):
                continue

            if addr.is_private or addr.is_reserved or addr.is_link_local:
                return False
        return True
    except (ValueError, socket.gaierror):
        return False

@router.get("/media/{key:path}")
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
    if ".." in key:
        raise HTTPException(status_code=400, detail="Invalid media key")

    file_path = storage._full_path(key)
    # 确保解析后的路径仍在存储根目录内
    if not os.path.realpath(file_path).startswith(os.path.realpath(storage.root_dir)):
        raise HTTPException(status_code=403, detail="Access denied")

    if not os.path.exists(file_path):
        raise HTTPException(status_code=404, detail="Media not found")
        
    mime_type, _ = mimetypes.guess_type(file_path)
    if not mime_type:
        mime_type = "application/octet-stream"
    
    # 添加缓存头优化性能
    return FileResponse(
        file_path, 
        media_type=mime_type,
        headers={
            "Cache-Control": "public, max-age=31536000, immutable",  # 1年缓存
            "ETag": f'"{key}"',
        }
    )

@router.get("/proxy/image")
async def proxy_image(
    url: str = Query(..., description="要代理的图片 URL"),
    storage: LocalStorageBackend = Depends(get_storage_backend),
):
    """通用图片代理，用于解决跨域、Referer 校验或网络瓶颈
    
    优化机制：
    1. 首次访问：下载并转码为WebP存储到本地
    2. 后续访问：直接返回本地缓存（速度提升100倍+）
    """
    import hashlib
    from pathlib import Path
    from app.media.processor import (
        _image_to_webp,
        _request_headers_for_url,
        _content_addressed_key,
        _sha256_bytes,
    )
    
    # 还原 URL 编码以确保 hash 一致性 (前端通过 query 参数传过来往往会被 encode)
    url = urllib.parse.unquote(url)

    # SSRF 防护：禁止访问内网地址
    if not _is_safe_url(url):
        raise HTTPException(status_code=400, detail="目标 URL 不允许访问（内网地址或无效协议）")

    # 1. 生成缓存key（使用URL的MD5作为命名空间）
    url_hash = hashlib.md5(url.encode()).hexdigest()
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
    from app.services.settings_service import get_setting_value
    proxy = await get_setting_value("http_proxy", getattr(settings, 'http_proxy', None))
    
    try:
        async with httpx.AsyncClient(proxy=proxy, timeout=httpx.Timeout(10.0, connect=5.0)) as client:
            resp = await client.get(url, headers=headers, follow_redirects=True)
            
            if resp.status_code != 200:
                logger.error(f"图片代理上游错误 {resp.status_code}: {url}")
                raise HTTPException(
                    status_code=502,
                    detail=f"上游服务器返回错误: {resp.status_code}"
                )
            
            original_data = resp.content
            content_type = resp.headers.get("content-type", "image/jpeg")
            
            # 4. 转码为WebP（支持动画GIF）
            try:
                webp_data, width, height = _image_to_webp(original_data, quality=80)
                sha256 = _sha256_bytes(webp_data)
                
                # 5. 存储到本地
                cache_key = f"{cache_namespace}/{url_hash}.webp"
                await storage.put_bytes(key=cache_key, data=webp_data, content_type="image/webp")
                
                logger.info(
                    f"图片代理已缓存: {url} -> {cache_key} "
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
            
            except Exception as transcode_error:
                # 转码失败，返回原图
                logger.warning(f"图片转码失败，返回原图: {transcode_error}")
                
                # 存储原图
                ext = content_type.split("/")[-1].split(";")[0]
                if ext not in ["jpeg", "jpg", "png", "gif", "webp"]:
                    ext = "jpg"
                cache_key = f"{cache_namespace}/{url_hash}.{ext}"
                await storage.put_bytes(key=cache_key, data=original_data, content_type=content_type)
                
                return StreamingResponse(
                    iter([original_data]),
                    media_type=content_type,
                    headers={
                        "Cache-Control": "public, max-age=86400",
                        "X-Cache-Status": "MISS-RAW",
                    }
                )
    
    except httpx.TimeoutException:
        logger.error(f"图片代理请求超时: {url}")
        raise HTTPException(status_code=504, detail="上游服务器响应超时")
    
    except httpx.RequestError as e:
        logger.error(f"图片代理网络错误: {url}, {e}")
        raise HTTPException(status_code=502, detail=f"网络请求失败: {str(e)}")
    
    except Exception as e:
        logger.error(f"图片代理未知错误: {url}, {e}", exc_info=True)
        raise HTTPException(status_code=500, detail="图片代理服务内部错误")
