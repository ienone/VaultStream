from typing import List, Optional, Any
from sqlalchemy import select, update, type_coerce
from sqlalchemy.ext.asyncio import AsyncSession
from app.models.system import SystemSetting

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

    async def upsert_setting(self, key: str, value: Any, category: str = "general", description: Optional[str] = None) -> SystemSetting:
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

    async def replace_setting_if_unchanged(self, key: str, expected: Any, value: Any) -> bool:
        result = await self.db.execute(
            update(SystemSetting).where(
                SystemSetting.key == key,
                SystemSetting.value == type_coerce(expected, SystemSetting.value.type),
            ).values(value=value).execution_options(synchronize_session=False)
        )
        return result.rowcount == 1
