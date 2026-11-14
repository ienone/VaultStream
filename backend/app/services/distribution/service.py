"""
Distribution business entrypoint.

This service owns rule matching, auto-approval, and queue
enqueue decisions.
"""
from sqlalchemy import select, update
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.events import event_bus
from app.core.logging import logger
from app.core.time_utils import utcnow
from app.models import (
    BotChat,
    BotConfig,
    Content,
    ContentQueueItem,
    ContentStatus,
    DistributionRule,
    DistributionTarget,
    QueueItemStatus,
    ReviewStatus,
)
from app.services.automation_policy import AutomationPolicyService
from app.services.distribution.delivery_state import delivery_is_resolved
from app.services.distribution.receipt_policy import EXPLICIT_PUSH, has_qq_agent_receipt
from app.services.distribution.decision import (
    DECISION_FILTERED,
    DECISION_PENDING_REVIEW,
    should_distribute,
)


class DistributionService:
    """Single business entrypoint for distribution decisions and queueing."""

    def __init__(self, db: AsyncSession):
        self.db = db

    async def enqueue_content(
        self, content_id: int, *, force: bool = False, manual: bool = False,
        bot_chat_id: int | None = None, auto_approve: bool = False,
    ) -> int:
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

        if not (await AutomationPolicyService().aggregation_delivery(content)).allowed:
            return 0
        if content.deleted_at is not None:
            return 0
        if content.status != ContentStatus.PARSE_SUCCESS:
            logger.info(
                f"Content not eligible (status): content_id={content_id}, status={content.status}"
            )
            return 0

        if content.review_status == ReviewStatus.REJECTED:
            logger.info(
                f"Content not eligible (review): content_id={content_id}, "
                f"review_status={content.review_status}"
            )
            return 0

        targets = (await self.db.execute(select(DistributionRule, DistributionTarget, BotChat)
            .join(DistributionTarget, DistributionTarget.rule_id == DistributionRule.id)
            .join(BotChat, BotChat.id == DistributionTarget.bot_chat_id)
            .join(BotConfig, BotConfig.id == BotChat.bot_config_id)
            .where(DistributionRule.enabled.is_(True), DistributionTarget.enabled.is_(True),
                   BotChat.enabled.is_(True), BotChat.is_accessible.is_(True), BotChat.is_push_target.is_(True),
                   BotConfig.enabled.is_(True), BotConfig.is_primary.is_(True))
            .order_by(DistributionRule.priority.desc(), DistributionRule.id, BotChat.id)
        )).all()
        if not targets:
            return 0
        existing_items = {(item.rule_id, item.bot_chat_id): item for item in await self.db.scalars(
            select(ContentQueueItem).where(ContentQueueItem.content_id == content_id)
        )}
        count = 0
        for rule, target, bot_chat in targets:
            if bot_chat_id is not None and bot_chat.id != bot_chat_id:
                continue
            if (
                target.backfill_watermark is not None
                and content.created_at is not None
                and content.created_at < target.backfill_watermark
            ):
                continue

            existing = existing_items.get((rule.id, bot_chat.id))
            awaiting_review = existing is not None and existing.last_error_type == "approval_required"
            if existing and not awaiting_review and not manual and not (force and existing.status == QueueItemStatus.FAILED):
                continue

            decision = should_distribute(
                content=content,
                rule=rule,
                bot_chat=bot_chat,
            )

            if decision.bucket == DECISION_FILTERED:
                continue

            target_id = decision.target_id or bot_chat.chat_id
            if not manual and await has_qq_agent_receipt(self.db, content_id, bot_chat, target_id):
                continue

            needs_approval = decision.bucket == DECISION_PENDING_REVIEW
            if existing:
                if awaiting_review and needs_approval:
                    continue
                if manual and existing.status == QueueItemStatus.SCHEDULED and existing.approved_by != EXPLICIT_PUSH:
                    existing.approved_by = EXPLICIT_PUSH
                    count += 1
                if existing.status == QueueItemStatus.SUCCESS and not force:
                    logger.debug(
                        f"Queue item already succeeded: content_id={content_id}, "
                        f"rule_id={rule.id}, bot_chat_id={bot_chat.id}"
                    )
                    continue

                if existing.status == QueueItemStatus.FAILED and (awaiting_review or (force and not needs_approval)):
                    reset = await self.db.execute(update(ContentQueueItem).where(
                        ContentQueueItem.id == existing.id,
                        ContentQueueItem.status == QueueItemStatus.FAILED,
                        delivery_is_resolved(),
                        ContentQueueItem.last_error_type == "approval_required" if awaiting_review else True,
                    ).values(
                        status=QueueItemStatus.SCHEDULED, attempt_count=0,
                        last_error=None, last_error_type=None, last_error_at=None,
                        next_attempt_at=None, target_id=target_id,
                        approved_by=EXPLICIT_PUSH if manual else existing.approved_by,
                        scheduled_at=utcnow(), updated_at=utcnow(),
                    ).execution_options(synchronize_session=False))
                    if reset.rowcount != 1:
                        continue
                    await self.db.refresh(existing)
                    count += 1
                    logger.info(
                        f"Queue item reset to SCHEDULED: content_id={content_id}, "
                        f"rule_id={rule.id}, bot_chat_id={bot_chat.id}"
                    )
                    continue

                continue

            if content.review_status == ReviewStatus.PENDING and not needs_approval:
                if not auto_approve:
                    continue
                updated = await self.db.execute(update(Content).where(
                    Content.id == content.id, Content.review_status == ReviewStatus.PENDING,
                    Content.deleted_at.is_(None),
                ).values(review_status=ReviewStatus.AUTO_APPROVED, reviewed_at=utcnow(),
                         review_note=f"Auto-approved (rule: {rule.name})"))
                if not updated.rowcount:
                    await self.db.refresh(content)
                    if content.review_status not in (ReviewStatus.APPROVED, ReviewStatus.AUTO_APPROVED):
                        continue
            item = ContentQueueItem(
                content_id=content_id,
                rule_id=rule.id,
                bot_chat_id=bot_chat.id,
                target_platform=bot_chat.platform_type,
                target_id=target_id,
                status=QueueItemStatus.FAILED if needs_approval else QueueItemStatus.SCHEDULED,
                last_error_type="approval_required" if needs_approval else None,
                last_error="等待确认发送" if needs_approval else None,
                priority=rule.priority + content.queue_priority,
                scheduled_at=utcnow(),
                approved_by=EXPLICIT_PUSH if manual else None,
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
                f"targets_checked={len(targets)}, "
                f"items_created_or_updated={count}"
            )

        return count
