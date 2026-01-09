import asyncio
import sys
import os

# 将项目根目录添加到路径
sys.path.append(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from sqlalchemy import select, update
from app.database import AsyncSessionLocal
from app.models import Content
from app.media_processing import _get_dominant_color, _request_headers_for_url
from app.storage import get_storage_backend
from app.config import settings
import httpx
from app.logging import logger

async def update_missing_colors():
    storage = get_storage_backend()
    proxy = settings.http_proxy if hasattr(settings, 'http_proxy') and settings.http_proxy else None
    
    async with AsyncSessionLocal() as session:
        # 查询有封面但没颜色的记录
        result = await session.execute(
            select(Content).where(
                Content.cover_url.isnot(None),
                Content.cover_color.is_(None)
            )
        )
        contents = result.scalars().all()
        
        logger.info(f"找到 {len(contents)} 条待补全颜色的记录")
        
        async with httpx.AsyncClient(proxy=proxy, timeout=12.0, follow_redirects=True) as client:
            for content in contents:
                try:
                    logger.info(f"正在处理 Content ID: {content.id}, URL: {content.cover_url}")
                    
                    img_data = None
                    url = content.cover_url or ""
                    
                    # 1. 处理远程 URL
                    if url.startswith('http'):
                        resp = await client.get(url, headers=_request_headers_for_url(url))
                        if resp.status_code == 200:
                            img_data = resp.content
                        else:
                            logger.warning(f"获取远程图片失败 {url}, code={resp.status_code}")
                    
                    # 2. 处理本地路径 (支持 /media/ 或相对于存储根目录的路径)
                    elif len(url) > 0:
                        # 转换 /media/vaultstream/blobs/... 为 key: vaultstream/blobs/...
                        clean_path = url
                        if '/media/' in url:
                            clean_path = url.split('/media/')[-1].lstrip('/')
                        elif '/api/v1/media/' in url:
                            clean_path = url.split('/api/v1/media/')[-1].lstrip('/')
                        
                        try:
                            img_data = await storage.get_bytes(clean_path)
                        except Exception as storage_err:
                            logger.warning(f"从存储后端获取本地图片失败 {clean_path}: {storage_err}")
                    
                    if img_data:
                        color = _get_dominant_color(img_data)
                        if color:
                            content.cover_color = color
                            logger.info(f"成功更新颜色: {color}")
                    
                    if content.id % 5 == 0:
                        await session.commit()
                        
                except Exception as e:
                    logger.error(f"处理 ID {content.id} 失败: {e}")
            
            await session.commit()
    logger.info("所有存量数据处理完毕")

if __name__ == "__main__":
    asyncio.run(update_missing_colors())
