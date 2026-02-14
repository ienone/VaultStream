"""
解析任务处理器

处理内容解析、元数据提取、媒体下载等逻辑
"""
import asyncio
import traceback
from typing import Optional, Dict, Any
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.logging import logger, log_context
from app.core.database import AsyncSessionLocal
from app.models import Content, ContentStatus, Platform, utcnow
from app.adapters import AdapterFactory
from app.adapters.errors import AdapterError, RetryableAdapterError
from app.core.config import settings
from app.utils.url_utils import normalize_bilibili_url
from app.core.storage import get_storage_backend
from app.media.processor import store_archive_images_as_webp, store_archive_videos
from app.media.color import extract_cover_color
from app.core.queue import task_queue


class ContentParser:
    """内容解析器"""

    async def process_parse_task(self, task_data: dict, task_id: str):
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

                    # 幂等处理
                    if action == "parse" and content.status == ContentStatus.PARSE_SUCCESS:
                        await self._handle_archived_media_fix(session, content)
                        logger.info("内容已解析完成，跳过解析")
                        await task_queue.mark_complete(content_id)
                        return

                    # 更新状态为处理中
                    content.status = ContentStatus.PROCESSING
                    await session.commit()

                    # 执行解析（带重试）
                    parsed = await self._execute_parse_with_retry(content, attempt, max_attempts)

                    # 更新数据库
                    await self._update_content(session, content, parsed)
                    
                    # 自动审批检查
                    await self._check_auto_approval(session, content)

                except Exception as e:
                    await self._handle_parse_error(session, content, task_data, e, attempt, max_attempts)
                
                finally:
                    # 标记任务完成
                    await task_queue.mark_complete(content_id)

    async def _execute_parse_with_retry(self, content: Content, current_attempt: int, max_attempts: int):
        """执行解析逻辑，包含重试机制"""
        parsed = None
        last_err: Exception | None = None
        base_delay = 1.0
        
        remaining_attempts = max(1, max_attempts - current_attempt)
        
        for i in range(remaining_attempts):
            try:
                # B 站 ID 规范化
                if content.platform == Platform.BILIBILI:
                    content.url = normalize_bilibili_url(content.url)

                adapter = AdapterFactory.create(
                    content.platform,
                    cookies=self._get_platform_cookies(content.platform)
                )

                logger.info(f"开始解析内容 (try={current_attempt + i + 1}/{max_attempts})")
                parsed = await adapter.parse(content.url)
                last_err = None
                return parsed
            except AdapterError as e:
                last_err = e
                if not e.retryable:
                    raise
                # retryable: sleep and continue
                delay = base_delay * (2 ** (current_attempt + i))
                logger.warning(f"可重试错误，{delay:.1f}s 后重试: {e}")
                await asyncio.sleep(delay)
            except Exception as e:
                # 未分类异常：默认不重试
                last_err = e
                raise

        if parsed is None:
            raise RetryableAdapterError(
                f"解析重试失败，已达到最大次数: {max_attempts}",
                details={"last_error": str(last_err) if last_err else None},
            )

    async def _update_content(self, session: AsyncSession, content: Content, parsed: Any):
        """更新内容数据到数据库"""
        content.clean_url = parsed.clean_url
        content.content_type = parsed.content_type
        content.layout_type = parsed.layout_type  # 新增: 保存布局类型
        content.title = parsed.title
        content.description = parsed.description
        content.author_name = parsed.author_name
        content.author_id = parsed.author_id
        content.author_avatar_url = parsed.author_avatar_url
        content.author_url = parsed.author_url
        content.source_tags = parsed.source_tags or []
        content.published_at = parsed.published_at
        
        # Phase 7: 保存结构化字段
        content.associated_question = getattr(parsed, 'associated_question', None)
        content.top_answers = getattr(parsed, 'top_answers', None)

        # 私有归档媒体处理
        if settings.enable_archive_media_processing:
            try:
                await self._maybe_process_private_archive_media(parsed)
            except Exception as e:
                logger.warning("Archive media processing skipped: {}", f"{type(e).__name__}: {e}")
        
        # 补充封面颜色
        if not getattr(parsed, "cover_color", None) and parsed.cover_url:
            parsed.cover_color = await extract_cover_color(parsed.cover_url)

        # 同步回内容记录
        content.cover_url = parsed.cover_url
        content.media_urls = parsed.media_urls
        content.author_avatar_url = parsed.author_avatar_url
        content.raw_metadata = parsed.raw_metadata
        
        content.cover_color = getattr(parsed, "cover_color", None)
        if not content.cover_color and isinstance(content.raw_metadata, dict) and "archive" in content.raw_metadata:
            content.cover_color = content.raw_metadata["archive"].get("dominant_color")

        # 统一 ID 和互动数据
        content.platform_id = parsed.content_id
        if hasattr(parsed, 'stats') and parsed.stats:
            self._map_stats_to_content(content, parsed.stats)

        # 更新状态
        content.status = ContentStatus.PARSE_SUCCESS
        content.last_error = None
        content.last_error_type = None
        content.last_error_detail = None
        content.last_error_at = None

        await session.commit()
        await session.commit()
        logger.info("内容解析完成")
        
        # 广播更新事件
        from app.core.events import event_bus
        await event_bus.publish("content_updated", {
            "id": content.id,
            "title": content.title,
            "status": content.status.value,
            "platform": content.platform.value if content.platform else None,
            "cover_url": content.cover_url
        })

    def _map_stats_to_content(self, content: Content, stats: Dict[str, Any]):
        """将解析的统计数据映射到 Content 模型"""
        content.view_count = stats.get('view', 0)
        content.like_count = stats.get('like', 0)
        content.collect_count = stats.get('favorite', 0)
        content.share_count = stats.get('share', 0)
        content.comment_count = stats.get('reply', 0)
        
        # 平台特有数据
        if content.platform == Platform.BILIBILI:
            content.extra_stats = {
                "coin": stats.get('coin', 0),
                "danmaku": stats.get('danmaku', 0),
                "live_status": stats.get('live_status', 0)
            }
        elif content.platform == Platform.TWITTER:
            content.extra_stats = {
                "bookmarks": stats.get('bookmarks', 0),
                "screen_name": stats.get('screen_name'),
                "replying_to": stats.get('replying_to'),
            }
        elif content.platform == Platform.WEIBO:
            self._map_weibo_stats(content, stats)
        elif content.platform == Platform.ZHIHU:
            self._map_zhihu_stats(content, stats)
        else:
            # 其他平台
            extra_keys = set(stats.keys()) - {'view', 'like', 'favorite', 'share', 'reply'}
            content.extra_stats = {k: stats[k] for k in extra_keys if k in stats}

    def _map_weibo_stats(self, content: Content, stats: Dict[str, Any]):
        """映射微博特有数据"""
        if content.content_type == "user_profile":
            content.view_count = stats.get('followers', stats.get('view', 0))
            content.share_count = stats.get('friends', stats.get('share', 0))
            content.comment_count = stats.get('statuses', stats.get('reply', 0))
            content.extra_stats = {
                "followers": content.view_count,
                "friends": content.share_count,
                "statuses": content.comment_count,
            }
        else:
            content.extra_stats = {
                "repost": stats.get('share', 0),
                "attitudes": stats.get('like', 0),
                "comments": stats.get('reply', 0),
            }

    def _map_zhihu_stats(self, content: Content, stats: Dict[str, Any]):
        """映射知乎特有数据"""
        if content.content_type == "user_profile":
            content.view_count = stats.get('follower_count', 0)
            content.share_count = stats.get('following_count', 0)
            content.like_count = stats.get('voteup_count', 0)
            content.collect_count = stats.get('favorited_count', 0)
            
            content.extra_stats = {
                "follower_count": stats.get('follower_count', 0),
                "following_count": stats.get('following_count', 0),
                "voteup_count": stats.get('voteup_count', 0),
                "thanked_count": stats.get('thanked_count', 0),
                "favorited_count": stats.get('favorited_count', 0),
                # ... 其他字段保留
            }
        else:
            content.extra_stats = {
                "voteup_count": stats.get('voteup_count', 0),
                "thanks_count": stats.get('thanks_count', 0),
                "follower_count": stats.get('follower_count', 0),
                # ...
            }
            if content.content_type == "question":
                content.collect_count = stats.get('follower_count', content.collect_count)
                content.view_count = stats.get('visit_count', content.view_count)
                content.comment_count = stats.get('answer_count', content.comment_count)
            elif content.content_type == "pin":
                content.collect_count = stats.get('favorite', 0)
                content.share_count = stats.get('share', 0)
            elif content.content_type == "article":
                content.collect_count = stats.get('favorited_count', 0)

    async def _handle_parse_error(self, session, content, task_data, error, attempt, max_attempts):
        """处理解析错误"""
        logger.error(f"处理任务失败: {task_data.get('content_id')}, 错误: {error}")
        
        # 更新数据库中的失败状态
        if content:
            content.status = ContentStatus.PARSE_FAILED
            content.failure_count = (content.failure_count or 0) + 1
            content.last_error = str(error)
            content.last_error_type = type(error).__name__
            content.last_error_detail = {
                "message": str(error),
                "traceback": traceback.format_exc(limit=50),
            }
            content.last_error_at = utcnow()
            await session.commit()
            
            # 广播失败事件
            try:
                from app.core.events import event_bus
                await event_bus.publish("content_updated", {
                    "id": content.id,
                    "status": ContentStatus.PARSE_FAILED.value,
                    "error": str(error)
                })
            except Exception:
                pass

        # 判断是否进入死信队列
        reason = "failed"
        if isinstance(error, AdapterError) and error.auth_required:
            reason = "auth_required"
        elif isinstance(error, AdapterError) and not error.retryable:
            reason = "non_retryable"
        elif attempt + 1 >= max_attempts:
            reason = "max_attempts_reached"

        if reason != "failed":
            await task_queue.push_dead_letter(task_data, reason=reason)

    async def _check_auto_approval(self, session, content):
        """M4: 解析完成后尝试自动审批"""
        try:
            from app.distribution import DistributionEngine
            engine = DistributionEngine(session)
            auto_approved = await engine.auto_approve_if_eligible(content)
            
            if auto_approved:
                logger.info(f"内容已自动审批: content_id={content.id}")
        except Exception as e:
            logger.warning(f"自动审批检查失败: {e}", exc_info=True)

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
        """处理私有归档媒体"""
        meta = getattr(parsed, "raw_metadata", None)
        if not isinstance(meta, dict):
            return

        archive = meta.get("archive")
        if not isinstance(archive, dict):
            return

        storage = get_storage_backend()
        
        # MinIO/S3: 确保bucket存在
        ensure_bucket = getattr(storage, "ensure_bucket", None)
        if callable(ensure_bucket):
            await ensure_bucket()

        namespace = "vaultstream"
        quality = int(getattr(settings, "archive_image_webp_quality", 80) or 80)
        max_count = getattr(settings, "archive_image_max_count", None)

        # 处理图片
        await store_archive_images_as_webp(
            archive=archive,
            storage=storage,
            namespace=namespace,
            quality=quality,
            max_images=max_count,
        )
        
        # 更新 markdown 引用
        if archive.get("markdown"):
            parsed.description = archive["markdown"]
        
        # 更新 media_urls
        stored_images = archive.get("stored_images", [])
        if stored_images:
            local_urls = []
            for img in stored_images:
                # 排除头像
                if img.get("type") == "avatar" or img.get("is_avatar"):
                    continue
                if img.get("url"):
                    local_urls.append(img["url"])
                elif img.get("key"):
                    local_urls.append(f"local://{img['key']}")

            if local_urls:
                unique_local_urls = list(dict.fromkeys(local_urls))
                parsed.media_urls = unique_local_urls
                parsed.cover_url = unique_local_urls[0]

            # 同步更新头像
            for img in stored_images:
                if img.get("type") == "avatar" or img.get("is_avatar"):
                    if img.get("url"):
                        parsed.author_avatar_url = img["url"]
                    elif img.get("key"):
                        parsed.author_avatar_url = f"local://{img['key']}"
                    break
            
            # 同步更新 top_answers 中的头像和封面 (知乎问题等)
            top_answers = meta.get("top_answers", [])
            if top_answers:
                # 构建原始URL到存储URL的映射
                url_mapping = {}
                for img in stored_images:
                    orig_url = img.get("orig_url")
                    stored_url = img.get("url") or (f"local://{img['key']}" if img.get("key") else None)
                    if orig_url and stored_url:
                        url_mapping[orig_url] = stored_url
                
                # 更新 top_answers 中的 URL
                for ans in top_answers:
                    if ans.get("author_avatar_url") in url_mapping:
                        ans["author_avatar_url"] = url_mapping[ans["author_avatar_url"]]
                    if ans.get("cover_url") in url_mapping:
                        ans["cover_url"] = url_mapping[ans["cover_url"]]
        
        # 处理视频
        if archive.get("videos"):
            max_videos = getattr(settings, "archive_video_max_count", None)
            await store_archive_videos(
                archive=archive,
                storage=storage,
                namespace=namespace,
                max_videos=max_videos,
            )
            
            stored_videos = archive.get("stored_videos", [])
            if stored_videos:
                for v in stored_videos:
                    v_url = v.get("url") or (f"local://{v['key']}" if v.get("key") else None)
                    if v_url and v_url not in parsed.media_urls:
                        parsed.media_urls.append(v_url)

    async def _handle_archived_media_fix(self, session: AsyncSession, content: Content):
        """补处理归档媒体（针对已解析但未归档的情况）"""
        if not settings.enable_archive_media_processing:
            return

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
                class _ParsedLike:
                    def __init__(self):
                        self.raw_metadata = meta
                        self.cover_url = None
                        self.media_urls = []
                        self.description = None
                        self.author_avatar_url = None

                parsed_like = _ParsedLike()
                await self._maybe_process_private_archive_media(parsed_like)
                
                content.raw_metadata = meta
                if parsed_like.cover_url:
                    content.cover_url = parsed_like.cover_url
                if parsed_like.media_urls:
                    content.media_urls = parsed_like.media_urls
                    
                await session.commit()
                logger.info("补处理归档媒体完成")
            except Exception as e:
                logger.warning("补处理归档媒体失败，跳过: {}", f"{type(e).__name__}: {e}")

    async def retry_parse(self, content_id: int, max_retries: int = 3, delay_seconds: float = 1.0, backoff_factor: float = 2.0, force: bool = False):
        """对外接口：手动触发重试解析"""
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

                    if not force and content.status == ContentStatus.PARSE_SUCCESS:
                        logger.info(f"重试解析：内容已解析完成 {content_id}")
                        return True

                    content.status = ContentStatus.PROCESSING
                    await session.commit()

                    # 复用内部执行逻辑
                    parsed = await self._execute_parse_with_retry(content, 0, 1)
                    await self._update_content(session, content, parsed)
                    
                    logger.info(f"重试解析成功: {content_id} (attempt={attempt})")
                    return True

            except Exception as e:
                logger.warning(f"重试解析第 {attempt} 次失败: {content_id}, err: {e}")
                # 记录错误 (简化版逻辑)
                try:
                    async with AsyncSessionLocal() as session:
                         result = await session.execute(
                            select(Content).where(Content.id == content_id)
                        )
                         content = result.scalar_one_or_none()
                         if content:
                            content.status = ContentStatus.PARSE_FAILED
                            content.last_error = str(e)
                            await session.commit()
                except:
                    pass

                if attempt >= max_retries:
                    return False

                await asyncio.sleep(wait)
                wait = wait * backoff_factor

        return False
