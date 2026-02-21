import re
from datetime import datetime
from typing import List, Optional
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select, and_, or_, func
from sqlalchemy.exc import IntegrityError
from app.models import Content, ContentStatus, ContentSource, PushedRecord, Platform, ReviewStatus
from app.adapters import AdapterFactory
from app.utils.url_utils import normalize_bilibili_url, canonicalize_url
from app.utils.tags import normalize_tags
from app.core.queue import task_queue
from app.core.logging import logger
from app.core.events import event_bus

class ContentService:
    def __init__(self, db: AsyncSession):
        self.db = db

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

        # 1. 规范化
        url_for_detect = normalize_bilibili_url(url)
        url_for_detect = canonicalize_url(url_for_detect)

        # 2. 平台检测
        platform = AdapterFactory.detect_platform(url_for_detect)
        if not platform:
            raise ValueError("Unsupported platform URL")

        # 3. 计算唯一标识
        adapter = AdapterFactory.create(platform)
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
                url=url,
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
            if source_name:
                content.source = source_name
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

        # 6. 异步入队（新增内容，或存量仍处于待解析状态）
        should_enqueue_parse = is_new or content.status in (
            ContentStatus.UNPROCESSED,
            ContentStatus.PARSE_FAILED,
        )
        if should_enqueue_parse:
            await task_queue.enqueue({'content_id': content.id, 'action': 'parse'})
            logger.info(f"New content enqueued: {content.id}")
            
            # 广播新增事件
            await event_bus.publish("content_created", {
                "id": content.id,
                "url": content.url,
                "platform": content.platform.value if content.platform else None,
                "status": content.status.value if content.status else None,
            })

        return content

    # --- 内容更新 ---

    async def update_content(self, content_id: int, updates: dict) -> Content:
        """更新内容字段，支持状态重置触发重新解析"""
        result = await self.db.execute(select(Content).where(Content.id == content_id))
        content = result.scalar_one_or_none()
        if content is None:
            raise ValueError("Content not found")

        enqueue_parse = False
        for field, value in updates.items():
            if value is None:
                continue
            if field == "cover_url" and content.cover_url != value:
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

        await self.db.commit()
        await self.db.refresh(content)

        if enqueue_parse:
            await task_queue.enqueue({'content_id': content.id, 'action': 'parse'})
            logger.info(f"Content status reset to unprocessed, parse re-enqueued: {content.id}")

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
        
        if content.rich_payload:
            if content.rich_payload.context_data:
                for item in content.rich_payload.context_data:
                    if item.type == "image" and item.url:
                        key = cls._extract_local_key(item.url)
                        if key:
                            keys.add(key)
            if content.rich_payload.payload_blocks:
                for block in content.rich_payload.payload_blocks:
                    if block.type == "image" and block.content:
                        key = cls._extract_local_key(block.content)
                        if key:
                            keys.add(key)
                            
        if content.description and "local://" in content.description:
            for match in re.finditer(r'local://([a-zA-Z0-9_/.-]+)', content.description):
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
                Content.description.like(f'%{local_url}%'),
                Content.context_data.like(f'%{local_url}%'),
                Content.rich_payload.like(f'%{local_url}%'),
                Content.archive_metadata.like(f'%{local_url}%'),
            )
        )
        ref_count = (await self.db.execute(ref_stmt)).scalar() or 0
        return ref_count > 0

    async def delete_content(self, content_id: int) -> dict:
        """删除内容（含数据库记录和已归档的本地媒体文件）"""
        result = await self.db.execute(select(Content).where(Content.id == content_id))
        content = result.scalar_one_or_none()
        if content is None:
            raise ValueError("Content not found")

        local_keys = self._collect_local_media_keys(content)
        if local_keys:
            from app.core.storage import get_storage_backend
            storage = get_storage_backend()
            for key in local_keys:
                try:
                    if await self._is_media_referenced(key, content_id):
                        logger.info(f"媒体文件仍被其他内容引用，跳过删除: key={key}")
                        continue
                    await storage.delete(key=key)
                except Exception as e:
                    logger.warning(f"清理媒体文件失败: key={key}, err={e}")

        await self.db.execute(ContentSource.__table__.delete().where(ContentSource.content_id == content_id))
        await self.db.execute(PushedRecord.__table__.delete().where(PushedRecord.content_id == content_id))
        await self.db.delete(content)
        await self.db.commit()

        logger.info(f"内容已删除: content_id={content_id}, 清理媒体文件={len(local_keys)}个")
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
            from app.distribution.queue_service import enqueue_content_background
            await enqueue_content_background(content_id)
        except Exception as e:
            logger.error(f"审批通过后分发入队失败: content_id={content_id}, err={e}")
