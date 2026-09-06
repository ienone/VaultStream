from typing import List, Optional
from sqlalchemy import select, desc
from sqlalchemy.orm import selectinload
from sqlalchemy.ext.asyncio import AsyncSession
from app.models.distribution import DistributionRule, DistributionTarget

class DistributionRepository:
    def __init__(self, db: AsyncSession):
        self.db = db

    async def get_rule_by_id(self, rule_id: int) -> Optional[DistributionRule]:
        result = await self.db.execute(
            select(DistributionRule)
            .options(
                selectinload(DistributionRule.distribution_targets)
                .selectinload(DistributionTarget.bot_chat)
            )
            .where(DistributionRule.id == rule_id)
        )
        return result.scalar_one_or_none()

    async def get_rule_by_name(self, name: str) -> Optional[DistributionRule]:
        result = await self.db.execute(
            select(DistributionRule)
            .options(
                selectinload(DistributionRule.distribution_targets)
                .selectinload(DistributionTarget.bot_chat)
            )
            .where(DistributionRule.name == name)
        )
        return result.scalar_one_or_none()

    async def list_rules(self, enabled: Optional[bool] = None) -> List[DistributionRule]:
        query = (
            select(DistributionRule)
            .options(
                selectinload(DistributionRule.distribution_targets)
                .selectinload(DistributionTarget.bot_chat)
            )
            .order_by(desc(DistributionRule.priority), DistributionRule.id)
        )
        if enabled is not None:
            query = query.where(DistributionRule.enabled == enabled)
        result = await self.db.execute(query)
        return list(result.scalars().all())

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
            .options(selectinload(DistributionTarget.bot_chat))
            .where(DistributionTarget.rule_id == rule_id)
            .order_by(DistributionTarget.created_at.asc())
        )
        return list(result.scalars().all())

    async def get_target_by_id(self, target_id: int, rule_id: Optional[int] = None) -> Optional[DistributionTarget]:
        stmt = (
            select(DistributionTarget)
            .options(selectinload(DistributionTarget.bot_chat))
            .where(DistributionTarget.id == target_id)
        )
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
