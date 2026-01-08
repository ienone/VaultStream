"""
后台任务处理器
"""
import asyncio
from app.logging import logger, log_context, ensure_task_id
import traceback
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession
from typing import Optional

from app.queue import task_queue
from app.database import AsyncSessionLocal
from app.models import Content, ContentStatus, Platform, utcnow, PushedRecord, ReviewStatus
from app.adapters import AdapterFactory
from app.config import settings
from app.utils import normalize_bilibili_url
from app.adapters.errors import AdapterError, RetryableAdapterError
from app.storage import get_storage_backend
from app.media_processing import store_archive_images_as_webp, store_archive_videos
from app.push_service import get_push_service


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
            task_data: 任务数据，包含 content_id 和可选的 action 字段
                      action 可以是 "parse" (默认) 或 "distribute"
        """
        schema_version = int(task_data.get("schema_version") or 1)
        action = task_data.get("action") or "parse"
        attempt = int(task_data.get("attempt") or 0)
        max_attempts = int(task_data.get("max_attempts") or 3)
        content_id = task_data.get('content_id')
        task_id = ensure_task_id(task_data.get("task_id"))
        
        if not content_id:
            logger.warning("任务数据缺少 content_id")
            return
        
        # 根据 action 分发到不同的处理器
        if action == "distribute":
            await self._process_distribution_task(task_data, task_id)
        else:
            await self._process_parse_task(task_data, task_id)
    
    async def _process_distribution_task(self, task_data: dict, task_id: str):
        """
        处理分发任务（M4）
        
        task_data 示例:
        {
            "action": "distribute",
            "content_id": 123,
            "rule_id": 1,
            "target_platform": "telegram",
            "target_id": "@my_channel"
        }
        """
        content_id = task_data.get('content_id')
        target_platform = task_data.get('target_platform')
        target_id = task_data.get('target_id')
        rule_id = task_data.get('rule_id')
        
        with log_context(task_id=task_id, content_id=content_id):
            logger.info(f"开始处理分发任务: target={target_platform}:{target_id}")
            
            async with AsyncSessionLocal() as session:
                try:
                    # 获取内容记录
                    result = await session.execute(
                        select(Content).where(Content.id == content_id)
                    )
                    content = result.scalar_one_or_none()
                    
                    if not content:
                        logger.warning(f"内容不存在: {content_id}")
                        return
                    
                    # 检查审批状态
                    if content.review_status not in [ReviewStatus.APPROVED, ReviewStatus.AUTO_APPROVED]:
                        logger.warning(f"内容未批准，跳过分发: review_status={content.review_status}")
                        return
                    
                    # 检查是否已推送
                    existing = await session.execute(
                        select(PushedRecord).where(
                            PushedRecord.content_id == content_id,
                            PushedRecord.target_id == target_id
                        )
                    )
                    if existing.scalar_one_or_none():
                        logger.info(f"内容已推送到目标，跳过: target_id={target_id}")
                        return
                    
                    # 调用推送服务发送消息
                    push_service = get_push_service()
                    
                    # 构造内容数据（需要转为 dict）
                    content_dict = {
                        "id": content.id,
                        "title": content.title,
                        "platform": content.platform.value if content.platform else None,
                        "cover_url": content.cover_url,
                        "raw_metadata": content.raw_metadata,
                        "canonical_url": content.canonical_url,
                        "tags": content.tags,
                        "is_nsfw": content.is_nsfw
                    }
                    
                    # 根据目标平台类型推送
                    message_id = None
                    if target_platform == "telegram":
                        message_id = await push_service.push_to_telegram(content_dict, target_id)
                    else:
                        logger.warning(f"不支持的推送平台: {target_platform}")
                        return
                    
                    if message_id:
                        # 创建推送记录
                        push_record = PushedRecord(
                            content_id=content_id,
                            target_platform=target_platform,
                            target_id=target_id,
                            message_id=str(message_id),
                            push_status="success"
                        )
                        session.add(push_record)
                        await session.commit()
                        
                        logger.info(
                            f"分发任务完成: content_id={content_id}, "
                            f"target={target_id}, message_id={message_id}"
                        )
                    else:
                        # 推送失败，记录失败状态
                        push_record = PushedRecord(
                            content_id=content_id,
                            target_platform=target_platform,
                            target_id=target_id,
                            push_status="failed"
                        )
                        session.add(push_record)
                        await session.commit()
                        logger.error(f"分发任务失败: content_id={content_id}, target={target_id}")
                    
                except Exception as e:
                    logger.error(f"分发任务失败: {e}", exc_info=True)
                    await session.rollback()
    
    async def _process_parse_task(self, task_data: dict, task_id: str):
        """处理解析任务"""
        schema_version = int(task_data.get("schema_version") or 1)
        action = task_data.get("action") or "parse"
        attempt = int(task_data.get("attempt") or 0)
        max_attempts = int(task_data.get("max_attempts") or 3)
        content_id = task_data.get('content_id')
        
        if not content_id:
            logger.warning("任务数据缺少 content_id")
            return
        
        async with AsyncSessionLocal() as session:
            content = None
            with log_context(task_id=task_id, content_id=content_id):
                try:
                    logger.info(f"开始处理任务: schema={schema_version}, action={action}, attempt={attempt}/{max_attempts}")
                    # 获取内容记录
                    result = await session.execute(
                        select(Content).where(Content.id == content_id)
                    )
                    content = result.scalar_one_or_none()

                    if not content:
                        logger.warning(f"内容不存在: {content_id}")
                        await task_queue.mark_complete(content_id)
                        return

                    # 幂等：解析任务遇到已完成内容，默认跳过。
                    # 但若启用了归档媒体处理且存在未处理图片，则允许补处理（不重新解析）。
                    if action == "parse" and content.status == ContentStatus.PULLED:
                        if settings.enable_archive_media_processing:
                            meta = content.raw_metadata
                            archive = meta.get("archive") if isinstance(meta, dict) else None
                            images = archive.get("images") if isinstance(archive, dict) else None
                            need_media = False
                            if isinstance(images, list) and images:
                                for img in images:
                                    if isinstance(img, dict) and img.get("url") and not img.get("stored_key"):
                                        need_media = True
                                        break

                            if need_media:
                                logger.info("内容已解析完成，但存在未处理图片；开始补处理归档媒体")
                                try:
                                    # Reuse the same processing logic by emulating ParsedContent shape.
                                    class _ParsedLike:
                                        raw_metadata = meta

                                    await self._maybe_process_private_archive_media(_ParsedLike())
                                    content.raw_metadata = meta
                                    await session.commit()
                                    logger.info("补处理归档媒体完成")
                                except Exception as e:
                                    logger.warning("补处理归档媒体失败，跳过: {}", f"{type(e).__name__}: {e}")

                        logger.info("内容已解析完成，跳过解析")
                        await task_queue.mark_complete(content_id)
                        return

                    # 更新状态为处理中
                    content.status = ContentStatus.PROCESSING
                    await session.commit()

                    # Pipeline 重试策略：仅对 retryable 错误进行指数退避重试
                    parsed = None
                    last_err: Exception | None = None
                    base_delay = 1.0
                    for i in range(max(1, max_attempts - attempt)):
                        try:
                            # 增强解析鲁棒性：处理 B 站 ID 拼接
                            if content.platform == Platform.BILIBILI:
                                content.url = normalize_bilibili_url(content.url)

                            adapter = AdapterFactory.create(
                                content.platform,
                                cookies=self._get_platform_cookies(content.platform)
                            )

                            logger.info(f"开始解析内容 (try={attempt + i + 1}/{max_attempts})")
                            parsed = await adapter.parse(content.url)
                            last_err = None
                            break
                        except AdapterError as e:
                            last_err = e
                            if not e.retryable:
                                raise
                            # retryable: sleep and continue
                            delay = base_delay * (2 ** (attempt + i))
                            logger.warning(f"可重试错误，{delay:.1f}s 后重试: {e}")
                            await asyncio.sleep(delay)
                        except Exception as e:
                            # 未分类异常：默认不重试（避免无限放大问题）
                            last_err = e
                            raise

                    if parsed is None:
                        # 全部重试失败：统一抛出为 RetryableAdapterError 以便落库
                        raise RetryableAdapterError(
                            f"解析重试失败，已达到最大次数: {max_attempts}",
                            details={"last_error": str(last_err) if last_err else None},
                        )

                    # 更新内容信息
                    content.clean_url = parsed.clean_url
                    content.content_type = parsed.content_type
                    content.title = parsed.title
                    content.description = parsed.description
                    content.author_name = parsed.author_name
                    content.author_id = parsed.author_id
                    content.published_at = parsed.published_at
                    # 可选：对私有归档中的媒体进行处理（下载/转码/存储），不影响对外分享字段。
                    if settings.enable_archive_media_processing:
                        try:
                            await self._maybe_process_private_archive_media(parsed)
                        except Exception as e:
                            logger.warning("Archive media processing skipped: {}", f"{type(e).__name__}: {e}")

                    # 将（可能被本地化的）媒体字段同步回内容记录
                    content.cover_url = parsed.cover_url
                    content.media_urls = parsed.media_urls

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
                    
                    # M4: 解析完成后尝试自动审批
                    try:
                        from app.distribution import DistributionEngine
                        engine = DistributionEngine(session)
                        auto_approved = await engine.auto_approve_if_eligible(content)
                        
                        if auto_approved:
                            logger.info(f"内容已自动审批: content_id={content_id}")
                    except Exception as e:
                        logger.warning(f"自动审批检查失败: {e}", exc_info=True)

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

                    # 任务死信：达到最大尝试次数/不可重试错误
                    reason = "failed"
                    if isinstance(e, AdapterError) and e.auth_required:
                        reason = "auth_required"
                    elif isinstance(e, AdapterError) and not e.retryable:
                        reason = "non_retryable"
                    elif attempt + 1 >= max_attempts:
                        reason = "max_attempts_reached"

                    if reason != "failed":
                        await task_queue.push_dead_letter(task_data, reason=reason)
                
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

    async def _maybe_process_private_archive_media(self, parsed) -> None:
        """进程私有归档媒体（如适用）。

        当前的实现：
            - 如果 parsed.raw_metadata 包含类似 opus 的归档且带有图片 URL，则将其存储为 WebP。

        备注：
        - 这会原地修改 parsed.raw_metadata（仅限私有）。
        - 也会根据本地化结果同步更新面向分享的字段，如 cover_url/media_urls。
        """

        meta = getattr(parsed, "raw_metadata", None)
        if not isinstance(meta, dict):
            return

        archive = meta.get("archive")
        if not isinstance(archive, dict):
            return

        images = archive.get("images")
        if not isinstance(images, list) or not images:
            return

        storage = get_storage_backend()

        # MinIO/S3: 确保bucket存在,避免首次使用时失败
        ensure_bucket = getattr(storage, "ensure_bucket", None)
        if callable(ensure_bucket):
            await ensure_bucket()

        namespace = "vaultstream"
        quality = int(getattr(settings, "archive_image_webp_quality", 80) or 80)
        max_count = getattr(settings, "archive_image_max_count", None)

        await store_archive_images_as_webp(
            archive=archive,
            storage=storage,
            namespace=namespace,
            quality=quality,
            max_images=max_count,
        )
        
        # 将本地化后的图片 URL 同步回 ParsedContent，供外部展示使用
        stored_images = archive.get("stored_images", [])
        if stored_images:
            # 提取所有本地化后的 URL
            local_urls = [img["url"] for img in stored_images if img.get("url")]
            if local_urls:
                # 严格去重并保持顺序 (使用 dict.fromkeys 来保持顺序)
                unique_local_urls = list(dict.fromkeys(local_urls))
                
                # 始终使用本地化后的真实 URL 覆盖原始 URL
                parsed.media_urls = unique_local_urls
                
                # 同步更新封面
                parsed.cover_url = unique_local_urls[0]

        # 处理视频（如果存档中有视频）
        if archive.get("videos"):
            max_videos = getattr(settings, "archive_video_max_count", None)
            await store_archive_videos(
                archive=archive,
                storage=storage,
                namespace=namespace,
                max_videos=max_videos,
            )

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
        content.published_at = parsed.published_at

        if settings.enable_archive_media_processing:
            try:
                await self._maybe_process_private_archive_media(parsed)
            except Exception as e:
                logger.warning("Archive media processing skipped: {}", f"{type(e).__name__}: {e}")

        content.cover_url = parsed.cover_url
        content.media_urls = parsed.media_urls
        content.raw_metadata = parsed.raw_metadata

        # 统一存储 ID 和互动数据
        content.platform_id = parsed.content_id
        if hasattr(parsed, 'stats') and parsed.stats:
            content.view_count = parsed.stats.get('view', 0)
            content.like_count = parsed.stats.get('like', 0)
            content.collect_count = parsed.stats.get('favorite', 0)
            content.share_count = parsed.stats.get('share', 0)
            content.comment_count = parsed.stats.get('reply', 0)
            
            # 平台特有数据存储到 extra_stats
            if content.platform == Platform.BILIBILI:
                # B站特有数据
                content.extra_stats = {
                    "coin": parsed.stats.get('coin', 0),
                    "danmaku": parsed.stats.get('danmaku', 0),
                    "live_status": parsed.stats.get('live_status', 0)
                }
            elif content.platform == Platform.TWITTER:
                # Twitter 特有数据
                content.extra_stats = {
                    "bookmarks": parsed.stats.get('bookmarks', 0),
                    "screen_name": parsed.stats.get('screen_name'),
                    "replying_to": parsed.stats.get('replying_to'),
                }
            else:
                # 其他平台：保留所有非通用字段
                extra_keys = set(parsed.stats.keys()) - {'view', 'like', 'favorite', 'share', 'reply'}
                content.extra_stats = {k: parsed.stats[k] for k in extra_keys if k in parsed.stats}

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
