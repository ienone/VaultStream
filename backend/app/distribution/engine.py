"""
M4: 分发引擎模块。

处理内容匹配和任务创建。
"""
from typing import List, Dict, Any, Optional
from sqlalchemy import select, and_
from sqlalchemy.ext.asyncio import AsyncSession
from datetime import datetime, timedelta

from app.core.logging import logger
from app.models import Content, DistributionRule, PushedRecord, ReviewStatus, Platform, DistributionTarget, BotChat
from app.schemas import ShareCardPreview, OptimizedMedia


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
        conditions = rule.match_conditions

        if not conditions:
            return True

        if "platform" in conditions and conditions["platform"]:
            if conditions["platform"] != content.platform.value:
                return False

        if "tags" in conditions:
            required_tags = conditions["tags"]
            if isinstance(required_tags, list) and required_tags:
                content_tags = [t.lower() for t in (content.tags or [])]
                required_tags_lower = [t.lower() for t in required_tags]

                tags_match_mode = conditions.get("tags_match_mode", "any")

                if tags_match_mode == "all":
                    if not all(tag in content_tags for tag in required_tags_lower):
                        return False
                else:
                    if not any(tag in content_tags for tag in required_tags_lower):
                        return False

        if "tags_exclude" in conditions:
            exclude_tags = conditions["tags_exclude"]
            if isinstance(exclude_tags, list) and exclude_tags:
                content_tags = [t.lower() for t in (content.tags or [])]
                exclude_tags_lower = [t.lower() for t in exclude_tags]
                if any(tag in content_tags for tag in exclude_tags_lower):
                    return False

        if "is_nsfw" in conditions:
            if conditions["is_nsfw"] != content.is_nsfw:
                return False

        if rule.approval_required:
            if content.review_status not in [ReviewStatus.APPROVED, ReviewStatus.AUTO_APPROVED]:
                return False

        return True

    async def check_nsfw_policy(self, content: Content, rule: DistributionRule) -> bool:
        """检查分发时的 NSFW 策略。"""
        if not content.is_nsfw:
            return True

        if content.review_status == ReviewStatus.APPROVED:
            logger.info(f"Manual approval bypasses NSFW check: content_id={content.id}")
            return True

        policy = rule.nsfw_policy

        if policy == "block":
            logger.warning(f"NSFW blocked: content_id={content.id}, rule={rule.name}")
            return False
        if policy == "allow":
            return True
        if policy == "separate_channel":
            logger.info(f"NSFW should go to separate channel: content_id={content.id}")
            return True

        logger.warning(f"Unknown NSFW policy: {policy}")
        return False

    async def check_already_pushed(self, content: Content, target_id: str) -> bool:
        """检查内容是否已推送到目标。"""
        result = await self.db.execute(
            select(PushedRecord)
            .where(
                and_(
                    PushedRecord.content_id == content.id,
                    PushedRecord.target_id == target_id,
                )
            )
            .order_by(PushedRecord.pushed_at.desc())
            .limit(1)
        )
        record = result.scalar_one_or_none()

        if not record:
            return False

        if content.reviewed_at and record.pushed_at:
            if content.reviewed_at > record.pushed_at:
                logger.info(
                    "Detected re-push: content_id=%s, target_id=%s, reviewed_at=%s, last_pushed=%s",
                    content.id,
                    target_id,
                    content.reviewed_at,
                    record.pushed_at,
                )
                return False

        return True

    async def should_distribute(
        self,
        content: Content,
        rule: DistributionRule,
        target: Dict[str, Any],
    ) -> bool:
        """检查内容是否应分发到目标。"""
        target_id = target.get("target_id")

        if not target_id:
            return False

        if not target.get("enabled", True):
            logger.debug(f"Target disabled: target_id={target_id}")
            return False

        if not await self.check_nsfw_policy(content, rule):
            logger.debug(f"NSFW policy blocked: target_id={target_id}")
            return False

        if await self.check_already_pushed(content, target_id):
            logger.debug(
                f"Already pushed to target (dedupe): content_id={content.id}, target_id={target_id}"
            )
            return False

        return True

    async def create_distribution_tasks(self, content: Content) -> List[Dict[str, Any]]:
        """
        为内容创建分发任务（重构版：批量查询规避 N+1）。
        
        实现要点：
        - 跨规则排重：同一 Content 对同一 BotChat 只产生一条任务（保留优先级最高规则）
        - 权限前置校验：检查 BotChat.enabled, is_accessible, can_post
        - 批量查询优化：一次性获取所有规则目标，预加载 BotChat 表规避循环内查询
        """
        if content.review_status not in [ReviewStatus.APPROVED, ReviewStatus.AUTO_APPROVED]:
            logger.debug(f"Content not approved: content_id={content.id}, status={content.review_status}")
            return []

        matched_rules = await self.match_rules(content)
        if not matched_rules:
            logger.info(f"No matching rules: content_id={content.id}, tags={content.tags}")
            return []

        # 1. 批量获取所有涉及规则的目标和 BotChat（过滤掉不可用的目标和 Chat）
        rule_ids = [r.id for r in matched_rules]
        targets_result = await self.db.execute(
            select(DistributionTarget, BotChat)
            .join(BotChat, DistributionTarget.bot_chat_id == BotChat.id)
            .where(DistributionTarget.rule_id.in_(rule_ids))
            .where(DistributionTarget.enabled == True)
            .where(BotChat.enabled == True)
            .where(BotChat.is_accessible == True)
            .where(BotChat.can_post == True)
        )
        
        # 按 rule_id 组织目标
        rule_targets: Dict[int, List[tuple[DistributionTarget, BotChat]]] = {}
        for target, bot_chat in targets_result.all():
            if target.rule_id not in rule_targets:
                rule_targets[target.rule_id] = []
            rule_targets[target.rule_id].append((target, bot_chat))

        # 2. 如果是 NSFW 内容，预先加载所有启用状态的 BotChat Map 规避 N+1
        chats_map: Dict[str, BotChat] = {}
        if content.is_nsfw:
            chats_result = await self.db.execute(select(BotChat).where(BotChat.enabled == True))
            chats_map = {c.chat_id: c for c in chats_result.scalars().all()}

        # 记录已创建任务的 BotChat (用于跨规则排重)
        processed_chats: Dict[int, Dict[str, Any]] = {}  # {bot_chat_id: task_dict}
        tasks = []
        
        for rule in matched_rules:
            target_pairs = rule_targets.get(rule.id, [])
            if not target_pairs:
                continue
            
            for target, bot_chat in target_pairs:
                # 前置权限校验
                if not await self._check_bot_chat_accessible(bot_chat):
                    continue
                
                # NSFW 策略路由
                actual_chat_id, actual_bot_chat = await self._apply_nsfw_routing(
                    content, rule, bot_chat, chats_map
                )
                if not actual_chat_id:
                    # NSFW 被阻止
                    continue
                
                # 跨规则排重：已处理过该 BotChat 则跳过（保留优先级高的规则）
                if actual_bot_chat.id in processed_chats:
                    logger.debug(
                        f"Skipping duplicate target: content={content.id}, "
                        f"chat={actual_chat_id}, rule={rule.name} (already processed)"
                    )
                    continue
                
                # 检查是否已推送
                if await self.check_already_pushed(content, actual_chat_id):
                    logger.debug(
                        f"Already pushed to target (dedupe): content_id={content.id}, "
                        f"target_id={actual_chat_id}"
                    )
                    continue
                
                # 构建渲染配置（优先级：target override > rule default）
                render_config = self._merge_render_config(rule, target)
                
                # 创建任务
                task = {
                    "content_id": content.id,
                    "rule_id": rule.id,
                    "target_platform": actual_bot_chat.platform_type,
                    "target_id": actual_chat_id,
                    "template_id": rule.template_id,
                    "target_meta": {
                        "merge_forward": target.merge_forward,
                        "use_author_name": target.use_author_name,
                        "summary": target.summary,
                        "render_config": render_config,
                    },
                }
                
                tasks.append(task)
                processed_chats[actual_bot_chat.id] = task
                
                logger.debug(
                    f"Created task: content={content.id}, rule={rule.name}, "
                    f"chat={actual_chat_id}, platform={actual_bot_chat.platform_type}"
                )

        logger.info(
            f"Created {len(tasks)} distribution tasks for content {content.id} "
            f"(matched {len(matched_rules)} rules, deduplicated to {len(processed_chats)} chats)"
        )
        return tasks
    
    async def _check_bot_chat_accessible(self, bot_chat: BotChat) -> bool:
        """前置权限校验：检查 BotChat 是否可访问且可发送"""
        if not bot_chat.enabled:
            logger.debug(f"BotChat disabled: chat_id={bot_chat.chat_id}")
            return False
        
        if not bot_chat.is_accessible:
            logger.warning(f"BotChat not accessible: chat_id={bot_chat.chat_id}")
            return False
        
        if not bot_chat.can_post:
            logger.warning(f"BotChat cannot post: chat_id={bot_chat.chat_id}")
            return False
        
        return True
    
    async def _apply_nsfw_routing(
        self, 
        content: Content, 
        rule: DistributionRule, 
        bot_chat: BotChat,
        chats_map: Optional[Dict[str, BotChat]] = None
    ) -> tuple[Optional[str], Optional[BotChat]]:
        """
        NSFW 路由：根据策略决定实际分发目标。
        
        Returns:
            (actual_chat_id, actual_bot_chat) 或 (None, None) 表示被阻止
        """
        if not content.is_nsfw:
            return bot_chat.chat_id, bot_chat
        
        # 手动审批可绕过 NSFW 检查
        if content.review_status == ReviewStatus.APPROVED:
            logger.info(f"Manual approval bypasses NSFW check: content_id={content.id}")
            return bot_chat.chat_id, bot_chat
        
        policy = rule.nsfw_policy
        
        if policy == "block":
            logger.warning(f"NSFW blocked: content_id={content.id}, rule={rule.name}")
            return None, None
        
        if policy == "allow":
            return bot_chat.chat_id, bot_chat
        
        if policy == "separate_channel":
            if not bot_chat.nsfw_chat_id:
                logger.warning(
                    f"NSFW separate policy but no nsfw_chat_id: chat={bot_chat.chat_id}"
                )
                return None, None
            
            # 使用预加载的 map 查找备用 BotChat，否则查询数据库
            nsfw_chat = None
            if chats_map and bot_chat.nsfw_chat_id in chats_map:
                nsfw_chat = chats_map[bot_chat.nsfw_chat_id]
            else:
                result = await self.db.execute(
                    select(BotChat).where(BotChat.chat_id == bot_chat.nsfw_chat_id)
                )
                nsfw_chat = result.scalar_one_or_none()
            
            if not nsfw_chat:
                logger.error(
                    f"NSFW chat not found: nsfw_chat_id={bot_chat.nsfw_chat_id}"
                )
                return None, None
            
            if not await self._check_bot_chat_accessible(nsfw_chat):
                logger.warning(f"NSFW chat not accessible: {bot_chat.nsfw_chat_id}")
                return None, None
            
            logger.debug(
                f"NSFW routing: {bot_chat.chat_id} -> {nsfw_chat.chat_id} "
                f"(content={content.id})"
            )
            return nsfw_chat.chat_id, nsfw_chat
        
        logger.warning(f"Unknown NSFW policy: {policy}")
        return None, None
    
    def _merge_render_config(
        self, rule: DistributionRule, target: DistributionTarget
    ) -> Optional[Dict[str, Any]]:
        """合并渲染配置：target override > rule default"""
        if target.render_config_override:
            # 如果有 override，以它为基础，但保留 rule 的部分字段（如需要）
            base = rule.render_config or {}
            return {**base, **target.render_config_override}
        
        return rule.render_config

    async def group_tasks_for_dispatch(self, tasks: List[Dict[str, Any]]) -> List[Dict[str, Any]]:
        """启用时将任务分组为批量转发载荷。"""
        grouped: dict[tuple[str, str], Dict[str, Any]] = {}
        output: List[Dict[str, Any]] = []

        for task in tasks:
            target_meta = task.get("target_meta") or {}
            if not target_meta.get("merge_forward"):
                output.append(task)
                continue

            key = (task.get("target_platform", ""), task.get("target_id", ""))
            group = grouped.get(key)
            if not group:
                group = {
                    "action": "distribute_batch",
                    "target_platform": task.get("target_platform"),
                    "target_id": task.get("target_id"),
                    "target_meta": target_meta,
                    "batch_contents": [],
                }
                grouped[key] = group
                output.append(group)

            group["batch_contents"].append(
                {
                    "id": task.get("content_id"),
                    "rule_id": task.get("rule_id"),
                }
            )

        return output

    async def get_min_interval_for_content(self, content: Content) -> int:
        """
        根据匹配规则计算最小间隔（秒）。

        默认最小值为 300秒（5分钟）。
        """
        matched_rules = await self.match_rules(content)
        if not matched_rules:
            return 300

        max_interval = 300
        for rule in matched_rules:
            if rule.rate_limit and rule.time_window:
                rule_interval = rule.time_window // rule.rate_limit
                max_interval = max(max_interval, rule_interval)

        return max_interval

    async def calculate_scheduled_at(self, content: Content, min_interval: Optional[int] = None) -> datetime:
        """计算内容的 scheduled_at。"""
        if min_interval is None:
            min_interval = await self.get_min_interval_for_content(content)

        now = datetime.utcnow()
        result = await self.db.execute(
            select(Content.scheduled_at)
            .where(
                Content.review_status.in_([ReviewStatus.APPROVED, ReviewStatus.AUTO_APPROVED]),
                Content.status == "pulled",
                Content.scheduled_at >= now,
            )
            .order_by(Content.scheduled_at.asc())
        )
        scheduled_times = [r[0] for r in result.all()]

        interval = timedelta(seconds=min_interval)
        potential_time = now + timedelta(seconds=10)

        for st in scheduled_times:
            if st - potential_time >= interval:
                return potential_time
            potential_time = st + interval

        return potential_time

    async def compact_schedule(self, immediate_ids: Optional[List[int]] = None):
        """紧凑队列排期（不破坏手动覆盖）。"""
        now = datetime.utcnow()
        result = await self.db.execute(
            select(Content)
            .where(
                Content.review_status.in_([ReviewStatus.APPROVED, ReviewStatus.AUTO_APPROVED]),
                Content.status == "pulled",
            )
            .order_by(Content.scheduled_at.asc().nulls_last(), Content.created_at.asc())
        )
        contents = result.scalars().all()

        if not contents:
            return

        last_time = now
        immediate_ids_set = set(immediate_ids or [])

        for content in contents:
            if content.is_manual_schedule or content.id in immediate_ids_set:
                min_gap_seconds = 10
            else:
                min_gap_seconds = await self.get_min_interval_for_content(content)

            interval = timedelta(seconds=min_gap_seconds)

            current_scheduled = (
                content.scheduled_at.replace(tzinfo=None) if content.scheduled_at else None
            )

            min_allowed = last_time + (timedelta(seconds=5) if last_time == now else interval)

            if not current_scheduled or current_scheduled < min_allowed:
                content.scheduled_at = min_allowed
            else:
                content.scheduled_at = current_scheduled

            last_time = content.scheduled_at

        await self.db.commit()
        logger.info(
            "Queue schedule compacted: %s items, %s immediate",
            len(contents),
            len(immediate_ids_set),
        )

    async def move_item_to_position(self, content_id: int, new_index: int):
        """使用新索引重排队列并重新调度。"""
        result = await self.db.execute(
            select(Content)
            .where(
                Content.review_status.in_([ReviewStatus.APPROVED, ReviewStatus.AUTO_APPROVED]),
                Content.status == "pulled",
            )
            .order_by(Content.scheduled_at.asc().nulls_last(), Content.created_at.asc())
        )
        contents = result.scalars().all()

        moving_item = next((c for c in contents if c.id == content_id), None)
        if not moving_item:
            return

        moving_item.is_manual_schedule = True

        items = [c for c in contents if c.id != content_id]
        new_index = max(0, min(new_index, len(items)))
        items.insert(new_index, moving_item)

        if new_index == 0:
            moving_item.scheduled_at = datetime.utcnow() - timedelta(hours=1)
        elif new_index >= len(items) - 1:
            last_item = items[-2]
            moving_item.scheduled_at = (last_item.scheduled_at or datetime.utcnow()) + timedelta(seconds=1)
        else:
            prev_item = items[new_index - 1]
            moving_item.scheduled_at = (prev_item.scheduled_at or datetime.utcnow()) + timedelta(seconds=1)

        await self.db.commit()
        await self.compact_schedule()

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
                content.is_manual_schedule = False

                min_interval = await self.get_min_interval_for_content(content)
                content.scheduled_at = await self.calculate_scheduled_at(content, min_interval=min_interval)

                await self.db.commit()

                logger.info(
                    "Content auto-approved: content_id=%s, interval=%ss, scheduled_at=%s",
                    content.id,
                    min_interval,
                    content.scheduled_at,
                )
                return True

        return False

    async def _check_auto_approve_conditions(
        self,
        content: Content,
        conditions: Dict[str, Any],
    ) -> bool:
        """检查自动批准条件。"""
        if "is_nsfw" in conditions:
            if conditions["is_nsfw"] != content.is_nsfw:
                return False

        if "platform" in conditions:
            if conditions["platform"] != content.platform.value:
                return False

        if "tags" in conditions:
            required_tags = conditions["tags"]
            if isinstance(required_tags, list):
                content_tags = content.tags or []
                if not all(tag in content_tags for tag in required_tags):
                    return False

        return True

    async def refresh_queue_by_rules(self):
        """根据更新的规则刷新队列。"""
        result = await self.db.execute(
            select(Content).where(Content.status == "pulled")
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
                    content.scheduled_at = None
                    changes += 1

            elif content.review_status == ReviewStatus.PENDING:
                for rule in enabled_rules:
                    if rule.auto_approve_conditions and await self._check_auto_approve_conditions(
                        content, rule.auto_approve_conditions
                    ):
                        content.review_status = ReviewStatus.AUTO_APPROVED
                        content.reviewed_at = datetime.utcnow()
                        content.review_note = f"Rule update auto-approved (rule: {rule.name})"
                        content.is_manual_schedule = False
                        changes += 1
                        break

        if changes > 0:
            await self.db.commit()
            logger.info("Rules updated: %s content status changes", changes)

        await self.compact_schedule()
