"""
颜色提取模块

从图片中提取主色调信息
"""
import httpx
from typing import Optional

from app.core.logging import logger


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
        async with httpx.AsyncClient(timeout=timeout_seconds) as client:
            resp = await client.get(url)
            resp.raise_for_status()
            data = resp.content
            return _get_dominant_color(data)
    except Exception as e:
        logger.warning(f"提取封面颜色失败 ({url}): {e}")
        return None
