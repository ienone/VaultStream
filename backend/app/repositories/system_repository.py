from typing import List, Optional, Tuple, Dict, Any
from sqlalchemy import select, and_, update, desc, delete, func
from sqlalchemy.ext.asyncio import AsyncSession
from app.models.system import SystemSetting, PushedRecord, ContentQueueItem, QueueItemStatus

class SystemRepository:
    def __init__(self, db: AsyncSession):
        self.db = db

    # --- Settings ---

    async def get_setting(self, key: str) -> Optional[SystemSetting]:
        result = await self.db.execute(
            select(SystemSetting).where(SystemSetting.key == key)
        )
        return result.scalar_one_or_none()

    async def list_settings(self, category: Optional[str] = None) -> List[SystemSetting]:
        query = select(SystemSetting)
        if category:
            query = query.where(SystemSetting.category == category)
        result = await self.db.execute(query)
        return list(result.scalars().all())

    async def upsert_setting(self, key: str, value: Any, category: str = "general", description: str = None) -> SystemSetting:
        setting = await self.get_setting(key)
        if setting:
            setting.value = value
            if description:
                setting.description = description
        else:
            setting = SystemSetting(key=key, value=value, category=category, description=description)
            self.db.add(setting)
        await self.db.flush()
        return setting

    async def delete_setting(self, setting: SystemSetting) -> None:
        await self.db.delete(setting)

    # --- Pushed Records ---

    async def list_pushed_records(self, content_id: Optional[int] = None, limit: int = 50) -> List[PushedRecord]:
        query = select(PushedRecord).order_by(desc(PushedRecord.pushed_at))
        if content_id:
            query = query.where(PushedRecord.content_id == content_id)
        query = query.limit(limit)
        result = await self.db.execute(query)
        return list(result.scalars().all())

    async def create_pushed_record(self, **kwargs) -> PushedRecord:
        record = PushedRecord(**kwargs)
        self.db.add(record)
        await self.db.flush()
        return record

    # --- Queue Items ---

    async def get_queue_item(self, item_id: int) -> Optional[ContentQueueItem]:
        result = await self.db.execute(
            select(ContentQueueItem).where(ContentQueueItem.id == item_id)
        )
        return result.scalar_one_or_none()

    async def list_queue_items(
        self, 
        status: Optional[QueueItemStatus] = None, 
        limit: int = 100,
        offset: int = 0
    ) -> Tuple[List[ContentQueueItem], int]:
        query = select(ContentQueueItem).order_by(desc(ContentQueueItem.created_at))
        if status:
            query = query.where(ContentQueueItem.status == status)
        
        # Count
        count_stmt = select(func.count()).select_from(ContentQueueItem)
        if status:
            count_stmt = count_stmt.where(ContentQueueItem.status == status)
        total = (await self.db.execute(count_stmt)).scalar() or 0

        # Data
        query = query.offset(offset).limit(limit)
        result = await self.db.execute(query)
        return list(result.scalars().all()), total

    async def get_queue_stats(self) -> Dict[str, int]:
        """获取各状态的队列项计数"""
        stmt = select(ContentQueueItem.status, func.count()).group_by(ContentQueueItem.status)
        result = await self.db.execute(stmt)
        stats = {status.value: count for status, count in result.all()}
        
        # 确保包含所有可能的状态
        for s in QueueItemStatus:
            if s.value not in stats:
                stats[s.value] = 0
        return stats
