"""
功能描述：媒体资源代理 API
包含：本地媒体代理、远程图片代理
调用方式：无需 API Token (方便前端直接加载)，但部分接口可能限制来源
"""
import os
import mimetypes
import httpx
from fastapi import APIRouter, Depends, HTTPException, Query
from fastapi.responses import FileResponse, StreamingResponse

from app.core.logging import logger
from app.core.config import settings
from app.core.storage import get_storage_backend, LocalStorageBackend

router = APIRouter()

@router.get("/media/{key:path}")
async def proxy_media(
    key: str,
    storage: LocalStorageBackend = Depends(get_storage_backend),
):
    """
    媒体代理 API
    支持 Range 请求以加速播放视频预览。
    """
    if not isinstance(storage, LocalStorageBackend):
        raise HTTPException(status_code=400, detail="Only local storage proxy is supported")
        
    file_path = storage._full_path(key)
    if not os.path.exists(file_path):
        raise HTTPException(status_code=404, detail="Media not found")
        
    mime_type, _ = mimetypes.guess_type(file_path)
    if not mime_type:
        mime_type = "application/octet-stream"
        
    return FileResponse(file_path, media_type=mime_type)

@router.get("/proxy/image")
async def proxy_image(url: str = Query(..., description="要代理的图片 URL")):
    """通用图片代理，用于解决跨域、Referer 校验或网络瓶颈"""
    async def stream_image():
        headers = {
            "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/91.0.4472.124 Safari/537.36",
        }
        if "hdslb.com" in url or "bilibili" in url:
            headers["Referer"] = "https://www.bilibili.com/"
        elif "sinaimg.cn" in url or "weibocdn.com" in url:
            headers["Referer"] = "https://weibo.com/"
        
        proxy = settings.http_proxy or settings.https_proxy
        
        async with httpx.AsyncClient(proxy=proxy, timeout=10.0) as client:
            try:
                async with client.stream("GET", url, headers=headers, follow_redirects=True) as resp:
                    if resp.status_code != 200:
                         logger.error(f"Image proxy upstream error {resp.status_code} for {url}")
                         raise Exception(f"Upstream error {resp.status_code}")
                    
                    async for chunk in resp.aiter_bytes():
                        yield chunk
            except Exception as e:
                logger.error(f"Image proxy error for {url}: {e}")

    return StreamingResponse(stream_image(), media_type="image/jpeg")
