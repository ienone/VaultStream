import re
from typing import List, Optional
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select, and_
from app.models import Content, ContentStatus, ContentSource, Platform
from app.adapters import AdapterFactory
from app.utils.url_utils import normalize_bilibili_url, canonicalize_url
from app.core.queue import task_queue
from app.core.logging import logger
from app.core.events import event_bus

class ContentService:
    def __init__(self, db: AsyncSession):
        self.db = db

    @staticmethod
    def _normalize_tags(tags: Optional[List[str]], tags_text: Optional[str] = None) -> List[str]:
        # 统一在后端收口标签清洗，避免各端分词/去重口径不一致。
        candidates: List[str] = []
        for tag in tags or []:
            if tag is None:
                continue
            candidates.extend(re.split(r"[,，\s]+", str(tag)))
        if tags_text:
            candidates.extend(re.split(r"[,，\s]+", tags_text))

        normalized: List[str] = []
        seen: set[str] = set()
        for raw in candidates:
            clean = raw.strip()
            if not clean:
                continue
            if clean in seen:
                continue
            seen.add(clean)
            normalized.append(clean)
        return normalized

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
        normalized_tags = self._normalize_tags(tags, tags_text)

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

        await self.db.commit()
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
