from contextlib import AsyncExitStack
import mimetypes
import re
from dataclasses import dataclass
from datetime import datetime
from typing import AsyncIterable, List, Optional
from uuid import uuid4
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select, and_, or_, func, text
from sqlalchemy.exc import IntegrityError
from app.models import (
    Content,
    ContentStatus,
    ContentSource,
    LayoutType,
    MediaArchiveStatus,
    MediaAsset,
    MediaRole,
    MediaType,
    MediaVariant,
    MediaVariantKind,
    MediaVariantStatus,
    PushedRecord,
    Platform,
    ReviewStatus,
)
from app.adapters.storage import LocalStorageBackend
from app.adapters import AdapterFactory, open_adapter
from app.utils.url_utils import (
    extract_primary_url_candidate,
    is_url_like_input,
    normalize_share_url_input,
)
from app.utils.tags import normalize_tags
from app.core.queue import task_queue
from app.core.logging import logger
from app.core.events import event_bus
from app.services.post_ingest import PostIngestService
from app.services.notification_inbox import (
    safely_record_bot_capture_notification,
    safely_resolve_bot_capture_notification,
)


class ParseQueueUnavailableError(RuntimeError):
    """Content was persisted, but its parse task could not be queued."""

    def __init__(self, content_id: int):
        self.content_id = content_id
        super().__init__("Content saved but parse task enqueue failed")


@dataclass(frozen=True)
class CaptureFileInput:
    """One streamed file in a user capture request."""

    chunks: AsyncIterable[bytes]
    filename: str
    mime_type: Optional[str] = None


class ContentService:
    MANUAL_EDIT_FIELDS = frozenset({
        "title",
        "body",
        "author_name",
        "cover_url",
        "tags",
        "layout_type_override",
    })

    def __init__(self, db: AsyncSession):
        self.db = db

    @staticmethod
    async def _record_capture_receipt(
        content: Content,
        *,
        source_name: str | None,
        capture_kind: str,
        client_context: dict | None,
    ) -> None:
        if (source_name or "").strip().lower() != "telegram_bot":
            return
        await safely_record_bot_capture_notification(
            content_id=content.id,
            capture_kind=capture_kind,
            display_title=content.title,
            display_url=content.url,
            client_context=client_context,
        )

    async def create_share(
        self, 
        url: str, 
        tags: List[str] = None, 
        tags_text: str = None,
        source_name: str = None, 
        note: str = None,
        is_nsfw: bool = False,
        client_context: dict = None,
        layout_type_override: str = None
    ) -> Content:
        """核心分享创建业务逻辑"""
        normalized_tags = normalize_tags(tags, tags_text)
        raw_url = (url or "").strip()
        extracted_input = extract_primary_url_candidate(raw_url)
        if not is_url_like_input(extracted_input):
            raise ValueError("No valid URL found in input")

        # 1. 规范化
        url_for_detect = normalize_share_url_input(raw_url)

        # 2. 平台检测
        platform = AdapterFactory.detect_platform(url_for_detect)
        if not platform:
            raise ValueError("Unsupported platform URL")

        # 3. 计算唯一标识
        async with open_adapter(platform) as adapter:
            canonical_url = await adapter.clean_url(url_for_detect)
        
        # 4. 去重查询
        stmt = select(Content).where(
            and_(Content.platform == platform, Content.canonical_url == canonical_url)
        )
        content = (await self.db.execute(stmt)).scalar_one_or_none()

        is_new = False
        if content is None:
            content = Content(
                platform=platform,
                url=url_for_detect,
                canonical_url=canonical_url,
                clean_url=canonical_url,
                tags=normalized_tags,
                source=source_name,
                is_nsfw=is_nsfw,
                status=ContentStatus.UNPROCESSED,
                layout_type_override=layout_type_override,
            )
            self.db.add(content)
            await self.db.flush()
            is_new = True
        else:
            # 存量合并：标签合并
            existing_tags = set(content.tags or [])
            incoming_tags = set(normalized_tags)
            content.tags = list(existing_tags.union(incoming_tags))
            if content.url != url_for_detect:
                content.url = url_for_detect
            if content.clean_url != canonical_url:
                content.clean_url = canonical_url
            if source_name:
                content.source = source_name
            # 如果提供了 override，更新它
            if layout_type_override:
                content.layout_type_override = layout_type_override

        # 5. 记录来源流水
        self.db.add(
            ContentSource(
                content_id=content.id,
                source=source_name,
                tags_snapshot=normalized_tags,
                note=note,
                client_context=client_context,
            )
        )

        try:
            await self.db.commit()
        except IntegrityError:
            # 并发竞态：两个请求同时通过去重查询，第二个触发唯一约束冲突
            await self.db.rollback()
            logger.info(f"去重唯一约束冲突，回读已有记录: platform={platform}, canonical_url={canonical_url}")
            stmt = select(Content).where(
                and_(Content.platform == platform, Content.canonical_url == canonical_url)
            )
            content = (await self.db.execute(stmt)).scalar_one_or_none()
            if content is None:
                raise
            # 合并标签
            existing_tags = set(content.tags or [])
            incoming_tags = set(normalized_tags)
            content.tags = list(existing_tags.union(incoming_tags))
            if content.url != url_for_detect:
                content.url = url_for_detect
            if content.clean_url != canonical_url:
                content.clean_url = canonical_url
            if source_name:
                content.source = source_name
            
            # 显式标记为 dirty 确保更新被提交
            self.db.add(content)
            
            # 重新记录来源流水
            self.db.add(
                ContentSource(
                    content_id=content.id,
                    source=source_name,
                    tags_snapshot=normalized_tags,
                    note=note,
                    client_context=client_context,
                )
            )
            await self.db.commit()
            is_new = False

        await self.db.refresh(content)
        await self._record_capture_receipt(
            content,
            source_name=source_name,
            capture_kind="link",
            client_context=client_context,
        )

        # 6. 异步入队（新增内容，或存量仍处于待解析状态）
        should_enqueue_parse = is_new or content.status in (
            ContentStatus.UNPROCESSED,
            ContentStatus.PARSE_FAILED,
        )
        if should_enqueue_parse:
            enqueued = await task_queue.enqueue(
                {'content_id': content.id, 'action': 'parse'}
            )
            if not enqueued:
                raise ParseQueueUnavailableError(content.id)
            logger.info(f"New content enqueued: {content.id}")
            
            # 广播新增事件
            await event_bus.publish("content_created", {
                "id": content.id,
                "url": content.url,
                "platform": content.platform.value if content.platform else None,
                "status": content.status.value if content.status else None,
            })
        elif content.status == ContentStatus.PARSE_SUCCESS:
            await PostIngestService().run_for_content(
                self.db,
                content,
                source=source_name or "share",
                summary=True,
                embedding=True,
                patrol=False,
                distribution=True,
            )

        return content

    async def create_text_capture(
        self,
        text: str,
        *,
        title: str = None,
        tags: List[str] = None,
        tags_text: str = None,
        source_name: str = "manual_text",
        note: str = None,
        is_nsfw: bool = False,
        client_context: dict = None,
        layout_type_override: str = None,
    ) -> Content:
        """保存原始文本，并从已完成解析的状态进入统一后处理。"""
        body = (text or "").strip()
        if not body:
            raise ValueError("Text content cannot be empty")

        normalized_title = (title or "").strip()
        if not normalized_title:
            first_line = next(
                (line.strip() for line in body.splitlines() if line.strip()),
                "文本摘录",
            )
            normalized_title = first_line[:200]

        internal_url = f"vaultstream://text/{uuid4().hex}"
        normalized_tags = normalize_tags(tags, tags_text)
        content = Content(
            platform=Platform.UNIVERSAL,
            url=internal_url,
            canonical_url=internal_url,
            clean_url=internal_url,
            title=normalized_title,
            body=body,
            content_type="note",
            tags=normalized_tags,
            source=source_name or "manual_text",
            source_type="manual_text",
            is_nsfw=is_nsfw,
            status=ContentStatus.PARSE_SUCCESS,
            layout_type_override=layout_type_override,
        )
        self.db.add(content)
        await self.db.flush()
        self.db.add(
            ContentSource(
                content_id=content.id,
                source=source_name or "manual_text",
                tags_snapshot=normalized_tags,
                note=note,
                client_context=client_context,
            )
        )
        await self.db.commit()
        await self.db.refresh(content)
        await self._record_capture_receipt(
            content,
            source_name=source_name,
            capture_kind="text",
            client_context=client_context,
        )

        await PostIngestService().run_for_content(
            self.db,
            content,
            source=source_name or "manual_text",
            summary=True,
            embedding=True,
            patrol=False,
            distribution=True,
        )
        await event_bus.publish(
            "content_created",
            {
                "id": content.id,
                "url": content.url,
                "platform": content.platform.value,
                "status": content.status.value,
            },
        )
        return content

    async def create_file_capture(
        self,
        chunks: AsyncIterable[bytes],
        *,
        filename: str,
        mime_type: str = None,
        title: str = None,
        tags: List[str] = None,
        tags_text: str = None,
        source_name: str = "manual_upload",
        note: str = None,
        is_nsfw: bool = False,
        layout_type_override: str = None,
        storage: LocalStorageBackend,
        max_bytes: int,
    ) -> Content:
        """保存一个用户上传文件；单文件与多文件共享同一持久化规则。"""
        return await self.create_files_capture(
            [
                CaptureFileInput(
                    chunks=chunks,
                    filename=filename,
                    mime_type=mime_type,
                )
            ],
            title=title,
            tags=tags,
            tags_text=tags_text,
            source_name=source_name,
            note=note,
            is_nsfw=is_nsfw,
            layout_type_override=layout_type_override,
            storage=storage,
            max_bytes=max_bytes,
        )

    async def create_files_capture(
        self,
        files: List[CaptureFileInput],
        *,
        title: str = None,
        tags: List[str] = None,
        tags_text: str = None,
        source_name: str = "manual_upload",
        note: str = None,
        is_nsfw: bool = False,
        layout_type_override: str = None,
        client_context: dict = None,
        storage: LocalStorageBackend,
        max_bytes: int,
    ) -> Content:
        """把一次分享中的一个或多个原文件保存为同一个内容对象。"""
        if not files:
            raise ValueError("At least one file is required")

        async with AsyncExitStack() as staging:
            stored_files = []
            for capture_file in files:
                display_filename = (
                    (capture_file.filename or "")
                    .replace("\\", "/")
                    .split("/")[-1]
                    .strip()
                    or "未命名文件"
                )
                normalized_mime = (
                    (capture_file.mime_type or "").split(";", 1)[0].strip().lower()
                )
                if not normalized_mime or "/" not in normalized_mime:
                    normalized_mime = (
                        mimetypes.guess_type(display_filename)[0]
                        or "application/octet-stream"
                    )

                if normalized_mime.startswith("image/"):
                    media_type = MediaType.IMAGE
                    media_role = MediaRole.GALLERY
                    item_content_type = "image"
                    item_layout_type = LayoutType.GALLERY
                elif normalized_mime.startswith("video/"):
                    media_type = MediaType.VIDEO
                    media_role = MediaRole.BODY
                    item_content_type = "video"
                    item_layout_type = LayoutType.VIDEO
                elif normalized_mime.startswith("audio/"):
                    media_type = MediaType.AUDIO
                    media_role = MediaRole.BODY
                    item_content_type = "audio"
                    item_layout_type = LayoutType.AUDIO
                elif normalized_mime == "application/pdf" or normalized_mime.startswith("text/"):
                    media_type = MediaType.DOCUMENT
                    media_role = MediaRole.ATTACHMENT
                    item_content_type = "document"
                    item_layout_type = LayoutType.ARTICLE
                else:
                    media_type = MediaType.OTHER
                    media_role = MediaRole.ATTACHMENT
                    item_content_type = "document"
                    item_layout_type = LayoutType.ARTICLE

                stored, temp_path = await staging.enter_async_context(storage.stage_stream(
                    chunks=capture_file.chunks,
                    content_type=normalized_mime,
                    max_bytes=max_bytes,
                ))
                stored_files.append(
                    {
                        "filename": display_filename,
                        "mime_type": normalized_mime,
                        "media_type": media_type,
                        "media_role": media_role,
                        "content_type": item_content_type,
                        "layout_type": item_layout_type,
                        "stored": stored,
                        "temp_path": temp_path,
                    }
                )

            first_file = stored_files[0]
            if len(stored_files) == 1:
                content_type = first_file["content_type"]
                layout_type = first_file["layout_type"]
                default_title = first_file["filename"]
            elif all(item["media_type"] == MediaType.IMAGE for item in stored_files):
                content_type = "gallery"
                layout_type = LayoutType.GALLERY
                default_title = f"{len(stored_files)} 张共享图片"
            else:
                content_type = "document"
                layout_type = LayoutType.ARTICLE
                default_title = f"{len(stored_files)} 个共享文件"

            internal_url = f"vaultstream://file/{uuid4().hex}"
            normalized_tags = normalize_tags(tags, tags_text)
            normalized_title = (title or "").strip() or default_title
            normalized_note = (note or "").strip() or None
            normalized_source = source_name or "manual_upload"
            archived_files = [
                {
                    "filename": item["filename"],
                    "mime_type": item["mime_type"],
                    "size_bytes": item["stored"].size,
                    "checksum": item["stored"].sha256 or "",
                }
                for item in stored_files
            ]
            content = Content(
                platform=Platform.UNIVERSAL,
                url=internal_url,
                canonical_url=internal_url,
                clean_url=internal_url,
                title=normalized_title,
                body=normalized_note,
                content_type=content_type,
                layout_type=layout_type,
                layout_type_override=layout_type_override,
                tags=normalized_tags,
                source=normalized_source,
                source_type=normalized_source,
                is_nsfw=is_nsfw,
                status=ContentStatus.PARSE_SUCCESS,
                archive_metadata={
                    "files": archived_files,
                },
            )
            self.db.add(content)
            await self.db.flush()
            self.db.add(
                ContentSource(
                    content_id=content.id,
                    source=normalized_source,
                    tags_snapshot=normalized_tags,
                    note=normalized_note,
                    client_context=client_context,
                )
            )
            for position, item in enumerate(stored_files):
                stored = item["stored"]
                checksum = stored.sha256 or ""
                asset = MediaAsset(
                    content_id=content.id,
                    position=position,
                    media_type=item["media_type"],
                    role=item["media_role"],
                    archive_status=MediaArchiveStatus.READY,
                    repairable=False,
                    asset_metadata={
                        "filename": item["filename"],
                        "mime_type": item["mime_type"],
                        "size_bytes": stored.size,
                        "checksum": checksum,
                        "source": normalized_source,
                    },
                )
                self.db.add(asset)
                await self.db.flush()
                self.db.add(
                    MediaVariant(
                        asset_id=asset.id,
                        variant_kind=MediaVariantKind.ORIGINAL_ARCHIVE,
                        storage_key=stored.key,
                        mime_type=item["mime_type"],
                        size_bytes=stored.size,
                        status=MediaVariantStatus.READY,
                        checksum=checksum,
                    )
                )
            published_keys = []
            try:
                await self.db.flush()
                for item in stored_files:
                    if await storage.publish_staged(item["stored"], item["temp_path"]):
                        published_keys.append(item["stored"].key)
                await self.db.commit()
            except BaseException:
                await self.db.rollback()
                # Serialize cleanup with capture commits; never remove an object
                # that another committed content now references.
                await self.db.execute(text("BEGIN IMMEDIATE"))
                for key in published_keys:
                    if not await self._is_media_referenced(key, -1):
                        await storage.delete(key=key)
                await self.db.rollback()
                raise
        await self.db.refresh(content)
        await self._record_capture_receipt(
            content,
            source_name=normalized_source,
            capture_kind="attachment",
            client_context=client_context,
        )

        await PostIngestService().run_for_content(
            self.db,
            content,
            source=normalized_source,
            summary=bool(normalized_note),
            embedding=True,
            patrol=False,
            distribution=True,
        )
        await event_bus.publish(
            "content_created",
            {
                "id": content.id,
                "url": content.url,
                "platform": content.platform.value,
                "status": content.status.value,
            },
        )
        return content

    # --- 内容更新 ---

    async def update_content(self, content_id: int, updates: dict) -> Content:
        """更新内容字段，支持状态重置触发重新解析"""
        result = await self.db.execute(select(Content).where(Content.id == content_id))
        content = result.scalar_one_or_none()
        if content is None:
            raise ValueError("Content not found")

        enqueue_parse = False
        manual_fields = set(content.manual_edit_fields or [])
        for field, value in updates.items():
            if value is None and field != "layout_type_override":
                continue
            previous_value = getattr(content, field)
            if previous_value == value:
                continue

            if field == "cover_url":
                content.cover_url = value
                from app.media.color import extract_cover_color
                content.cover_color = await extract_cover_color(value)
            elif field == "status":
                previous_status = content.status
                content.status = value
                if value == ContentStatus.UNPROCESSED and previous_status != ContentStatus.UNPROCESSED:
                    enqueue_parse = True
            else:
                setattr(content, field, value)

            if field in self.MANUAL_EDIT_FIELDS:
                if field == "layout_type_override" and value is None:
                    manual_fields.discard(field)
                else:
                    manual_fields.add(field)

        content.manual_edit_fields = sorted(manual_fields)

        await self.db.commit()
        await self.db.refresh(content)

        if enqueue_parse:
            enqueued = await task_queue.enqueue(
                {'content_id': content.id, 'action': 'parse'}
            )
            if not enqueued:
                raise ParseQueueUnavailableError(content.id)
            logger.info(f"Content status reset to unprocessed, parse re-enqueued: {content.id}")

        await event_bus.publish("content_updated", {
            "id": content.id,
            "title": content.title,
            "status": content.status.value if content.status else None,
            "platform": content.platform.value if content.platform else None,
        })

        return content

    async def resolve_parse_candidate(
        self,
        content_id: int,
        *,
        field: str,
        action: str,
        merged_value: Optional[str] = None,
    ) -> Content:
        """Resolve one parser/manual conflict and leave unrelated fields pending."""
        result = await self.db.execute(select(Content).where(Content.id == content_id))
        content = result.scalar_one_or_none()
        if content is None:
            raise ValueError("Content not found")

        candidate = dict(content.parse_candidate or {})
        fields = dict(candidate.get("fields") or {})
        if field not in fields:
            raise ValueError("Parse candidate field not found")

        manual_fields = set(content.manual_edit_fields or [])
        if action == "accept_parsed":
            value = fields[field]
            setattr(content, field, value)
            manual_fields.discard(field)
        elif action == "keep_current":
            manual_fields.add(field)
        elif action == "merge":
            if merged_value is None:
                raise ValueError("merged_value is required when action is merge")
            setattr(content, field, merged_value)
            manual_fields.add(field)
        else:
            raise ValueError("Unsupported parse candidate action")

        if field == "cover_url" and action in {"accept_parsed", "merge"}:
            from app.media.color import extract_cover_color
            content.cover_color = await extract_cover_color(content.cover_url)

        fields.pop(field)
        content.manual_edit_fields = sorted(manual_fields)
        content.parse_candidate = (
            {**candidate, "fields": fields}
            if fields
            else None
        )

        await self.db.commit()
        await self.db.refresh(content)
        await event_bus.publish("content_updated", {
            "id": content.id,
            "title": content.title,
            "status": content.status.value if content.status else None,
            "platform": content.platform.value if content.platform else None,
        })
        return content

    # --- 内容删除（含媒体清理 + 引用计数） ---

    @staticmethod
    def _extract_local_key(url: Optional[str]) -> Optional[str]:
        if url and url.startswith("local://"):
            return url.replace("local://", "")
        return None

    @classmethod
    def _collect_local_keys_from_json(cls, value: object, keys: set[str]) -> None:
        """递归扫描 JSON 结构中的 local:// URL，覆盖 dict/list/str 组合场景。"""
        if isinstance(value, str):
            key = cls._extract_local_key(value)
            if key:
                keys.add(key)
            return
        if isinstance(value, dict):
            for nested_value in value.values():
                cls._collect_local_keys_from_json(nested_value, keys)
            return
        if isinstance(value, list):
            for nested_value in value:
                cls._collect_local_keys_from_json(nested_value, keys)
            return

    @classmethod
    def _collect_local_media_keys(cls, content: Content) -> list[str]:
        """收集内容中所有 local:// 引用的存储 key（全字段覆盖）"""
        keys: set[str] = set()
        for url in (content.cover_url, content.author_avatar_url):
            key = cls._extract_local_key(url)
            if key:
                keys.add(key)
        for url in (content.media_urls or []):
            key = cls._extract_local_key(url)
            if key:
                keys.add(key)
        
        # 结构化字段和归档字段均可能包含 local:// 资源引用。
        cls._collect_local_keys_from_json(content.context_data, keys)
        cls._collect_local_keys_from_json(content.rich_payload, keys)
        cls._collect_local_keys_from_json(content.archive_metadata, keys)
                            
        if content.body and "local://" in content.body:
            for match in re.finditer(r'local://([a-zA-Z0-9_/.-]+)', content.body):
                keys.add(match.group(1))
        return list(keys)

    async def _is_media_referenced(self, key: str, exclude_content_id: int) -> bool:
        """检查是否有其他内容引用同一媒体文件"""
        local_url = f"local://{key}"
        ref_stmt = select(func.count()).select_from(Content).where(
            Content.id != exclude_content_id,
            or_(
                Content.cover_url == local_url,
                Content.author_avatar_url == local_url,
                Content.media_urls.like(f'%{local_url}%'),
                Content.body.like(f'%{local_url}%'),
                Content.context_data.like(f'%{local_url}%'),
                Content.rich_payload.like(f'%{local_url}%'),
                Content.archive_metadata.like(f'%{local_url}%'),
            )
        )
        legacy_ref_count = (await self.db.execute(ref_stmt)).scalar() or 0
        if legacy_ref_count > 0:
            return True
        variant_stmt = (
            select(func.count())
            .select_from(MediaVariant)
            .join(MediaAsset, MediaVariant.asset_id == MediaAsset.id)
            .where(
                MediaVariant.storage_key == key,
                MediaAsset.content_id != exclude_content_id,
            )
        )
        variant_ref_count = (await self.db.execute(variant_stmt)).scalar() or 0
        return variant_ref_count > 0

    async def _collect_variant_storage_keys(self, content_id: int) -> list[str]:
        stmt = (
            select(MediaVariant.storage_key)
            .join(MediaAsset, MediaVariant.asset_id == MediaAsset.id)
            .where(MediaAsset.content_id == content_id)
        )
        return list((await self.db.execute(stmt)).scalars().all())

    async def delete_content(self, content_id: int) -> dict:
        """删除内容（含数据库记录和已归档的本地媒体文件）"""
        from app.services.knowledge_event_service import KnowledgeEventService

        await KnowledgeEventService(self.db).prepare_member_removal(content_id)
        result = await self.db.execute(select(Content).where(Content.id == content_id))
        content = result.scalar_one_or_none()
        if content is None:
            raise ValueError("Content not found")

        storage_keys = set(self._collect_local_media_keys(content))
        storage_keys.update(await self._collect_variant_storage_keys(content_id))

        await self.db.execute(ContentSource.__table__.delete().where(ContentSource.content_id == content_id))
        await self.db.execute(PushedRecord.__table__.delete().where(PushedRecord.content_id == content_id))
        await self.db.delete(content)
        await self.db.commit()
        await safely_resolve_bot_capture_notification(content_id)

        deleted_storage_count = 0
        if storage_keys:
            from app.adapters.storage import get_storage_backend
            storage = get_storage_backend()
            for key in storage_keys:
                try:
                    if await self._is_media_referenced(key, content_id):
                        logger.info(f"媒体文件仍被其他内容引用，跳过删除: key={key}")
                        continue
                    if await storage.delete(key=key):
                        deleted_storage_count += 1
                except Exception as e:
                    logger.warning(f"清理媒体文件失败: key={key}, err={e}")

        logger.info(
            f"内容已删除: content_id={content_id}, "
            f"清理媒体文件={deleted_storage_count}个"
        )
        await event_bus.publish("content_deleted", {"id": content_id})
        return {"status": "deleted", "content_id": content_id}

    # --- 审批 ---

    async def review_card(self, card_id: int, action: str, reviewed_by: str = None, note: str = None) -> dict:
        """审批单个内容"""
        if action not in ("approve", "reject"):
            raise ValueError("Invalid action")

        result = await self.db.execute(select(Content).where(Content.id == card_id))
        content = result.scalar_one_or_none()
        if content is None:
            raise ValueError("Card not found")

        is_approve = action == "approve"
        content.review_status = ReviewStatus.APPROVED if is_approve else ReviewStatus.REJECTED
        content.reviewed_at = datetime.utcnow()
        content.reviewed_by = reviewed_by
        content.review_note = note
        await self.db.commit()

        if is_approve:
            await self._enqueue_distribution(content.id)

        return {"id": content.id, "review_status": content.review_status.value}

    async def batch_review_cards(self, content_ids: List[int], action: str, reviewed_by: str = None, note: str = None) -> dict:
        """批量审批内容"""
        if action not in ("approve", "reject"):
            raise ValueError("Invalid action")

        is_approve = action == "approve"
        review_status = ReviewStatus.APPROVED if is_approve else ReviewStatus.REJECTED

        result = await self.db.execute(select(Content).where(Content.id.in_(content_ids)))
        contents = result.scalars().all()
        if not contents:
            raise ValueError("No cards found")

        for content in contents:
            content.review_status = review_status
            content.reviewed_at = datetime.utcnow()
            content.reviewed_by = reviewed_by
            content.review_note = note
        await self.db.commit()

        if is_approve:
            for content in contents:
                await self._enqueue_distribution(content.id)

        return {"updated": len(contents), "action": action}

    async def _enqueue_distribution(self, content_id: int) -> None:
        """审批通过后触发分发入队"""
        try:
            from app.services.distribution import enqueue_content_background
            await enqueue_content_background(content_id)
        except Exception as e:
            logger.error(f"审批通过后分发入队失败: content_id={content_id}, err={e}")
