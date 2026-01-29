"""
颜色提取模块

从图片中提取主色调信息
"""
import httpx
from pathlib import Path
from typing import Optional
from urllib.parse import urlparse

from app.core.logging import logger
from app.core.config import settings


def _get_dominant_color(data: bytes) -> str:
    """
    获取图片的主色调 (Hex 格式)
    
    使用PIL提取图片的主要颜色
    
    Args:
        data: 图片的二进制数据
        
    Returns:
        主色调的Hex字符串，如 "#FF5733"
    """
    try:
        from PIL import Image
        from io import BytesIO
        
        img = Image.open(BytesIO(data))
        img = img.convert("RGB")
        img = img.resize((100, 100))  # 缩小以提高性能
        
        # 获取颜色直方图
        pixels = list(img.getdata())
        color_count = {}
        for pixel in pixels:
            if pixel in color_count:
                color_count[pixel] += 1
            else:
                color_count[pixel] = 1
        
        # 找到最常见的颜色
        dominant_color = max(color_count, key=color_count.get)
        return f"#{dominant_color[0]:02x}{dominant_color[1]:02x}{dominant_color[2]:02x}"
    except Exception as e:
        logger.warning(f"提取主色调失败: {e}")
        return "#000000"


def _try_read_local_media(url: str) -> Optional[bytes]:
    """
    尝试从本地存储读取媒体文件
    
    如果URL指向本地媒体路径，直接从磁盘读取避免HTTP回环请求
    """
    try:
        parsed = urlparse(url)
        # 检查是否是本地媒体路径 (如 /media/vaultstream/blobs/...)
        if parsed.path.startswith("/media/"):
            relative_path = parsed.path[7:]  # 去掉 "/media/" 前缀
            local_path = Path(settings.storage_local_root) / relative_path
            if local_path.exists() and local_path.is_file():
                return local_path.read_bytes()
    except Exception:
        pass
    return None


async def extract_cover_color(url: str, timeout_seconds: float = 10.0) -> Optional[str]:
    """
    从 URL 提取封面主色调（无需启用完整的归档处理）
    
    Args:
        url: 图片URL
        timeout_seconds: 超时时间（秒）
        
    Returns:
        主色调Hex字符串，失败返回None
        
    Examples:
        >>> await extract_cover_color("https://example.com/image.jpg")
        "#FF5733"
    """
    try:
        # 优先尝试本地读取，避免HTTP回环请求导致502错误
        local_data = _try_read_local_media(url)
        if local_data:
            return _get_dominant_color(local_data)
        
        # 远程URL通过HTTP获取
        async with httpx.AsyncClient(timeout=timeout_seconds) as client:
            resp = await client.get(url)
            resp.raise_for_status()
            data = resp.content
            return _get_dominant_color(data)
    except Exception as e:
        logger.warning(f"提取封面颜色失败 ({url}): {e}")
        return None
