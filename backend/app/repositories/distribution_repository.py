from typing import List, Optional, Tuple, Dict, Any
from sqlalchemy import select, and_, update, desc, delete
from sqlalchemy.orm import selectinload
from sqlalchemy.ext.asyncio import AsyncSession
from app.models.distribution import DistributionRule, DistributionTarget
from app.models.bot import BotChat

class DistributionRepository:
    def __init__(self, db: AsyncSession):
        self.db = db

    async def get_rule_by_id(self, rule_id: int) -> Optional[DistributionRule]:
        result = await self.db.execute(
            select(DistributionRule).where(DistributionRule.id == rule_id)
        )
        return result.scalar_one_or_none()

    async def get_rule_by_name(self, name: str) -> Optional[DistributionRule]:
        result = await self.db.execute(
            select(DistributionRule).where(DistributionRule.name == name)
        )
        return result.scalar_one_or_none()

    async def list_rules(self, enabled: Optional[bool] = None) -> List[DistributionRule]:
        query = select(DistributionRule).order_by(desc(DistributionRule.priority), DistributionRule.id)
        if enabled is not None:
            query = query.where(DistributionRule.enabled == enabled)
        result = await self.db.execute(query)
        return list(result.scalars().all())

    async def list_active_rules_with_targets(self) -> List[DistributionRule]:
        """获取所有启用的规则及其关联的目标（预加载）"""
        stmt = (
            select(DistributionRule)
            .options(
                selectinload(DistributionRule.distribution_targets)
                .selectinload(DistributionTarget.bot_chat)
            )
            .where(DistributionRule.enabled == True)
            .order_by(desc(DistributionRule.priority))
        )
        result = await self.db.execute(stmt)
        return list(result.scalars().all())

    async def get_rule_with_targets(self, rule_id: int) -> Optional[DistributionRule]:
        """按 ID 获取规则及其关联的目标"""
        stmt = (
            select(DistributionRule)
            .options(
                selectinload(DistributionRule.distribution_targets)
                .selectinload(DistributionTarget.bot_chat)
            )
            .where(DistributionRule.id == rule_id)
        )
        result = await self.db.execute(stmt)
        return result.scalar_one_or_none()

    async def create_rule(self, **kwargs) -> DistributionRule:
        db_rule = DistributionRule(**kwargs)
        self.db.add(db_rule)
        await self.db.flush()
        return db_rule

    async def delete_rule(self, db_rule: DistributionRule) -> None:
        await self.db.delete(db_rule)

    # --- Target Methods ---

    async def list_rule_targets(self, rule_id: int) -> List[DistributionTarget]:
        result = await self.db.execute(
            select(DistributionTarget)
            .where(DistributionTarget.rule_id == rule_id)
            .order_by(DistributionTarget.created_at.asc())
        )
        return list(result.scalars().all())

    async def get_target_by_id(self, target_id: int, rule_id: Optional[int] = None) -> Optional[DistributionTarget]:
        stmt = select(DistributionTarget).where(DistributionTarget.id == target_id)
        if rule_id is not None:
            stmt = stmt.where(DistributionTarget.rule_id == rule_id)
        result = await self.db.execute(stmt)
        return result.scalar_one_or_none()

    async def get_target_by_chat(self, rule_id: int, bot_chat_id: int) -> Optional[DistributionTarget]:
        result = await self.db.execute(
            select(DistributionTarget).where(
                DistributionTarget.rule_id == rule_id,
                DistributionTarget.bot_chat_id == bot_chat_id
            )
        )
        return result.scalar_one_or_none()

    async def create_target(self, **kwargs) -> DistributionTarget:
        db_target = DistributionTarget(**kwargs)
        self.db.add(db_target)
        await self.db.flush()
        return db_target

    async def delete_target(self, db_target: DistributionTarget) -> None:
        await self.db.delete(db_target)

    async def batch_update_targets_by_chat(
        self, 
        rule_ids: List[int], 
        bot_chat_id: int, 
        update_values: Dict[str, Any]
    ) -> int:
        """根据 BotChat ID 批量更新多个规则下的目标配置"""
        stmt = (
            update(DistributionTarget)
            .where(
                and_(
                    DistributionTarget.rule_id.in_(rule_ids),
                    DistributionTarget.bot_chat_id == bot_chat_id
                )
            )
            .values(**update_values)
        )
        result = await self.db.execute(stmt)
        return result.rowcount
