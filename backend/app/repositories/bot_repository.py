from typing import List, Optional, Tuple, Dict, Any
from sqlalchemy import select, and_, update, desc, delete
from sqlalchemy.orm import selectinload
from sqlalchemy.ext.asyncio import AsyncSession
from app.models.bot import BotConfig, BotChat, BotRuntime, BotConfigPlatform

class BotRepository:
    def __init__(self, db: AsyncSession):
        self.db = db

    async def get_config_by_id(self, config_id: int) -> Optional[BotConfig]:
        result = await self.db.execute(
            select(BotConfig).where(BotConfig.id == config_id)
        )
        return result.scalar_one_or_none()

    async def list_configs(self, enabled: Optional[bool] = None) -> List[BotConfig]:
        query = select(BotConfig).order_by(BotConfig.id)
        if enabled is not None:
            query = query.where(BotConfig.enabled == enabled)
        result = await self.db.execute(query)
        return list(result.scalars().all())

    async def get_primary_config(
        self, 
        platform: BotConfigPlatform, 
        enabled_only: bool = True
    ) -> Optional[BotConfig]:
        """获取主配置，如果没有主配置则返回第一个可用配置"""
        query = select(BotConfig).where(BotConfig.platform == platform)
        if enabled_only:
            query = query.where(BotConfig.enabled == True)
        
        # 尝试获取 is_primary=True 的
        primary_query = query.where(BotConfig.is_primary == True).order_by(BotConfig.id.asc()).limit(1)
        result = await self.db.execute(primary_query)
        cfg = result.scalar_one_or_none()
        if cfg:
            return cfg
        
        # Fallback: 获取第一个
        fallback_query = query.order_by(BotConfig.id.asc()).limit(1)
        result = await self.db.execute(fallback_query)
        return result.scalar_one_or_none()

    async def create_config(self, **kwargs) -> BotConfig:
        db_config = BotConfig(**kwargs)
        self.db.add(db_config)
        await self.db.flush()
        return db_config

    async def delete_config(self, db_config: BotConfig) -> None:
        await self.db.delete(db_config)

    # --- Chat Methods ---

    async def get_chat_by_id(self, chat_internal_id: int) -> Optional[BotChat]:
        result = await self.db.execute(
            select(BotChat).where(BotChat.id == chat_internal_id)
        )
        return result.scalar_one_or_none()

    async def get_chat_by_platform_id(self, bot_config_id: int, chat_id: str) -> Optional[BotChat]:
        result = await self.db.execute(
            select(BotChat).where(
                BotChat.bot_config_id == bot_config_id,
                BotChat.chat_id == chat_id
            )
        )
        return result.scalar_one_or_none()

    async def list_chats_for_config(self, bot_config_id: int, enabled: Optional[bool] = None) -> List[BotChat]:
        query = select(BotChat).where(BotChat.bot_config_id == bot_config_id)
        if enabled is not None:
            query = query.where(BotChat.enabled == enabled)
        result = await self.db.execute(query)
        return list(result.scalars().all())

    async def create_chat(self, **kwargs) -> BotChat:
        db_chat = BotChat(**kwargs)
        self.db.add(db_chat)
        await self.db.flush()
        return db_chat

    # --- Runtime Methods ---

    async def get_runtime(self) -> Optional[BotRuntime]:
        result = await self.db.execute(select(BotRuntime).limit(1))
        return result.scalar_one_or_none()

    async def update_runtime(self, **kwargs) -> BotRuntime:
        runtime = await self.get_runtime()
        if not runtime:
            runtime = BotRuntime(id=1, **kwargs)
            self.db.add(runtime)
        else:
            for k, v in kwargs.items():
                setattr(runtime, k, v)
        await self.db.flush()
        return runtime
