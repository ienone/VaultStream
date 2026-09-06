"""
Distribution business entrypoint.

This service owns rule matching, auto-approval, rule refresh, and queue
enqueue decisions.
"""
from sqlalchemy import and_, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.events import event_bus
from app.core.logging import logger
from app.core.time_utils import utcnow
from app.models import (
    BotChat,
    Content,
    ContentQueueItem,
    ContentStatus,
    DistributionRule,
    DistributionTarget,
    QueueItemStatus,
    ReviewStatus,
)
from app.repositories import ContentRepository, DistributionRepository
from app.services.automation_policy import AutomationPolicyService
from app.services.distribution.decision import (
    DECISION_FILTERED,
    check_match_conditions,
    should_distribute,
)


class DistributionService:
    """Single business entrypoint for distribution decisions and queueing."""

    def __init__(self, db: AsyncSession):
        self.db = db
        self.content_repo = ContentRepository(db)
        self.dist_repo = DistributionRepository(db)

    def _check_match(self, content: Content, rule: DistributionRule) -> bool:
        decision = check_match_conditions(content, rule.match_conditions or {})
        return decision.bucket != DECISION_FILTERED

    async def auto_approve_if_eligible(self, content: Content) -> bool:
        """Auto-approve content when it matches any non-approval-required rule."""
        policy = await AutomationPolicyService().distribution_enqueue(force=False)
        if not policy.allowed:
            logger.bind(
                component="distribution",
                content_id=content.id,
                policy=policy.as_dict(),
            ).info("Content auto-approval skipped by automation policy")
            return False

        result = await self.db.execute(
            select(DistributionRule).where(DistributionRule.enabled == True)
        )
        all_rules = result.scalars().all()

        for rule in all_rules:
            if rule.approval_required:
                continue

            if self._check_match(content, rule):
                content.review_status = ReviewStatus.AUTO_APPROVED
                content.reviewed_at = utcnow()
                content.review_note = f"Auto-approved (rule: {rule.name})"

                await self.db.commit()

                logger.info(
                    "Content auto-approved: content_id=%s",
                    content.id,
                )

                try:
                    await self.enqueue_content(content.id)
                except Exception as e:
                    logger.warning(f"Failed to enqueue after auto-approve: {e}")

                return True

        return False

    async def refresh_queue_by_rules(self) -> None:
        """Refresh auto-approval status after rule changes."""
        policy = await AutomationPolicyService().distribution_enqueue(force=False)
        allow_auto_approval = policy.allowed
        contents = await self.content_repo.list_parsed_contents()
        enabled_rules = await self.dist_repo.list_rules(enabled=True)

        changes = 0
        auto_approved_ids: list[int] = []

        def matches_any_auto_approve_rule(content: Content) -> bool:
            for rule in enabled_rules:
                if rule.approval_required:
                    continue
                if self._check_match(content, rule):
                    return True
            return False

        for content in contents:
            if content.review_status == ReviewStatus.AUTO_APPROVED:
                still_valid = matches_any_auto_approve_rule(content)
                if not still_valid:
                    content.review_status = ReviewStatus.PENDING
                    content.review_note = "Rule update requires manual review"
                    changes += 1

            elif allow_auto_approval and content.review_status == ReviewStatus.PENDING:
                if matches_any_auto_approve_rule(content):
                    content.review_status = ReviewStatus.AUTO_APPROVED
                    content.reviewed_at = utcnow()
                    content.review_note = "Rule update auto-approved"
                    changes += 1
                    auto_approved_ids.append(int(content.id))

        if changes > 0:
            await self.db.commit()
            logger.info("Rules updated: %s content status changes", changes)

        if not allow_auto_approval:
            logger.bind(
                component="distribution",
                policy=policy.as_dict(),
            ).info("Rule refresh auto-approval skipped by automation policy")

        for content_id in auto_approved_ids:
            try:
                await self.enqueue_content(content_id)
            except Exception as e:
                logger.warning("Failed to enqueue after refresh auto-approve: {}", e)

    async def enqueue_content(self, content_id: int, *, force: bool = False) -> int:
        """Create or update distribution queue items for content."""
        policy = await AutomationPolicyService().distribution_enqueue(force=force)
        if not policy.allowed:
            logger.bind(
                component="distribution",
                content_id=content_id,
                policy=policy.as_dict(),
            ).info("Distribution enqueue skipped by automation policy")
            return 0

        result = await self.db.execute(select(Content).where(Content.id == content_id))
        content = result.scalar_one_or_none()

        if not content:
            logger.warning(f"Content not found: content_id={content_id}")
            return 0

        if content.status != ContentStatus.PARSE_SUCCESS:
            logger.info(
                f"Content not eligible (status): content_id={content_id}, status={content.status}"
            )
            return 0

        if content.review_status not in (
            ReviewStatus.APPROVED,
            ReviewStatus.AUTO_APPROVED,
        ):
            logger.info(
                f"Content not eligible (review): content_id={content_id}, "
                f"review_status={content.review_status}"
            )
            return 0

        rules_result = await self.db.execute(
            select(DistributionRule).where(DistributionRule.enabled == True)
        )
        enabled_rules = rules_result.scalars().all()

        if not enabled_rules:
            logger.info(f"No enabled rules for content: content_id={content_id}")
            return 0

        rule_ids = [r.id for r in enabled_rules]
        targets_result = await self.db.execute(
            select(DistributionTarget, BotChat)
            .join(BotChat, DistributionTarget.bot_chat_id == BotChat.id)
            .where(DistributionTarget.rule_id.in_(rule_ids))
            .where(DistributionTarget.enabled == True)
            .where(BotChat.enabled == True)
            .where(BotChat.is_accessible == True)
        )

        rule_targets: dict[int, list[tuple[DistributionTarget, BotChat]]] = {}
        for target, bot_chat in targets_result.all():
            rule_targets.setdefault(target.rule_id, []).append((target, bot_chat))

        existing_result = await self.db.execute(
            select(ContentQueueItem).where(
                and_(
                    ContentQueueItem.content_id == content_id,
                    ContentQueueItem.rule_id.in_(rule_ids),
                )
            )
        )
        existing_items: dict[tuple[int, int], ContentQueueItem] = {
            (item.rule_id, item.bot_chat_id): item
            for item in existing_result.scalars().all()
        }

        rules_map = {r.id: r for r in enabled_rules}
        count = 0

        for rule_id, pairs in rule_targets.items():
            rule = rules_map.get(rule_id)
            if not rule:
                continue

            for target, bot_chat in pairs:
                if (
                    target.backfill_watermark is not None
                    and content.created_at is not None
                    and content.created_at < target.backfill_watermark
                ):
                    continue

                if (
                    rule.approval_required
                    and content.review_status == ReviewStatus.AUTO_APPROVED
                ):
                    continue

                decision = should_distribute(
                    content=content,
                    rule=rule,
                    bot_chat=bot_chat,
                    require_approval=False,
                )

                if decision.bucket == DECISION_FILTERED:
                    continue

                target_id = decision.target_id or bot_chat.chat_id

                key = (rule.id, bot_chat.id)
                existing = existing_items.get(key)

                if existing:
                    if existing.status == QueueItemStatus.SUCCESS and not force:
                        logger.debug(
                            f"Queue item already succeeded: content_id={content_id}, "
                            f"rule_id={rule.id}, bot_chat_id={bot_chat.id}"
                        )
                        continue

                    if existing.status == QueueItemStatus.FAILED and force:
                        existing.status = QueueItemStatus.SCHEDULED
                        existing.attempt_count = 0
                        existing.last_error = None
                        existing.last_error_type = None
                        existing.last_error_at = None
                        existing.next_attempt_at = None
                        existing.target_id = target_id
                        existing.nsfw_routing_result = decision.nsfw_routing_result
                        existing.scheduled_at = utcnow()
                        existing.updated_at = utcnow()
                        count += 1
                        logger.info(
                            f"Queue item reset to SCHEDULED: content_id={content_id}, "
                            f"rule_id={rule.id}, bot_chat_id={bot_chat.id}"
                        )
                        continue

                    continue

                item = ContentQueueItem(
                    content_id=content_id,
                    rule_id=rule.id,
                    bot_chat_id=bot_chat.id,
                    target_platform=bot_chat.platform_type,
                    target_id=target_id,
                    status=QueueItemStatus.SCHEDULED,
                    priority=rule.priority + content.queue_priority,
                    scheduled_at=utcnow(),
                    nsfw_routing_result=decision.nsfw_routing_result,
                )
                self.db.add(item)
                count += 1

        if count > 0:
            await self.db.commit()
            await event_bus.publish(
                "queue_updated",
                {
                    "action": "enqueue",
                    "content_id": content_id,
                    "items_changed": count,
                    "timestamp": utcnow().isoformat(),
                },
            )
            logger.info(
                f"Enqueued content: content_id={content_id}, "
                f"rules_scanned={len(enabled_rules)}, "
                f"items_created_or_updated={count}"
            )

        return count
