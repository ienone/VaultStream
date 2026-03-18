"""
M4: 分发引擎模块。

处理内容匹配和任务创建。
"""
from typing import List
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession
from datetime import datetime

from app.core.logging import logger
from app.models import Content, DistributionRule, ReviewStatus
from .decision import check_match_conditions, DECISION_FILTERED


class DistributionEngine:
    """分发引擎：匹配内容规则并创建任务。"""

    def __init__(self, db: AsyncSession):
        self.db = db
        from app.repositories import ContentRepository, DistributionRepository
        self.content_repo = ContentRepository(db)
        self.dist_repo = DistributionRepository(db)

    async def match_rules(self, content: Content) -> List[DistributionRule]:
        """为给定内容匹配规则。"""
        all_rules = await self.dist_repo.list_rules(enabled=True)

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
        """如果命中任一“免审批”规则，则自动批准内容。"""
        result = await self.db.execute(
            select(DistributionRule).where(DistributionRule.enabled == True)
        )
        all_rules = result.scalars().all()

        for rule in all_rules:
            if rule.approval_required:
                continue

            if await self._check_match(content, rule):
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
                    from .scheduler import enqueue_content_background
                    await enqueue_content_background(content.id)
                except Exception as e:
                    logger.warning(f"Failed to enqueue after auto-approve: {e}")
                
                return True

        return False

    async def refresh_queue_by_rules(self):
        """根据规则变更刷新自动审批状态（仅基于 match_conditions + approval_required）。"""
        contents = await self.content_repo.list_parsed_contents()
        enabled_rules = await self.dist_repo.list_rules(enabled=True)

        changes = 0
        auto_approved_ids: list[int] = []

        async def _matches_any_auto_approve_rule(content: Content) -> bool:
            for rule in enabled_rules:
                if rule.approval_required:
                    continue
                if await self._check_match(content, rule):
                    return True
            return False

        for content in contents:
            if content.review_status == ReviewStatus.AUTO_APPROVED:
                still_valid = await _matches_any_auto_approve_rule(content)
                if not still_valid:
                    content.review_status = ReviewStatus.PENDING
                    content.review_note = "Rule update requires manual review"
                    changes += 1

            elif content.review_status == ReviewStatus.PENDING:
                if await _matches_any_auto_approve_rule(content):
                    content.review_status = ReviewStatus.AUTO_APPROVED
                    content.reviewed_at = datetime.utcnow()
                    content.review_note = "Rule update auto-approved"
                    changes += 1
                    auto_approved_ids.append(int(content.id))

        if changes > 0:
            await self.db.commit()
            logger.info("Rules updated: %s content status changes", changes)

        if auto_approved_ids:
            from .scheduler import enqueue_content_background

            for content_id in auto_approved_ids:
                try:
                    await enqueue_content_background(content_id)
                except Exception as e:
                    logger.warning("Failed to enqueue after refresh auto-approve: {}", e)
