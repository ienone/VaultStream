from datetime import timedelta
from typing import List, Optional, Dict, Any, Tuple
from sqlalchemy import select, desc, and_, update
from sqlalchemy.orm import selectinload
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.distribution import DistributionRule, DistributionTarget
from app.models.system import ContentQueueItem, PushedRecord, QueueItemStatus
from app.models.content import Content, ContentStatus, ReviewStatus
from app.models.bot import BotChat
from app.schemas.distribution import (
    DistributionRuleCreate, 
    DistributionRuleUpdate,
    DistributionTargetCreate, 
    DistributionTargetUpdate,
    BatchTargetUpdateRequest,
    RulePreviewStats,
    RulePreviewItem,
    RulePreviewResponse
)
from app.constants import Platform
from app.services.distribution.decision import (
    DECISION_FILTERED,
    DECISION_PENDING_REVIEW,
    DECISION_WILL_PUSH,
    DistributionDecision,
    check_match_conditions,
    should_distribute,
)
from app.media.extractor import pick_preview_thumbnail
from fastapi import HTTPException
from app.repositories import DistributionRepository, BotRepository, ContentRepository
from app.core.events import event_bus
from app.core.time_utils import utcnow


class DistributionRuleService:
    def __init__(self, db: AsyncSession):
        self.db = db
        self.repo = DistributionRepository(db)
        self.bot_repo = BotRepository(db)
        self.content_repo = ContentRepository(db)

    # -------------------------
    # Rule Management
    # -------------------------
    
    async def create_rule(self, rule_in: DistributionRuleCreate) -> DistributionRule:
        rule_exists = await self.repo.get_rule_by_name(rule_in.name)
        if rule_exists:
            raise HTTPException(status_code=400, detail="Rule name already exists")
        
        db_rule = await self.repo.create_rule(**rule_in.model_dump())
        await self.db.commit()
        await self.db.refresh(db_rule)
        return db_rule

    async def list_rules(self, enabled: Optional[bool] = None) -> List[DistributionRule]:
        return await self.repo.list_rules(enabled=enabled)

    async def get_rule(self, rule_id: int) -> DistributionRule:
        rule = await self.repo.get_rule_by_id(rule_id)
        if not rule:
            raise HTTPException(status_code=404, detail="Distribution rule not found")
        return rule

    async def update_rule(self, rule_id: int, rule_update: DistributionRuleUpdate) -> DistributionRule:
        db_rule = await self.get_rule(rule_id)
        
        update_data = rule_update.model_dump(exclude_unset=True)
        for key, value in update_data.items():
            setattr(db_rule, key, value)
        
        await self.db.commit()
        await self.db.refresh(db_rule)
        return db_rule

    async def delete_rule(self, rule_id: int) -> None:
        db_rule = await self.get_rule(rule_id)
        await self.repo.delete_rule(db_rule)
        await self.db.commit()

    # -------------------------
    # Target Management for Rule
    # -------------------------
    
    async def list_rule_targets(self, rule_id: int) -> List[DistributionTarget]:
        await self.get_rule(rule_id) # Ensure rule exists
        return await self.repo.list_rule_targets(rule_id)

    async def create_rule_target(self, rule_id: int, target_in: DistributionTargetCreate) -> Tuple[DistributionTarget, int]:
        rule = await self.get_rule(rule_id)
        
        chat = await self.bot_repo.get_chat_by_id(target_in.bot_chat_id)
        if not chat:
            raise HTTPException(status_code=404, detail="BotChat not found")

        existing = await self.repo.get_target_by_chat(rule_id, target_in.bot_chat_id)
        if existing:
            raise HTTPException(status_code=400, detail=f"Target already exists for rule '{rule.name}' and chat '{chat.chat_id}'")

        now = utcnow()
        backfill_mode = target_in.backfill_mode
        if backfill_mode == "all_history":
            backfill_watermark = None
        elif backfill_mode == "recent_days":
            backfill_watermark = now - timedelta(days=target_in.backfill_recent_days or 1)
        else:
            backfill_watermark = now

        target_data = target_in.model_dump(
            exclude={"backfill_mode", "backfill_recent_days"}
        )
        target_data["backfill_watermark"] = backfill_watermark
        db_target = await self.repo.create_target(
            rule_id=rule_id,
            **target_data
        )

        inserted_records = 0
        if backfill_mode != "new_only" and db_target.enabled and chat.enabled:
            inserted_records = await self._backfill_target_queue(
                rule=rule,
                target=db_target,
                bot_chat=chat,
                since=backfill_watermark,
            )

        await self.db.commit()
        await self.db.refresh(db_target)
        db_target.bot_chat = chat  # Fix pydantic validation for DistributionTargetResponse
        if inserted_records > 0:
            await event_bus.publish("queue_updated", {
                "action": "target_backfill",
                "rule_id": rule_id,
                "target_id": db_target.id,
                "bot_chat_id": chat.id,
                "items_changed": inserted_records,
                "timestamp": utcnow().isoformat(),
            })
        return db_target, inserted_records

    async def _backfill_target_queue(
        self,
        *,
        rule: DistributionRule,
        target: DistributionTarget,
        bot_chat: BotChat,
        since,
    ) -> int:
        if not rule.enabled or not target.enabled or not bot_chat.enabled:
            return 0

        conditions = [
            Content.status == ContentStatus.PARSE_SUCCESS,
            Content.review_status.in_([ReviewStatus.APPROVED, ReviewStatus.AUTO_APPROVED]),
        ]
        if since is not None:
            conditions.append(Content.created_at >= since)

        contents = (
            await self.db.execute(
                select(Content).where(and_(*conditions)).order_by(Content.created_at.desc())
            )
        ).scalars().all()
        if not contents:
            return 0

        existing_rows = (
            await self.db.execute(
                select(ContentQueueItem.content_id).where(
                    ContentQueueItem.rule_id == rule.id,
                    ContentQueueItem.bot_chat_id == bot_chat.id,
                )
            )
        ).scalars().all()
        existing_content_ids = {int(content_id) for content_id in existing_rows}

        inserted = 0
        for content in contents:
            if content.id in existing_content_ids:
                continue
            if (
                rule.approval_required
                and content.review_status == ReviewStatus.AUTO_APPROVED
            ):
                continue
            if check_match_conditions(content, rule.match_conditions or {}).bucket == DECISION_FILTERED:
                continue

            decision = should_distribute(
                content=content,
                rule=rule,
                bot_chat=bot_chat,
                require_approval=False,
            )
            if decision.bucket == DECISION_FILTERED:
                continue

            self.db.add(
                ContentQueueItem(
                    content_id=content.id,
                    rule_id=rule.id,
                    bot_chat_id=bot_chat.id,
                    target_platform=bot_chat.platform_type,
                    target_id=decision.target_id or bot_chat.chat_id,
                    status=QueueItemStatus.SCHEDULED,
                    priority=rule.priority + content.queue_priority,
                    scheduled_at=utcnow(),
                    nsfw_routing_result=decision.nsfw_routing_result,
                )
            )
            inserted += 1

        return inserted

    async def update_rule_target(self, rule_id: int, target_id: int, update_in: DistributionTargetUpdate) -> DistributionTarget:
        db_target = await self.repo.get_target_by_id(target_id, rule_id=rule_id)
        if not db_target:
            raise HTTPException(status_code=404, detail="Target not found")

        update_data = update_in.model_dump(exclude_unset=True)
        for key, value in update_data.items():
            setattr(db_target, key, value)

        await self.db.commit()
        await self.db.refresh(db_target)
        return db_target

    async def delete_rule_target(self, rule_id: int, target_id: int) -> None:
        db_target = await self.repo.get_target_by_id(target_id, rule_id=rule_id)
        if not db_target:
            raise HTTPException(status_code=404, detail="Target not found")

        await self.repo.delete_target(db_target)
        await self.db.commit()

    # -------------------------
    # Preview Logic
    # -------------------------

    async def preview_rule(self, rule_id: int, hours_ahead: int = 24, limit: int = 50) -> RulePreviewResponse:
        rule = await self.repo.get_rule_by_id(rule_id)
        if not rule:
            raise HTTPException(status_code=404, detail="Distribution rule not found")
        
        # 为了预览，我们需要加载 targets
        result = await self.db.execute(
            select(DistributionRule)
            .options(
                selectinload(DistributionRule.distribution_targets)
                .selectinload(DistributionTarget.bot_chat)
            )
            .where(DistributionRule.id == rule_id)
        )
        rule = result.scalar_one()

        contents, _ = await self.content_repo.list_contents(
            size=limit * 2,
            statuses=[ContentStatus.PARSE_SUCCESS.value],
            include_archive_metadata=True
        )
        
        preview_items: List[RulePreviewItem] = []
        will_push_count = 0
        filtered_count = 0
        pending_review_count = 0
        
        chats = [
            target.bot_chat
            for target in rule.distribution_targets
            if target.enabled and target.bot_chat and target.bot_chat.enabled
        ]
        
        for content in contents:
            if len(preview_items) >= limit:
                break
            
            decision = self._resolve_preview_decision(content=content, rule=rule, chats=chats)
            status = decision.bucket

            if status == DECISION_WILL_PUSH:
                will_push_count += 1
            elif status == DECISION_FILTERED:
                filtered_count += 1
            elif status == DECISION_PENDING_REVIEW:
                pending_review_count += 1
            
            thumbnail = pick_preview_thumbnail(
                content.archive_metadata or {},
                cover_url=content.cover_url,
            )
            
            preview_items.append(RulePreviewItem(
                content_id=content.id,
                title=content.title,
                platform=content.platform.value,
                tags=content.tags or [],
                is_nsfw=content.is_nsfw,
                status=status,
                reason_code=decision.reason_code,
                reason=decision.reason,
                scheduled_time=content.created_at,
                thumbnail_url=thumbnail
            ))
        
        return RulePreviewResponse(
            rule_id=rule.id,
            rule_name=rule.name,
            total_matched=len(preview_items),
            will_push_count=will_push_count,
            filtered_count=filtered_count,
            pending_review_count=pending_review_count,
            items=preview_items
        )

    async def get_all_rules_preview_stats(self) -> List[RulePreviewStats]:
        rules = await self.repo.list_rules(enabled=True)
        
        stats_list: List[RulePreviewStats] = []
        
        for rule in rules:
            contents, _ = await self.content_repo.list_contents(
                size=100,
                statuses=[ContentStatus.PARSE_SUCCESS.value]
            )
            
            will_push = 0
            filtered = 0
            pending_review = 0

            # 加载启用且关联了启用配置的目标
            targets = await self.repo.list_rule_targets(rule.id)
            chats = []
            for t in targets:
                if t.enabled:
                    # 获取详细 chat 信息
                    chat = await self.bot_repo.get_chat_by_id(t.bot_chat_id)
                    if chat and chat.enabled:
                        chats.append(chat)
            
            for content in contents:
                decision = self._resolve_preview_decision(content=content, rule=rule, chats=chats)
                if decision.bucket == DECISION_FILTERED:
                    filtered += 1
                elif decision.bucket == DECISION_PENDING_REVIEW:
                    pending_review += 1
                else:
                    will_push += 1
            
            stats_list.append(RulePreviewStats(
                rule_id=rule.id,
                rule_name=rule.name,
                will_push=will_push,
                filtered=filtered,
                pending_review=pending_review,
                total_matched=will_push + pending_review + filtered
            ))
        
        return stats_list

    def _resolve_preview_decision(
        self,
        *,
        content: Content,
        rule: DistributionRule,
        chats: List[BotChat],
    ) -> DistributionDecision:
        if not chats:
            return DistributionDecision(
                bucket=DECISION_FILTERED,
                reason_code="no_enabled_targets",
                reason="规则没有可用目标",
            )

        pending_decision: Optional[DistributionDecision] = None
        first_filtered: Optional[DistributionDecision] = None

        for chat in chats:
            decision = should_distribute(
                content=content,
                rule=rule,
                bot_chat=chat,
                require_approval=True,
            )
            if decision.bucket == DECISION_WILL_PUSH:
                return decision
            if decision.bucket == DECISION_PENDING_REVIEW and pending_decision is None:
                pending_decision = decision
            if decision.bucket == DECISION_FILTERED and first_filtered is None:
                first_filtered = decision

        return pending_decision or first_filtered or DistributionDecision(
            bucket=DECISION_FILTERED,
            reason_code="no_eligible_target",
            reason="无可用目标",
        )
