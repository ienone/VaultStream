"""
M4: 分发引擎模块。

处理内容匹配和任务创建。
"""
from typing import List, Dict, Any
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession
from datetime import datetime

from app.core.logging import logger
from app.models import Content, ContentStatus, DistributionRule, ReviewStatus
from app.distribution.decision import check_match_conditions, check_auto_approve_conditions, DECISION_FILTERED


class DistributionEngine:
    """分发引擎：匹配内容规则并创建任务。"""

    def __init__(self, db: AsyncSession):
        self.db = db

    async def match_rules(self, content: Content) -> List[DistributionRule]:
        """为给定内容匹配规则。"""
        result = await self.db.execute(
            select(DistributionRule)
            .where(DistributionRule.enabled == True)
            .order_by(DistributionRule.priority.desc(), DistributionRule.id)
        )
        all_rules = result.scalars().all()

        logger.debug(f"Matching rules for content {content.id}, total {len(all_rules)} enabled")

        matched_rules = []
        for rule in all_rules:
            if await self._check_match(content, rule):
                matched_rules.append(rule)

        return matched_rules

    async def _check_match(self, content: Content, rule: DistributionRule) -> bool:
        """检查内容是否匹配规则条件。"""
        decision = check_match_conditions(content, rule.match_conditions or {})
        return decision.bucket != DECISION_FILTERED

    async def auto_approve_if_eligible(self, content: Content) -> bool:
        """如果符合规则标准，则自动批准内容。"""
        result = await self.db.execute(
            select(DistributionRule).where(DistributionRule.enabled == True)
        )
        all_rules = result.scalars().all()

        for rule in all_rules:
            if not rule.auto_approve_conditions:
                continue

            if await self._check_auto_approve_conditions(content, rule.auto_approve_conditions):
                content.review_status = ReviewStatus.AUTO_APPROVED
                content.reviewed_at = datetime.utcnow()
                content.review_note = f"Auto-approved (rule: {rule.name})"

                await self.db.commit()

                logger.info(
                    "Content auto-approved: content_id=%s",
                    content.id,
                )
                
                # 自动审批后触发队列入队
                try:
                    from app.distribution.queue_service import enqueue_content_background
                    await enqueue_content_background(content.id)
                except Exception as e:
                    logger.warning(f"Failed to enqueue after auto-approve: {e}")
                
                return True

        return False

    async def _check_auto_approve_conditions(
        self,
        content: Content,
        conditions: Dict[str, Any],
    ) -> bool:
        """检查自动批准条件。"""
        return check_auto_approve_conditions(content, conditions)

    async def refresh_queue_by_rules(self):
        """根据更新的规则刷新队列。"""
        result = await self.db.execute(
            select(Content).where(Content.status == ContentStatus.PARSE_SUCCESS)
        )
        contents = result.scalars().all()

        rule_result = await self.db.execute(
            select(DistributionRule).where(DistributionRule.enabled == True)
        )
        enabled_rules = rule_result.scalars().all()

        changes = 0
        for content in contents:
            if content.review_status == ReviewStatus.AUTO_APPROVED:
                still_valid = False
                for rule in enabled_rules:
                    if rule.auto_approve_conditions and await self._check_auto_approve_conditions(
                        content, rule.auto_approve_conditions
                    ):
                        still_valid = True
                        break

                if not still_valid:
                    content.review_status = ReviewStatus.PENDING
                    changes += 1

            elif content.review_status == ReviewStatus.PENDING:
                for rule in enabled_rules:
                    if rule.auto_approve_conditions and await self._check_auto_approve_conditions(
                        content, rule.auto_approve_conditions
                    ):
                        content.review_status = ReviewStatus.AUTO_APPROVED
                        content.reviewed_at = datetime.utcnow()
                        content.review_note = f"Rule update auto-approved (rule: {rule.name})"
                        changes += 1
                        break

        if changes > 0:
            await self.db.commit()
            logger.info("Rules updated: %s content status changes", changes)
