"""
后台任务处理器
"""
import asyncio
from app.logging import logger, log_context, ensure_task_id
import traceback
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.queue import task_queue
from app.database import AsyncSessionLocal
from app.models import Content, ContentStatus, Platform, utcnow
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

                    # 更新状态为已抓取并清理失败信息（保留 failure_count 作为历史统计）
                    content.status = ContentStatus.PULLED
                    content.last_error = None
                    content.last_error_type = None
                    content.last_error_detail = None
                    content.last_error_at = None

                    await session.commit()
                    logger.info("内容解析完成")

                except Exception as e:
                    logger.error(f"处理任务失败: {content_id}, 错误: {e}")
                    
                    # 更新状态为失败
                    if content:
                        content.status = ContentStatus.FAILED
                        content.failure_count = (content.failure_count or 0) + 1
                        content.last_error = str(e)
                        content.last_error_type = type(e).__name__
                        content.last_error_detail = {
                            "message": str(e),
                            "traceback": traceback.format_exc(limit=50),
                        }
                        content.last_error_at = utcnow()
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

    async def _do_parse(self, session: AsyncSession, content: Content):
        """执行一次解析并保存结果（单次尝试）。

        注意：调用方负责在事务/会话边界内传入 `session` 和 `content` 实例。
        """
        # 增强解析鲁棒性：处理 B 站 ID 拼接
        if content.platform == Platform.BILIBILI:
            content.url = normalize_bilibili_url(content.url)

        adapter = AdapterFactory.create(
            content.platform,
            cookies=self._get_platform_cookies(content.platform)
        )

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
            content.extra_stats = {
                "coin": parsed.stats.get('coin', 0),
                "danmaku": parsed.stats.get('danmaku', 0),
                "live_status": parsed.stats.get('live_status', 0)
            }

        # 标记已抓取并清理失败信息
        content.status = ContentStatus.PULLED
        content.last_error = None
        content.last_error_type = None
        content.last_error_detail = None
        content.last_error_at = None

        await session.commit()

    async def retry_parse(self, content_id: int, max_retries: int = 3, delay_seconds: float = 1.0, backoff_factor: float = 2.0):
        """对指定 content_id 进行重试解析。

        会进行最多 `max_retries` 次尝试（包含第一次），每次失败会记录失败信息并按指数退避等待。
        最终如果仍然失败，状态保留为 `FAILED`，以便人工后续修复或再次触发重试。
        """
        attempt = 0
        wait = delay_seconds

        while attempt < max_retries:
            attempt += 1
            try:
                async with AsyncSessionLocal() as session:
                    result = await session.execute(
                        select(Content).where(Content.id == content_id)
                    )
                    content = result.scalar_one_or_none()

                    if not content:
                        logger.warning(f"重试解析：内容不存在 {content_id}")
                        return False

                    # 如果已解析成功，直接返回
                    if content.status == ContentStatus.PULLED:
                        logger.info(f"重试解析：内容已解析完成 {content_id}")
                        return True

                    # 标记为处理中以避免并发重试
                    content.status = ContentStatus.PROCESSING
                    await session.commit()

                    # 执行一次解析尝试
                    await self._do_parse(session, content)

                    logger.info(f"重试解析成功: {content_id} (attempt={attempt})")
                    return True

            except Exception as e:
                logger.warning(f"重试解析第 {attempt} 次失败: {content_id}, err: {e}")
                try:
                    async with AsyncSessionLocal() as session:
                        # 再次加载记录以保存失败信息
                        result = await session.execute(
                            select(Content).where(Content.id == content_id)
                        )
                        content = result.scalar_one_or_none()
                        if content:
                            content.status = ContentStatus.FAILED
                            content.failure_count = (content.failure_count or 0) + 1
                            content.last_error = str(e)
                            content.last_error_type = type(e).__name__
                            content.last_error_detail = {
                                "message": str(e),
                                "traceback": traceback.format_exc(limit=50),
                            }
                            content.last_error_at = utcnow()
                            await session.commit()
                except Exception:
                    logger.error("保存失败信息时发生错误", exc_info=True)

                if attempt >= max_retries:
                    logger.error(f"重试达到最大次数({max_retries})，标记为失败: {content_id}")
                    return False

                # 等待后继续下一次尝试（指数退避）
                await asyncio.sleep(wait)
                wait = wait * backoff_factor


# 全局worker实例
worker = TaskWorker()
