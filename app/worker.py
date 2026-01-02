"""
后台任务处理器
"""
import asyncio
from app.logging import logger, log_context, ensure_task_id
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.queue import task_queue
from app.database import AsyncSessionLocal
from app.models import Content, ContentStatus, Platform
from app.adapters import AdapterFactory
from app.config import settings
from app.utils import normalize_bilibili_url


class TaskWorker:
    """任务处理器"""
    
    def __init__(self):
        self.running = False
    
    async def start(self):
        """启动worker"""
        self.running = True
        logger.info("Task worker started")
        
        while self.running:
            try:
                # 从队列获取任务
                task_data = await task_queue.dequeue(timeout=5)
                
                if task_data:
                    await self.process_task(task_data)
                    
            except Exception as e:
                logger.error(f"Worker error: {e}")
                await asyncio.sleep(1)
    
    async def stop(self):
        """停止worker"""
        self.running = False
        logger.info("Task worker stopped")
    
    async def process_task(self, task_data: dict):
        """
        处理单个任务
        
        Args:
            task_data: 任务数据，包含 content_id
        """
        content_id = task_data.get('content_id')
        task_id = ensure_task_id(task_data.get("task_id"))
        if not content_id:
            logger.warning("任务数据缺少 content_id")
            return
        
        async with AsyncSessionLocal() as session:
            content = None
            with log_context(task_id=task_id, content_id=content_id):
                try:
                    # 获取内容记录
                    result = await session.execute(
                        select(Content).where(Content.id == content_id)
                    )
                    content = result.scalar_one_or_none()

                    if not content:
                        logger.warning(f"内容不存在: {content_id}")
                        await task_queue.mark_complete(content_id)
                        return

                    # 更新状态为处理中
                    content.status = ContentStatus.PROCESSING
                    await session.commit()

                    # 增强解析鲁棒性：处理 B 站 ID 拼接
                    if content.platform == Platform.BILIBILI:
                        content.url = normalize_bilibili_url(content.url)

                    # 创建适配器
                    adapter = AdapterFactory.create(
                        content.platform,
                        cookies=self._get_platform_cookies(content.platform)
                    )

                    # 解析内容
                    logger.info("开始解析内容")
                    parsed = await adapter.parse(content.url)

                    # 更新内容信息
                    content.clean_url = parsed.clean_url
                    content.content_type = parsed.content_type
                    content.title = parsed.title
                    content.description = parsed.description
                    content.author_name = parsed.author_name
                    content.author_id = parsed.author_id
                    content.cover_url = parsed.cover_url
                    content.media_urls = parsed.media_urls
                    content.published_at = parsed.published_at
                    content.raw_metadata = parsed.raw_metadata

                    # 统一存储 ID 和互动数据
                    content.platform_id = parsed.content_id
                    if hasattr(parsed, 'stats') and parsed.stats:
                        content.view_count = parsed.stats.get('view', 0)
                        content.like_count = parsed.stats.get('like', 0)
                        content.collect_count = parsed.stats.get('favorite', 0)
                        content.share_count = parsed.stats.get('share', 0)
                        content.comment_count = parsed.stats.get('reply', 0)
                        # 存储 B 站特有的投币、弹幕和直播状态到 extra_stats
                        content.extra_stats = {
                            "coin": parsed.stats.get('coin', 0),
                            "danmaku": parsed.stats.get('danmaku', 0),
                            "live_status": parsed.stats.get('live_status', 0)
                        }

                    # 更新状态为已抓取
                    content.status = ContentStatus.PULLED

                    await session.commit()
                    logger.info("内容解析完成")

                except Exception as e:
                    logger.error(f"处理任务失败: {content_id}, 错误: {e}")
                    
                    # 更新状态为失败
                    if content:
                        content.status = ContentStatus.FAILED
                        await session.commit()
                
                finally:
                    # 标记任务完成
                    await task_queue.mark_complete(content_id)
    
    def _get_platform_cookies(self, platform: Platform) -> dict:
        """获取平台cookies"""
        if platform == Platform.BILIBILI:
            cookies = {}
            if settings.bilibili_sessdata:
                cookies['SESSDATA'] = settings.bilibili_sessdata.get_secret_value()
            if settings.bilibili_bili_jct:
                cookies['bili_jct'] = settings.bilibili_bili_jct.get_secret_value()
            if settings.bilibili_buvid3:
                cookies['buvid3'] = settings.bilibili_buvid3.get_secret_value()
            return cookies
        return {}


# 全局worker实例
worker = TaskWorker()
