"""
解析任务处理器

处理内容解析、元数据提取、媒体下载等逻辑
"""
import asyncio
import json
import traceback
from dataclasses import dataclass
from typing import Optional, Dict, Any
from sqlalchemy import String, cast, select, update
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.logging import logger, log_context
from app.core.database import AsyncSessionLocal
from app.core.time_utils import utcnow
from app.models import Content, ContentStatus, Platform, Task, TaskStatus
from app.adapters import close_adapter
from app.adapters.errors import AdapterError, RetryableAdapterError
from app.adapters.storage import get_storage_backend
from app.media.extractor import sanitize_media_urls
from app.media.processor import store_archive_images, store_archive_videos
from app.media.color import extract_cover_color
from app.media.references import apply_archive_media
from app.core.queue import task_queue
from app.core.queue_adapter import TaskQueue
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
        claimed_task: Task,
    ) -> None:
        """处理解析任务"""
        content_id = task_data.get('content_id')
        
        if not content_id:
            logger.warning("任务数据缺少 content_id")
            await task_queue.mark_failed(claimed_task, reason="missing_content_id")
            return

        run = await record_task_run_started(
            "content_parse",
            trigger="queue",
            content_id=content_id,
            task_id=task_id,
        )
        run_id = run["run_id"]
        
        with log_context(task_id=task_id, content_id=content_id):
            try:
                result = await asyncio.wait_for(
                    self.execute_parse(content_id, claimed_task=claimed_task),
                    timeout=TaskQueue.EXECUTION_TIMEOUT.total_seconds(),
                )
                await record_task_run_success(
                    "content_parse",
                    run_id,
                    trigger="queue",
                    content_id=content_id,
                    task_id=task_id,
                    task_db_id=claimed_task.id,
                    skipped=result.skipped,
                    reason=result.reason,
                    status=result.status,
                    title=result.title,
                )
            except asyncio.CancelledError:
                await self._settle_parse_error(content_id, claimed_task, RuntimeError("Parsing cancelled"), "cancelled")
                await record_task_run_error(
                    "content_parse",
                    run_id,
                    "Parsing cancelled",
                    trigger="queue",
                    content_id=content_id,
                    task_id=task_id,
                    task_db_id=claimed_task.id,
                    error_type="CancelledError",
                )
                raise
            except Exception as e:
                reason = self._task_failure_reason(e)
                await self._settle_parse_error(
                    content_id, claimed_task, e,
                    f"{reason}: {type(e).__name__}: {e}",
                )
                await record_task_run_error(
                    "content_parse",
                    run_id,
                    e,
                    trigger="queue",
                    content_id=content_id,
                    task_id=task_id,
                    task_db_id=claimed_task.id,
                    error_type=type(e).__name__,
                    reason=reason,
                )

    async def execute_parse(
        self,
        content_id: int,
        *,
        force: bool = False,
        claimed_task: Task | None = None,
    ) -> ParseExecutionResult:
        """Execute one parse path and atomically settle claimed parse results."""
        async with AsyncSessionLocal() as session:
            if claimed_task is not None:
                if not await task_queue.owns(session, claimed_task):
                    await session.rollback()
                    raise RuntimeError("parse task already settled")
            else:
                await session.execute(update(Content).where(
                    Content.id == content_id,
                ).values(id=Content.id))
            result = await session.execute(select(Content).where(Content.id == content_id))
            content = result.scalar_one_or_none()
            if content is None or content.deleted_at is not None:
                logger.warning(f"内容不存在: {content_id}")
                skipped = ParseExecutionResult(
                    found=False,
                    skipped=True,
                    reason="content_deleted" if content is not None else "content_not_found",
                )
                if claimed_task is not None and not await task_queue.mark_complete(claimed_task, session=session):
                    raise RuntimeError("parse task already settled")
                await session.commit()
                return skipped

            if not force and content.status == ContentStatus.PARSE_SUCCESS:
                logger.info("内容已解析完成，跳过解析")
                skipped = ParseExecutionResult(
                    found=True,
                    skipped=True,
                    reason="already_parse_success",
                    status=content.status.value,
                    title=content.title,
                )
                if claimed_task is not None and not await task_queue.mark_complete(claimed_task, session=session):
                    raise RuntimeError("parse task already settled")
                await session.commit()
                return skipped

            content.status = ContentStatus.PROCESSING
            await session.commit()

            adapter = None
            try:
                adapter = await create_configured_adapter(content.platform)
                parse_url = normalize_share_url_input(content.url) or content.url
                parsed = await adapter.parse(parse_url)
                return await self._update_content(
                    session, content, parsed, adapter, claimed_task=claimed_task,
                )
            except asyncio.CancelledError:
                if claimed_task is None:
                    await self._record_parse_error(session, content_id, RuntimeError("Parsing cancelled"))
                raise
            except Exception as error:
                if claimed_task is None:
                    await self._record_parse_error(session, content_id, error)
                raise
            finally:
                await close_adapter(adapter)

    async def _update_content(
        self, session: AsyncSession, content: Content, parsed: Any, adapter: Any,
        *, claimed_task: Task | None = None,
    ) -> ParseExecutionResult:
        """更新内容数据到数据库"""
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

        # 未在归档中取得颜色时，复用本地图片或读取远程封面
        if not getattr(parsed, "cover_color", None) and parsed.cover_url:
            parsed.cover_color = await extract_cover_color(parsed.cover_url)

        # Network/media preparation is complete. Re-read current user fields and
        # acquire SQLite's write lock before changing persistent facts.
        content_id = content.id
        with session.no_autoflush:
            if claimed_task is not None:
                owns_write_lock = await task_queue.owns(session, claimed_task)
            else:
                lock = await session.execute(
                    update(Content)
                    .where(Content.id == content_id)
                    .values(id=Content.id)
                )
                owns_write_lock = lock.rowcount == 1
        if not owns_write_lock:
            await session.rollback()
            if claimed_task is not None:
                raise RuntimeError("parse task already settled")
            return ParseExecutionResult(found=False, skipped=True, reason="content_not_found")

        session.expire_all()
        content = await session.get(Content, content_id)
        if content is None or content.deleted_at is not None:
            reason = "content_deleted" if content is not None else "content_not_found"
            if claimed_task is not None:
                if not await task_queue.mark_complete(claimed_task, session=session):
                    raise RuntimeError("parse task already settled")
                await session.commit()
            else:
                await session.rollback()
            return ParseExecutionResult(found=False, skipped=True, reason=reason)

        content.resolved_url = parsed.clean_url if parsed.clean_url != content.canonical_url else None
        content.content_type = parsed.content_type
        content.layout_type = parsed.layout_type
        content.author_id = parsed.author_id
        content.author_avatar_url = parsed.author_avatar_url
        content.author_url = parsed.author_url
        content.source_tags = parsed.source_tags or []
        content.published_at = normalize_datetime_for_db(parsed.published_at)
        content.context_data = getattr(parsed, 'context_data', None)
        content.rich_payload = getattr(parsed, 'rich_payload', None)

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

        if claimed_task is not None and not await task_queue.mark_complete(claimed_task, session=session):
            await session.rollback()
            raise RuntimeError("parse task already settled")

        await session.commit()
        logger.info("内容解析完成")

        execution_result = ParseExecutionResult(
            found=True,
            skipped=False,
            status=ContentStatus.PARSE_SUCCESS.value,
            title=content.title,
        )

        await PostIngestService().run_for_content(
            session,
            content,
            source="parse",
            summary=True,
            embedding=True,
            patrol=False,
            distribution=False,
        )
        await self._check_auto_approval(session, content)

        # 广播更新事件
        from app.core.events import event_bus
        await event_bus.publish("content_updated", {
            "id": content.id,
            "title": content.title,
            "status": content.status.value,
            "platform": content.platform.value if content.platform else None,
            "cover_url": content.cover_url
        })
        return execution_result

    async def _settle_parse_error(
        self, content_id: int, claim: Task, error: Exception, reason: str,
    ) -> bool:
        """Fence content failure and queue failure in one short transaction."""
        async with AsyncSessionLocal() as session:
            if not await task_queue.owns(session, claim):
                await session.rollback()
                return False
            content = await session.get(Content, content_id)
            other_running = (await session.execute(
                select(Task.id).where(
                    Task.id != claim.id,
                    Task.status == TaskStatus.RUNNING,
                    cast(Task.payload["content_id"], String) == str(content_id),
                ).limit(1)
            )).first() is not None
            if (
                content is not None
                and content.deleted_at is None
                and content.status != ContentStatus.PARSE_SUCCESS
                and not other_running
            ):
                self._apply_parse_error(content, error)
            changed = await task_queue.mark_failed(claim, reason=reason, session=session)
            if changed:
                await session.commit()
            else:
                await session.rollback()
            return changed

    @staticmethod
    def _apply_parse_error(content: Content, error: Exception) -> None:
        content.status = ContentStatus.PARSE_FAILED
        content.failure_count = (content.failure_count or 0) + 1
        content.last_error = str(error)
        content.last_error_type = type(error).__name__
        content.last_error_detail = {"message": str(error)}
        content.last_error_at = utcnow()

    async def _record_parse_error(self, session, content_id: int, error) -> None:
        """Record content failure; queue settlement is owned by the caller."""
        logger.error(f"处理任务失败: content_id={content_id}, 错误: {error}")

        await session.rollback()
        await session.execute(update(Content).where(
            Content.id == content_id,
        ).values(id=Content.id))
        content = await session.get(Content, content_id)
        if content is None or content.deleted_at is not None or content.status == ContentStatus.PARSE_SUCCESS:
            return
        self._apply_parse_error(content, error)
        content.last_error_detail = {
            "message": str(error),
            "traceback": traceback.format_exc(limit=50),
        }
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
            return "adapter_error"
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

    async def _maybe_process_private_archive_media(self, parsed) -> None:
        """处理私有归档媒体"""
        meta = getattr(parsed, "archive_metadata", None)
        if not isinstance(meta, dict):
            return

        archive = self._extract_archive_blob(meta)
        if not isinstance(archive, dict):
            return

        storage = get_storage_backend()
        
        namespace = "vaultstream"
        archive_config = await ConfigService().get_archive_media_config()

        # 处理图片
        if archive_config.images_enabled:
            await store_archive_images(
                archive=archive,
                storage=storage,
                namespace=namespace,
                quality=archive_config.image_webp_quality,
                max_images=archive_config.image_max_count,
            )
        
        if archive_config.videos_enabled:
            await store_archive_videos(
                archive=archive, storage=storage, namespace=namespace,
                max_videos=archive_config.video_max_count,
                max_bytes=archive_config.video_max_bytes,
            )
        if archive.get("markdown"):
            parsed.body = archive["markdown"]
        apply_archive_media(parsed, archive)

    async def retry_parse(
        self,
        content_id: int,
        force: bool = False,
    ) -> bool:
        """用户主动重新解析一次，不循环重复相同方案。"""
        try:
            result = await self.execute_parse(content_id, force=force)
            return result.found
        except Exception as error:
            logger.warning(f"重试解析失败: {content_id}, err: {error}")
            return False
