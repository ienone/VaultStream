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
from app.models import Content, ContentStatus, Platform
from app.adapters import close_adapter
from app.adapters.errors import AdapterError, RetryableAdapterError
from app.adapters.storage import get_storage_backend
from app.media.extractor import sanitize_media_urls
from app.media.processor import store_archive_images_as_webp, store_archive_videos
from app.media.color import extract_cover_color
from app.core.queue import task_queue
from app.utils.datetime_utils import normalize_datetime_for_db
from app.utils.url_utils import normalize_share_url_input
from app.services.post_ingest import PostIngestService
from app.services.config_service import ConfigService
from app.services.settings_service import get_setting_value
from app.services.media_backfill import replace_content_media_assets
from app.services.platform_parsing import create_configured_adapter
from app.services.background_task_state import (
    record_task_run_error,
    record_task_run_started,
    record_task_run_success,
)


@dataclass(frozen=True)
class ParseExecutionResult:
    found: bool
    skipped: bool
    reason: str | None = None
    status: str | None = None
    title: str | None = None


class ContentParser:
    """内容解析器"""

    async def process_parse_task(
        self,
        task_data: dict,
        task_id: str,
        *,
        task_db_id: int,
    ) -> None:
        """处理解析任务"""
        schema_version = int(task_data.get("schema_version") or 1)
        action = task_data.get("action") or "parse"
        attempt = int(task_data.get("attempt") or 0)
        max_attempts = int(task_data.get("max_attempts") or 3)
        content_id = task_data.get('content_id')
        
        if not content_id:
            logger.warning("任务数据缺少 content_id")
            await task_queue.mark_failed(task_db_id, reason="missing_content_id")
            return

        run = await record_task_run_started(
            "content_parse",
            trigger="queue",
            content_id=content_id,
            task_id=task_id,
            action=action,
            attempt=attempt,
            max_attempts=max_attempts,
            schema_version=schema_version,
        )
        run_id = run["run_id"]
        
        with log_context(task_id=task_id, content_id=content_id):
            try:
                logger.info(
                    f"开始处理任务: schema={schema_version}, action={action}, "
                    f"attempt={attempt}/{max_attempts}"
                )
                result = await self.execute_parse(
                    content_id,
                    action=action,
                    current_attempt=attempt,
                    max_attempts=max_attempts,
                    force=False,
                )
                if not await task_queue.mark_complete(task_db_id):
                    raise RuntimeError(
                        f"parse task settlement failed: task_db_id={task_db_id}"
                    )
                await record_task_run_success(
                    "content_parse",
                    run_id,
                    trigger="queue",
                    content_id=content_id,
                    task_id=task_id,
                    task_db_id=task_db_id,
                    action=action,
                    skipped=result.skipped,
                    reason=result.reason,
                    status=result.status,
                    title=result.title,
                )
            except asyncio.CancelledError:
                await task_queue.mark_failed(task_db_id, reason="cancelled")
                await record_task_run_error(
                    "content_parse",
                    run_id,
                    "Parsing cancelled",
                    trigger="queue",
                    content_id=content_id,
                    task_id=task_id,
                    task_db_id=task_db_id,
                    action=action,
                    error_type="CancelledError",
                )
                raise
            except Exception as e:
                reason = self._task_failure_reason(e)
                await task_queue.mark_failed(
                    task_db_id,
                    reason=f"{reason}: {type(e).__name__}: {e}",
                )
                await record_task_run_error(
                    "content_parse",
                    run_id,
                    e,
                    trigger="queue",
                    content_id=content_id,
                    task_id=task_id,
                    task_db_id=task_db_id,
                    action=action,
                    attempt=attempt,
                    max_attempts=max_attempts,
                    error_type=type(e).__name__,
                    reason=reason,
                )

    async def execute_parse(
        self,
        content_id: int,
        *,
        action: str = "parse",
        current_attempt: int = 0,
        max_attempts: int = 3,
        force: bool = False,
    ) -> ParseExecutionResult:
        """Execute the single parse/retry path without queue settlement."""
        async with AsyncSessionLocal() as session:
            result = await session.execute(select(Content).where(Content.id == content_id))
            content = result.scalar_one_or_none()
            if content is None:
                logger.warning(f"内容不存在: {content_id}")
                return ParseExecutionResult(
                    found=False,
                    skipped=True,
                    reason="content_not_found",
                )

            if not force and action == "parse" and content.status == ContentStatus.PARSE_SUCCESS:
                await self._handle_archived_media_fix(session, content)
                logger.info("内容已解析完成，跳过解析")
                return ParseExecutionResult(
                    found=True,
                    skipped=True,
                    reason="already_parse_success",
                    status=content.status.value,
                    title=content.title,
                )

            content.status = ContentStatus.PROCESSING
            await session.commit()

            adapter = None
            try:
                parsed, adapter = await self._execute_parse_with_retry(
                    content,
                    current_attempt,
                    max_attempts,
                )
                await self._update_content(session, content, parsed, adapter)
                await self._check_auto_approval(session, content)
            except asyncio.CancelledError:
                await self._record_parse_error(
                    session,
                    content,
                    RuntimeError("Parsing cancelled"),
                )
                raise
            except Exception as error:
                await self._record_parse_error(session, content, error)
                raise
            finally:
                await close_adapter(adapter)

            return ParseExecutionResult(
                found=True,
                skipped=False,
                status=content.status.value if content.status else None,
                title=content.title,
            )

    async def _execute_parse_with_retry(self, content: Content, current_attempt: int, max_attempts: int) -> tuple[Any, Any]:
        """执行解析逻辑，包含重试机制"""
        parsed = None
        last_err: Exception | None = None
        base_delay = 1.0
        
        remaining_attempts = max(1, max_attempts - current_attempt)
        
        for i in range(remaining_attempts):
            adapter = None
            try:
                adapter = await create_configured_adapter(content.platform)

                normalized_parse_url = normalize_share_url_input(content.url)
                if normalized_parse_url and normalized_parse_url != content.url:
                    logger.info(f"检测到混合分享文案，已修正解析 URL: content_id={content.id}")
                    content.url = normalized_parse_url

                logger.info(f"开始解析内容 (try={current_attempt + i + 1}/{max_attempts})")
                parsed = await adapter.parse(content.url)
                last_err = None
                return parsed, adapter
            except AdapterError as e:
                await close_adapter(adapter)
                last_err = e
                if not e.retryable:
                    raise
                # retryable: sleep and continue
                delay = base_delay * (2 ** (current_attempt + i))
                logger.warning(f"可重试错误，{delay:.1f}s 后重试: {e}")
                await asyncio.sleep(delay)
            except Exception as e:
                await close_adapter(adapter)
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
        content.author_id = parsed.author_id
        content.author_avatar_url = parsed.author_avatar_url
        content.author_url = parsed.author_url
        content.source_tags = parsed.source_tags or []
        content.published_at = normalize_datetime_for_db(parsed.published_at)
        
        # 保存结构化扩展字段
        content.context_data = getattr(parsed, 'context_data', None)
        content.rich_payload = getattr(parsed, 'rich_payload', None)

        # 私有归档媒体处理（可能更新 parsed.body / media_urls / cover_url 等）
        archive_config = await ConfigService().get_archive_media_config()
        if archive_config.enabled:
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
        # P2-4: 防止超大正文导致单行数据膨胀
        _MAX_BODY_LEN = 200_000  # 200KB 字符上限
        parsed_body = parsed.body
        if parsed_body and len(parsed_body) > _MAX_BODY_LEN:
            parsed_body = parsed_body[:_MAX_BODY_LEN]
            logger.warning(f"正文超长截断: content_id={content.id}, original_len={len(parsed.body)}")

        parsed_fields = {
            "title": parsed.title,
            "body": parsed_body,
            "author_name": parsed.author_name,
            "cover_url": parsed.cover_url,
        }
        manual_fields = set(content.manual_edit_fields or [])
        conflicting_fields: dict[str, Any] = {}
        for field_name, parsed_value in parsed_fields.items():
            if field_name in manual_fields and getattr(content, field_name) != parsed_value:
                conflicting_fields[field_name] = parsed_value
            else:
                setattr(content, field_name, parsed_value)
        content.parse_candidate = (
            {
                "created_at": utcnow().isoformat(),
                "fields": conflicting_fields,
            }
            if conflicting_fields
            else None
        )

        content.media_urls = sanitize_media_urls(
            parsed.media_urls,
            author_avatar_url=parsed.author_avatar_url,
        )
        content.author_avatar_url = parsed.author_avatar_url
        content.archive_metadata = self._truncate_archive_metadata(
            getattr(parsed, 'archive_metadata', None),
            content.id,
        )
        
        if "cover_url" not in conflicting_fields:
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

        # 解析结果是媒体事实的写入边界。每次完整解析后在同一事务内重建
        # 该内容的资产/变体，避免继续双写旧 URL 与新表。
        await replace_content_media_assets(
            session,
            content,
            get_storage_backend(),
            source="parse",
        )

        await session.commit()
        logger.info("内容解析完成")

        await PostIngestService().run_for_content(
            session,
            content,
            source="parse",
            summary=True,
            embedding=True,
            patrol=False,
            distribution=False,
        )

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
        PostIngestService().schedule_embedding_index(content_id)

    async def _record_parse_error(self, session, content, error) -> None:
        """Record content failure; queue settlement is owned by the caller."""
        logger.error(f"处理任务失败: content_id={content.id}, 错误: {error}")
        
        # 更新数据库中的失败状态
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

        try:
            from app.core.events import event_bus
            await event_bus.publish("content_updated", {
                "id": content.id,
                "status": ContentStatus.PARSE_FAILED.value,
                "error": str(error)
            })
        except Exception:
            pass

    @staticmethod
    def _task_failure_reason(error: Exception) -> str:
        if isinstance(error, AdapterError) and error.auth_required:
            return "auth_required"
        if isinstance(error, AdapterError) and not error.retryable:
            return "non_retryable"
        if isinstance(error, RetryableAdapterError):
            return "max_attempts_reached"
        return "failed"

    async def _check_auto_approval(self, session, content):
        """M4: 解析完成后尝试自动审批"""
        await PostIngestService().auto_approve_and_enqueue(session, content)

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
        archive_config = await ConfigService().get_archive_media_config()

        # 处理图片
        if archive_config.images_enabled:
            await store_archive_images_as_webp(
                archive=archive,
                storage=storage,
                namespace=namespace,
                quality=archive_config.image_webp_quality,
                max_images=archive_config.image_max_count,
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
        if archive_config.videos_enabled and archive.get("videos"):
            await store_archive_videos(
                archive=archive,
                storage=storage,
                namespace=namespace,
                max_videos=archive_config.video_max_count,
                max_bytes=archive_config.video_max_bytes,
            )
            
            stored_videos = archive.get("stored_videos", [])
            if stored_videos:
                for v in stored_videos:
                    v_url = v.get("url") or (f"local://{v['key']}" if v.get("key") else None)
                    if v_url and v_url not in parsed.media_urls:
                        parsed.media_urls.append(v_url)

    async def _handle_archived_media_fix(self, session: AsyncSession, content: Content):
        """补处理归档媒体（针对已解析但未归档的情况）"""
        archive_config = await ConfigService().get_archive_media_config()
        if not archive_config.enabled:
            return

        meta = content.archive_metadata
        archive = self._extract_archive_blob(meta)
        images = archive.get("images") if isinstance(archive, dict) else None
        videos = archive.get("videos") if isinstance(archive, dict) else None

        def _has_unstored_media(items: Any) -> bool:
            return isinstance(items, list) and any(
                isinstance(item, dict)
                and item.get("url")
                and not item.get("stored_key")
                for item in items
            )

        need_images = archive_config.images_enabled and _has_unstored_media(images)
        need_videos = archive_config.videos_enabled and _has_unstored_media(videos)
        need_media = need_images or need_videos

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
                media_types = "图片和视频" if need_images and need_videos else "图片" if need_images else "视频"
                logger.info("内容已解析完成，但存在未处理{}；开始补处理归档媒体", media_types)
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
                flag_modified(content, "archive_metadata")
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

    async def retry_parse(
        self,
        content_id: int,
        max_retries: int = 3,
        force: bool = False,
    ) -> bool:
        """Manual transport for the same parser and retry classifier as the queue."""
        try:
            result = await self.execute_parse(
                content_id,
                action="parse",
                current_attempt=0,
                max_attempts=max_retries,
                force=force,
            )
            return result.found
        except Exception as error:
            logger.warning(f"重试解析失败: {content_id}, err: {error}")
            return False
