"""
解析任务处理器

处理内容解析、元数据提取、媒体下载等逻辑
"""
import asyncio
import copy
import html
import json
import traceback
from dataclasses import dataclass, field
from typing import Optional, Dict, Any
from urllib.parse import unquote
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm.attributes import flag_modified

from app.core.logging import logger, log_context
from app.core.database import AsyncSessionLocal
from app.core.time_utils import utcnow
from app.models import Content, ContentStatus, Platform, DistributionRule, ReviewStatus
from app.adapters import AdapterFactory
from app.adapters.errors import AdapterError, RetryableAdapterError
from app.core.config import settings
from app.adapters.storage import get_storage_backend
from app.media.extractor import sanitize_media_urls
from app.media.processor import store_archive_images_as_webp, store_archive_videos
from app.media.color import extract_cover_color
from app.core.queue import task_queue
from app.utils.datetime_utils import normalize_datetime_for_db
from app.utils.url_utils import normalize_share_url_input


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
                    parsed, adapter = await self._execute_parse_with_retry(content, attempt, max_attempts)

                    # 更新数据库
                    await self._update_content(session, content, parsed, adapter)
                    
                    # 自动审批检查
                    await self._check_auto_approval(session, content)

                except Exception as e:
                    await self._handle_parse_error(session, content, task_data, e, attempt, max_attempts)
                
                finally:
                    # 标记任务完成
                    await task_queue.mark_complete(content_id)

    async def _execute_parse_with_retry(self, content: Content, current_attempt: int, max_attempts: int) -> tuple[Any, Any]:
        """执行解析逻辑，包含重试机制"""
        parsed = None
        last_err: Exception | None = None
        base_delay = 1.0
        
        remaining_attempts = max(1, max_attempts - current_attempt)
        
        for i in range(remaining_attempts):
            try:
                cookies = await self._get_platform_cookies(content.platform)
                adapter_kwargs = {}
                if content.platform == Platform.ZHIHU:
                    raw_cookie = await self._get_platform_cookie_string(content.platform)
                    if raw_cookie:
                        adapter_kwargs["raw_cookie_str"] = raw_cookie

                adapter = AdapterFactory.create(
                    content.platform,
                    cookies=cookies,
                    **adapter_kwargs,
                )

                normalized_parse_url = normalize_share_url_input(content.url)
                if normalized_parse_url and normalized_parse_url != content.url:
                    logger.info(f"检测到混合分享文案，已修正解析 URL: content_id={content.id}")
                    content.url = normalized_parse_url

                logger.info(f"开始解析内容 (try={current_attempt + i + 1}/{max_attempts})")
                parsed = await adapter.parse(content.url)
                last_err = None
                return parsed, adapter
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

        raise RetryableAdapterError(
            f"解析重试失败，已达到最大次数: {max_attempts}",
            details={"last_error": str(last_err) if last_err else None},
        )

    async def _update_content(self, session: AsyncSession, content: Content, parsed: Any, adapter: Any):
        """更新内容数据到数据库"""
        content.clean_url = parsed.clean_url
        content.content_type = parsed.content_type
        content.layout_type = parsed.layout_type  # 新增: 保存布局类型
        content.title = parsed.title
        content.author_name = parsed.author_name
        content.author_id = parsed.author_id
        content.author_avatar_url = parsed.author_avatar_url
        content.author_url = parsed.author_url
        content.source_tags = parsed.source_tags or []
        content.published_at = normalize_datetime_for_db(parsed.published_at)
        
        # 保存结构化扩展字段
        content.context_data = getattr(parsed, 'context_data', None)
        content.rich_payload = getattr(parsed, 'rich_payload', None)

        # 私有归档媒体处理（可能更新 parsed.body / media_urls / cover_url 等）
        from app.services.settings_service import get_setting_value
        enable_processing = await get_setting_value("enable_archive_media_processing", settings.enable_archive_media_processing)
        if enable_processing:
            try:
                await self._maybe_process_private_archive_media(parsed)
            except Exception as e:
                logger.warning("Archive media processing skipped: {}", f"{type(e).__name__}: {e}")
        
        # 若存档中有 markdown 且解析器未使用，优先用 archive markdown 作为正文
        if not getattr(parsed, '_body_is_markdown', False):
            archive_blob = self._extract_archive_blob(getattr(parsed, 'archive_metadata', None))
            if isinstance(archive_blob, dict) and archive_blob.get("markdown"):
                parsed.body = archive_blob["markdown"]

        # 补充封面颜色（本地 URL 跳过，后续从已存储的图片读取）
        if not getattr(parsed, "cover_color", None) and parsed.cover_url and not parsed.cover_url.startswith("local://"):
            parsed.cover_color = await extract_cover_color(parsed.cover_url)

        # 同步回内容记录（在媒体处理之后，确保拿到更新后的值）
        content.body = parsed.body
        # P2-4: 防止超大正文导致单行数据膨胀
        _MAX_BODY_LEN = 200_000  # 200KB 字符上限
        if content.body and len(content.body) > _MAX_BODY_LEN:
            content.body = content.body[:_MAX_BODY_LEN]
            logger.warning(f"正文超长截断: content_id={content.id}, original_len={len(parsed.body)}")
        content.cover_url = parsed.cover_url
        content.media_urls = sanitize_media_urls(
            parsed.media_urls,
            author_avatar_url=parsed.author_avatar_url,
        )
        content.author_avatar_url = parsed.author_avatar_url
        content.archive_metadata = self._truncate_archive_metadata(
            getattr(parsed, 'archive_metadata', None),
            content.id,
        )
        
        content.cover_color = getattr(parsed, "cover_color", None)
        archive = self._extract_archive_blob(content.archive_metadata)
        if not content.cover_color and isinstance(archive, dict):
            content.cover_color = archive.get("dominant_color")

        # 统一 ID 和互动数据
        content.platform_id = parsed.content_id
        if hasattr(parsed, 'stats') and parsed.stats:
            adapter.map_stats_to_content(content, parsed)

        # 更新状态
        content.status = ContentStatus.PARSE_SUCCESS
        content.last_error = None
        content.last_error_type = None
        content.last_error_detail = None
        content.last_error_at = None

        await session.commit()
        logger.info("内容解析完成")

        # Phase 2: 解析成功后异步建立语义索引（失败不阻断主链路）
        self._schedule_embedding_index(content.id)
        
        # 自动生成摘要
        enable_auto_summary = await get_setting_value("enable_auto_summary", settings.enable_auto_summary)
        from app.services.content_summary_service import generate_summary_for_content
        try:
            if enable_auto_summary:
                await generate_summary_for_content(session, content.id)
                logger.info(f"摘要处理完成: content_id={content.id}, auto_ai={enable_auto_summary}")
            else:
                logger.debug(f"未开启自动摘要生成, 跳过: content_id={content.id}")
        except Exception as e:
            logger.warning(f"摘要生成/处理失败: {e}")

        # 广播更新事件
        from app.core.events import event_bus
        await event_bus.publish("content_updated", {
            "id": content.id,
            "title": content.title,
            "status": content.status.value,
            "platform": content.platform.value if content.platform else None,
            "cover_url": content.cover_url
        })

    def _schedule_embedding_index(self, content_id: int) -> None:
        async def _run():
            try:
                from app.services.embedding_service import EmbeddingService

                await EmbeddingService().index_content(content_id)
            except Exception as e:
                logger.warning("语义索引失败(已忽略): content_id={}, error={}", content_id, e)

        asyncio.create_task(_run())

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
            from app.services.distribution.decision import (
                check_match_conditions,
                DECISION_FILTERED,
            )
            from app.services.distribution.scheduler import enqueue_content

            rules_result = await session.execute(
                select(DistributionRule).where(DistributionRule.enabled == True)
            )
            enabled_rules = rules_result.scalars().all()

            for rule in enabled_rules:
                if rule.approval_required:
                    continue

                decision = check_match_conditions(content, rule.match_conditions or {})
                if decision.bucket == DECISION_FILTERED:
                    continue

                content.review_status = ReviewStatus.AUTO_APPROVED
                content.reviewed_at = utcnow()
                content.review_note = f"Auto-approved (rule: {rule.name})"
                await session.commit()

                await enqueue_content(content.id, session=session)
                logger.info(f"内容已自动审批: content_id={content.id}, rule={rule.name}")
                return
        except Exception as e:
            logger.warning(f"自动审批检查失败: {e}", exc_info=True)

    _MAX_ARCHIVE_METADATA_BYTES = 512 * 1024  # 512KB

    def _extract_archive_blob(self, metadata: Any) -> Dict[str, Any]:
        """从 archive_metadata 中提取可用于媒体处理的 archive 数据。"""
        if not isinstance(metadata, dict):
            return {}
        archive = metadata.get("archive")
        if isinstance(archive, dict):
            return archive
        processed_archive = metadata.get("processed_archive")
        if isinstance(processed_archive, dict):
            return processed_archive
        return {}

    def _truncate_archive_metadata(self, metadata: Any, content_id: int) -> Any:
        """对 archive_metadata 进行大小控制，防止单行数据膨胀。"""
        if not isinstance(metadata, dict):
            return metadata

        try:
            raw = json.dumps(metadata, ensure_ascii=False)
        except (TypeError, ValueError):
            return metadata

        if len(raw.encode("utf-8")) <= self._MAX_ARCHIVE_METADATA_BYTES:
            return metadata

        original_size = len(raw.encode("utf-8"))

        # 阶段 1: 移除已冗余的大字段（archive 中已归档数据的源文件）
        archive = self._extract_archive_blob(metadata)
        if isinstance(archive, dict):
            for key in ("markdown", "html", "raw_html"):
                archive.pop(key, None)
            for img in archive.get("images", []):
                if isinstance(img, dict):
                    img.pop("data", None)
                    img.pop("base64", None)
            for vid in archive.get("videos", []):
                if isinstance(vid, dict):
                    vid.pop("data", None)

        # 阶段 2: 递归裁剪超长字符串值
        def _trim(obj, max_str: int = 2000):
            if isinstance(obj, str) and len(obj) > max_str:
                return obj[:max_str] + f"...[truncated, original {len(obj)} chars]"
            if isinstance(obj, dict):
                return {k: _trim(v, max_str) for k, v in obj.items()}
            if isinstance(obj, list):
                return [_trim(v, max_str) for v in obj]
            return obj

        metadata = _trim(metadata)
        metadata["_truncated"] = True

        final_size = len(json.dumps(metadata, ensure_ascii=False).encode("utf-8"))
        logger.warning(
            f"archive_metadata 超大截断: content_id={content_id}, "
            f"{original_size // 1024}KB → {final_size // 1024}KB"
        )
        return metadata

    def _iter_url_candidates(self, url: str) -> list[str]:
        candidates: list[str] = []
        if not isinstance(url, str) or not url:
            return candidates

        stripped = url.strip()
        if not stripped:
            return candidates
        candidates.append(stripped)

        decoded = unquote(stripped)
        if decoded and decoded not in candidates:
            candidates.append(decoded)

        unescaped = html.unescape(stripped)
        if unescaped and unescaped not in candidates:
            candidates.append(unescaped)

        return candidates

    def _map_url_with_mapping(self, url: Any, url_mapping: Dict[str, str]) -> Optional[str]:
        if not isinstance(url, str) or not url_mapping:
            return None
        for candidate in self._iter_url_candidates(url):
            mapped = url_mapping.get(candidate)
            if isinstance(mapped, str) and mapped:
                return mapped
        return None

    def _build_stored_image_mapping(self, archive: Dict[str, Any]) -> Dict[str, str]:
        """从 archive 中构建原图 URL -> 本地可访问 URL 的映射。"""
        mapping: Dict[str, str] = {}

        def _add_mapping(orig_url: Any, mapped_url: Any) -> None:
            if not isinstance(orig_url, str) or not isinstance(mapped_url, str):
                return
            orig = orig_url.strip()
            mapped = mapped_url.strip()
            if not orig or not mapped:
                return
            if orig.startswith("local://"):
                return
            mapping[orig] = mapped

        stored_images = archive.get("stored_images")
        if isinstance(stored_images, list):
            for img in stored_images:
                if not isinstance(img, dict):
                    continue
                orig_url = img.get("orig_url") or img.get("source_url") or img.get("url")
                key = img.get("key") or img.get("stored_key")
                mapped_url = f"local://{key}" if isinstance(key, str) and key else img.get("url") or img.get("stored_url")
                _add_mapping(orig_url, mapped_url)

        # 回退：有些历史数据只在 images 中带了 stored_key。
        images = archive.get("images")
        if isinstance(images, list):
            for img in images:
                if not isinstance(img, dict):
                    continue
                orig_url = img.get("url")
                key = img.get("stored_key")
                mapped_url = f"local://{key}" if isinstance(key, str) and key else img.get("stored_url")
                _add_mapping(orig_url, mapped_url)

        return mapping

    def _rewrite_text_with_mapping(self, text: Optional[str], url_mapping: Dict[str, str]) -> Optional[str]:
        if not isinstance(text, str) or not text or not url_mapping:
            return text

        rewritten = text
        for orig_url, mapped_url in url_mapping.items():
            for candidate in self._iter_url_candidates(orig_url):
                rewritten = rewritten.replace(f"({candidate})", f"({mapped_url})")
                rewritten = rewritten.replace(candidate, mapped_url)
        return rewritten

    def _apply_stored_mapping_to_record(self, record: Any, archive: Dict[str, Any]) -> bool:
        """将 archive 的已存储映射回写到正文/封面/头像/媒体字段。"""
        url_mapping = self._build_stored_image_mapping(archive)
        if not url_mapping:
            return False

        changed = False

        body = getattr(record, "body", None)
        rewritten_body = self._rewrite_text_with_mapping(body, url_mapping)
        if isinstance(rewritten_body, str) and rewritten_body != body:
            record.body = rewritten_body
            changed = True

        cover_url = getattr(record, "cover_url", None)
        mapped_cover = self._map_url_with_mapping(cover_url, url_mapping)
        if mapped_cover and mapped_cover != cover_url:
            record.cover_url = mapped_cover
            changed = True

        avatar_url = getattr(record, "author_avatar_url", None)
        mapped_avatar = self._map_url_with_mapping(avatar_url, url_mapping)
        if mapped_avatar and mapped_avatar != avatar_url:
            record.author_avatar_url = mapped_avatar
            changed = True

        media_urls = getattr(record, "media_urls", None)
        if isinstance(media_urls, list) and media_urls:
            mapped_media: list[str] = []
            media_changed = False
            for media_url in media_urls:
                mapped = self._map_url_with_mapping(media_url, url_mapping) or media_url
                if mapped != media_url:
                    media_changed = True
                if isinstance(mapped, str):
                    mapped_media.append(mapped)
            if media_changed:
                record.media_urls = mapped_media
                changed = True

        rich_payload = getattr(record, "rich_payload", None)
        blocks = rich_payload.get("blocks") if isinstance(rich_payload, dict) else None
        if isinstance(blocks, list):
            payload_changed = False
            for block in blocks:
                if not isinstance(block, dict):
                    continue
                data = block.get("data")
                if not isinstance(data, dict):
                    continue
                if isinstance(data.get("author_avatar_url"), str):
                    mapped = self._map_url_with_mapping(data["author_avatar_url"], url_mapping)
                    if mapped and mapped != data["author_avatar_url"]:
                        data["author_avatar_url"] = mapped
                        payload_changed = True
                if isinstance(data.get("cover_url"), str):
                    mapped = self._map_url_with_mapping(data["cover_url"], url_mapping)
                    if mapped and mapped != data["cover_url"]:
                        data["cover_url"] = mapped
                        payload_changed = True
            if payload_changed:
                changed = True

        return changed

    async def _get_platform_cookies(self, platform: Platform) -> dict:
        """获取平台 cookies（优先从数据库 settings 读取，回退到 .env 配置）"""
        from app.services.settings_service import get_setting_value_fresh

        if platform == Platform.BILIBILI:
            cookies = {}
            if settings.bilibili_sessdata:
                cookies['SESSDATA'] = settings.bilibili_sessdata.get_secret_value()
            if settings.bilibili_bili_jct:
                cookies['bili_jct'] = settings.bilibili_bili_jct.get_secret_value()
            if settings.bilibili_buvid3:
                cookies['buvid3'] = settings.bilibili_buvid3.get_secret_value()
            return cookies

        # 通过扫码登录保存的平台 cookie（存储在数据库 settings 表中）
        # 支持：知乎、微博、小红书等
        platform_name = platform.value  # 例如 "zhihu"、"weibo"、"xiaohongshu"
        cookie_str = await get_setting_value_fresh(f"{platform_name}_cookie")
        if not cookie_str:
            # 对于知乎，还可以回退到 .env 中的 ZHIHU_COOKIE
            if platform == Platform.ZHIHU and settings.zhihu_cookie:
                cookie_str = settings.zhihu_cookie.get_secret_value()
            else:
                return {}

        # 将 cookie 字符串解析为字典（复用基类工具）
        from app.adapters.base import PlatformAdapter
        return PlatformAdapter.parse_cookie_str(cookie_str)

    async def _get_platform_cookie_string(self, platform: Platform) -> Optional[str]:
        """获取平台原始 cookie 串（用于需要直传 Cookie 头的平台）。"""
        from app.services.settings_service import get_setting_value_fresh

        platform_name = platform.value
        cookie_str = await get_setting_value_fresh(f"{platform_name}_cookie")
        if cookie_str:
            return cookie_str

        if platform == Platform.ZHIHU and settings.zhihu_cookie:
            return settings.zhihu_cookie.get_secret_value()
        return None

    async def _maybe_process_private_archive_media(self, parsed) -> None:
        """处理私有归档媒体"""
        meta = getattr(parsed, "archive_metadata", None)
        if not isinstance(meta, dict):
            return

        archive = self._extract_archive_blob(meta)
        if not isinstance(archive, dict):
            return

        storage = get_storage_backend()
        
        # MinIO/S3: 确保bucket存在
        ensure_bucket = getattr(storage, "ensure_bucket", None)
        if callable(ensure_bucket):
            await ensure_bucket()

        namespace = "vaultstream"
        from app.services.settings_service import get_setting_value
        quality = int(await get_setting_value("archive_image_webp_quality", settings.archive_image_webp_quality) or 80)
        max_count = await get_setting_value("archive_image_max_count", settings.archive_image_max_count)
        if max_count is not None:
            max_count = int(max_count)

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
            parsed.body = archive["markdown"]

        # 基于已存储映射修正正文/封面/头像等字段（兼容历史数据已存储但正文未改写场景）
        self._apply_stored_mapping_to_record(parsed, archive)
        
        # 更新 media_urls — 优先使用本地 local:// 协议
        stored_images = archive.get("stored_images", [])
        if stored_images:
            local_urls = []
            for img in stored_images:
                # 排除头像和非内容相关的图片（如知乎精选回答的头像与配图）
                img_type = img.get("type")
                if img_type and img_type not in ("image", "gallery", "cover"):
                    continue
                if img.get("is_avatar"):
                    continue
                # 优先使用 local:// 协议（内容寻址存储），回退到远程 url
                if img.get("key"):
                    local_urls.append(f"local://{img['key']}")
                elif img.get("url"):
                    local_urls.append(img["url"])

            if local_urls:
                unique_local_urls = list(dict.fromkeys(local_urls))
                parsed.media_urls = unique_local_urls

            # 构建原始URL到存储URL的映射
            url_mapping = {}
            for img in stored_images:
                orig_url = img.get("orig_url") or img.get("url")
                stored_url = f"local://{img['key']}" if img.get("key") else img.get("url")
                if orig_url and stored_url:
                    url_mapping[orig_url] = stored_url

            # 同步更新封面
            for img in stored_images:
                stored_url = f"local://{img['key']}" if img.get("key") else img.get("url")
                if stored_url and img.get("type") == "cover":
                    parsed.cover_url = stored_url
                    break
            
            # 如果没有明确的 cover_url，回退映射
            if parsed.cover_url and not parsed.cover_url.startswith("local://"):
                if parsed.cover_url in url_mapping:
                    parsed.cover_url = url_mapping[parsed.cover_url]
            # 如果依然为空，取 local_urls 第一张
            if not parsed.cover_url and local_urls:
                parsed.cover_url = local_urls[0]

            # 同步更新头像
            for img in stored_images:
                stored_url = f"local://{img['key']}" if img.get("key") else img.get("url")
                if stored_url and (img.get("type") == "avatar" or img.get("is_avatar")):
                    parsed.author_avatar_url = stored_url
                    break
            
            # 如果没有明确的 avatar，回退映射
            if parsed.author_avatar_url and not parsed.author_avatar_url.startswith("local://"):
                if parsed.author_avatar_url in url_mapping:
                    parsed.author_avatar_url = url_mapping[parsed.author_avatar_url]
            
            # 同步更新 rich_payload 子项中的头像和封面（如知乎问题精选回答）
            payload = getattr(parsed, "rich_payload", None)
            blocks = payload.get("blocks") if isinstance(payload, dict) else []
            if isinstance(blocks, list) and blocks:
                # 构建原始URL到存储URL的映射
                url_mapping = {}
                for img in stored_images:
                    orig_url = img.get("orig_url")
                    stored_url = img.get("url") or (f"local://{img['key']}" if img.get("key") else None)
                    if orig_url and stored_url:
                        url_mapping[orig_url] = stored_url
                
                # 更新 rich_payload blocks 中的 URL
                for block in blocks:
                    if not isinstance(block, dict):
                        continue
                    data = block.get("data")
                    if not isinstance(data, dict):
                        continue
                    if data.get("author_avatar_url") in url_mapping:
                        data["author_avatar_url"] = url_mapping[data["author_avatar_url"]]
                    if data.get("cover_url") in url_mapping:
                        data["cover_url"] = url_mapping[data["cover_url"]]
        
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
        from app.services.settings_service import get_setting_value
        enable_processing = await get_setting_value("enable_archive_media_processing", settings.enable_archive_media_processing)
        if not enable_processing:
            return

        meta = content.archive_metadata
        archive = self._extract_archive_blob(meta)
        images = archive.get("images") if isinstance(archive, dict) else None
        
        need_media = False
        if isinstance(images, list) and images:
            for img in images:
                if isinstance(img, dict) and img.get("url") and not img.get("stored_key"):
                    need_media = True
                    break

        need_reference_fix = False
        if isinstance(archive, dict):
            url_mapping = self._build_stored_image_mapping(archive)
            if url_mapping:
                if self._rewrite_text_with_mapping(content.body, url_mapping) != content.body:
                    need_reference_fix = True
                elif self._map_url_with_mapping(content.cover_url, url_mapping):
                    need_reference_fix = True
                elif self._map_url_with_mapping(content.author_avatar_url, url_mapping):
                    need_reference_fix = True
                elif isinstance(content.media_urls, list) and any(
                    self._map_url_with_mapping(u, url_mapping) for u in content.media_urls
                ):
                    need_reference_fix = True

        if need_media or need_reference_fix:
            if need_media:
                logger.info("内容已解析完成，但存在未处理图片；开始补处理归档媒体")
            else:
                logger.info("内容已解析完成，检测到历史远程引用；开始回写本地映射")
            try:
                @dataclass
                class _ParsedLike:
                    # 保持与 _maybe_process_private_archive_media 依赖字段一致，
                    # 避免后续扩展时因 mock 字段缺失引发隐藏错误。
                    archive_metadata: Dict[str, Any]
                    rich_payload: Optional[Dict[str, Any]] = None
                    cover_url: Optional[str] = None
                    media_urls: list[str] = field(default_factory=list)
                    body: Optional[str] = None
                    author_avatar_url: Optional[str] = None

                parsed_like = _ParsedLike(
                    archive_metadata=meta,
                    rich_payload=content.rich_payload if isinstance(content.rich_payload, dict) else None,
                    cover_url=content.cover_url,
                    media_urls=list(content.media_urls) if isinstance(content.media_urls, list) else [],
                    body=content.body,
                    author_avatar_url=content.author_avatar_url,
                )
                if need_media:
                    await self._maybe_process_private_archive_media(parsed_like)
                else:
                    self._apply_stored_mapping_to_record(parsed_like, archive)
                
                content.archive_metadata = meta
                if parsed_like.body:
                    content.body = parsed_like.body
                if parsed_like.cover_url:
                    content.cover_url = parsed_like.cover_url
                if parsed_like.author_avatar_url:
                    content.author_avatar_url = parsed_like.author_avatar_url
                if isinstance(parsed_like.rich_payload, dict):
                    # 需要新对象触发 ORM 脏检查，避免 JSON 原地修改不落库。
                    content.rich_payload = copy.deepcopy(parsed_like.rich_payload)
                    flag_modified(content, "rich_payload")
                if parsed_like.media_urls:
                    content.media_urls = sanitize_media_urls(
                        parsed_like.media_urls,
                        author_avatar_url=parsed_like.author_avatar_url or content.author_avatar_url,
                    )
                    
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
                    parsed, adapter = await self._execute_parse_with_retry(content, 0, 1)
                    await self._update_content(session, content, parsed, adapter)
                    
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
