from typing import List, Optional
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession
from app.models.bot import BotConfig, BotChat, BotConfigPlatform

class BotRepository:
    def __init__(self, db: AsyncSession):
        self.db = db

    async def get_primary_config(
        self, 
        platform: BotConfigPlatform, 
        enabled_only: bool = True
    ) -> Optional[BotConfig]:
        """获取平台唯一配置；优先返回启用记录。"""
        query = select(BotConfig).where(BotConfig.platform == platform)
        if enabled_only:
            query = query.where(BotConfig.enabled == True)

        result = await self.db.execute(
            query.order_by(
                BotConfig.is_primary.desc(),
                BotConfig.enabled.desc(),
                BotConfig.id.asc(),
            ).limit(1)
        )
        return result.scalar_one_or_none()

    # --- Chat Methods ---

    async def get_chat_by_id(self, chat_internal_id: int) -> Optional[BotChat]:
        result = await self.db.execute(
            select(BotChat).where(BotChat.id == chat_internal_id)
        )
        return result.scalar_one_or_none()

    async def list_chats_for_config(self, bot_config_id: int, enabled: Optional[bool] = None) -> List[BotChat]:
        query = select(BotChat).where(BotChat.bot_config_id == bot_config_id)
        if enabled is not None:
            query = query.where(BotChat.enabled == enabled)
        result = await self.db.execute(query)
        return list(result.scalars().all())
