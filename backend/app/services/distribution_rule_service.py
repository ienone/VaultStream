from typing import List, Optional, Dict, Any, Tuple
from sqlalchemy import select, desc, and_, update
from sqlalchemy.orm import selectinload
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.distribution import DistributionRule, DistributionTarget
from app.models.system import PushedRecord
from app.models.content import Content, ContentStatus
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
    evaluate_target_decision,
)
from app.media.extractor import pick_preview_thumbnail
from app.services.distribution.scheduler import mark_historical_parse_success_as_pushed_for_rule
from app.core.exceptions import NotFoundException, BadRequestException
from app.repositories import DistributionRepository, BotRepository, ContentRepository


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
            raise BadRequestException("Rule name already exists")
        
        db_rule = await self.repo.create_rule(**rule_in.model_dump())
        await self.db.commit()
        await self.db.refresh(db_rule)
        return db_rule

    async def list_rules(self, enabled: Optional[bool] = None) -> List[DistributionRule]:
        return await self.repo.list_rules(enabled=enabled)

    async def get_rule(self, rule_id: int) -> DistributionRule:
        rule = await self.repo.get_rule_by_id(rule_id)
        if not rule:
            raise NotFoundException("Distribution rule not found")
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
            raise NotFoundException("BotChat not found")

        existing = await self.repo.get_target_by_chat(rule_id, target_in.bot_chat_id)
        if existing:
            raise BadRequestException(f"Target already exists for rule '{rule.name}' and chat '{chat.chat_id}'")

        db_target = await self.repo.create_target(
            rule_id=rule_id,
            **target_in.model_dump()
        )

        inserted_records = await mark_historical_parse_success_as_pushed_for_rule(
            session=self.db,
            rule_id=rule_id,
            bot_chat_id=target_in.bot_chat_id,
        )

        await self.db.commit()
        await self.db.refresh(db_target)
        return db_target, inserted_records

    async def update_rule_target(self, rule_id: int, target_id: int, update_in: DistributionTargetUpdate) -> DistributionTarget:
        db_target = await self.repo.get_target_by_id(target_id, rule_id=rule_id)
        if not db_target:
            raise NotFoundException("Target not found")

        update_data = update_in.model_dump(exclude_unset=True)
        for key, value in update_data.items():
            setattr(db_target, key, value)

        await self.db.commit()
        await self.db.refresh(db_target)
        return db_target

    async def delete_rule_target(self, rule_id: int, target_id: int) -> None:
        db_target = await self.repo.get_target_by_id(target_id, rule_id=rule_id)
        if not db_target:
            raise NotFoundException("Target not found")

        await self.repo.delete_target(db_target)
        await self.db.commit()

    # -------------------------
    # Preview Logic
    # -------------------------

    async def preview_rule(self, rule_id: int, hours_ahead: int = 24, limit: int = 50) -> RulePreviewResponse:
        rule = await self.repo.get_rule_by_id(rule_id)
        if not rule:
            raise NotFoundException("Distribution rule not found")
        
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
            statuses=[ContentStatus.PARSE_SUCCESS.value]
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
            decision = evaluate_target_decision(
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
