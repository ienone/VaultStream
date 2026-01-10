from typing import List, Optional
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select, and_
from app.models import Content, ContentStatus, ContentSource, Platform
from app.adapters import AdapterFactory
from app.utils import normalize_bilibili_url, canonicalize_url
from app.queue import task_queue
from app.logging import logger

class ContentService:
    def __init__(self, db: AsyncSession):
        self.db = db

    async def create_share(
        self, 
        url: str, 
        tags: List[str] = None, 
        source_name: str = None, 
        note: str = None,
        is_nsfw: bool = False,
        client_context: dict = None
    ) -> Content:
        """核心分享创建业务逻辑"""
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
                tags=tags or [],
                source=source_name,
                is_nsfw=is_nsfw,
                status=ContentStatus.UNPROCESSED,
            )
            self.db.add(content)
            await self.db.flush()
            is_new = True
        else:
            # 存量合并：标签合并
            existing_tags = set(content.tags or [])
            incoming_tags = set(tags or [])
            content.tags = list(existing_tags.union(incoming_tags))
            if source_name:
                content.source = source_name

        # 5. 记录来源流水
        self.db.add(
            ContentSource(
                content_id=content.id,
                source=source_name,
                tags_snapshot=tags,
                note=note,
                client_context=client_context,
            )
        )

        await self.db.commit()
        await self.db.refresh(content)

        # 6. 异步入队
        if is_new:
            await task_queue.enqueue({'content_id': content.id, 'action': 'parse'})
            logger.info(f"New content enqueued: {content.id}")

        return content
