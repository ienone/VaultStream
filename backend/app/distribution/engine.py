"""
M4: 分发引擎模块
处理内容的自动分发逻辑
"""
from typing import List, Dict, Any, Optional
from sqlalchemy import select, and_
from sqlalchemy.ext.asyncio import AsyncSession
from datetime import datetime, timedelta

from app.core.logging import logger
from app.models import Content, DistributionRule, PushedRecord, ReviewStatus, Platform
from app.schemas import ShareCardPreview, OptimizedMedia


class DistributionEngine:
    """分发引擎：根据规则匹配内容并生成分发任务"""
    
    def __init__(self, db: AsyncSession):
        self.db = db
    
    async def match_rules(self, content: Content) -> List[DistributionRule]:
        """
        为给定内容匹配分发规则
        
        返回: 按优先级排序的匹配规则列表
        """
        # 获取所有启用的规则，按优先级排序
        result = await self.db.execute(
            select(DistributionRule)
            .where(DistributionRule.enabled == True)
            .order_by(DistributionRule.priority.desc(), DistributionRule.id)
        )
        all_rules = result.scalars().all()
        
        logger.debug(f"正在为内容 {content.id} 匹配规则，共有 {len(all_rules)} 条启用规则")
        
        matched_rules = []
        for rule in all_rules:
            if await self._check_match(content, rule):
                matched_rules.append(rule)
        
        return matched_rules
    
    async def _check_match(self, content: Content, rule: DistributionRule) -> bool:
        """
        检查内容是否匹配规则条件
        """
        conditions = rule.match_conditions
        
        # 如果没有任何条件，默认匹配所有内容
        if not conditions:
            return True
        
        # 检查平台匹配
        if "platform" in conditions and conditions["platform"]:
            if conditions["platform"] != content.platform.value:
                return False
        
        # 检查标签匹配
        if "tags" in conditions:
            required_tags = conditions["tags"]
            if isinstance(required_tags, list) and required_tags:
                content_tags = [t.lower() for t in (content.tags or [])]
                required_tags_lower = [t.lower() for t in required_tags]
                
                tags_match_mode = conditions.get("tags_match_mode", "any")
                
                if tags_match_mode == "all":
                    # 必须包含所有要求的标签
                    if not all(tag in content_tags for tag in required_tags_lower):
                        return False
                else:
                    # 包含任一标签即可
                    if not any(tag in content_tags for tag in required_tags_lower):
                        return False
        
        # 检查排除标签
        if "tags_exclude" in conditions:
            exclude_tags = conditions["tags_exclude"]
            if isinstance(exclude_tags, list) and exclude_tags:
                content_tags = [t.lower() for t in (content.tags or [])]
                exclude_tags_lower = [t.lower() for t in exclude_tags]
                if any(tag in content_tags for tag in exclude_tags_lower):
                    return False
        
        # 检查 NSFW 状态
        if "is_nsfw" in conditions:
            if conditions["is_nsfw"] != content.is_nsfw:
                return False
        
        # 检查审批状态（只分发已批准的内容）
        if rule.approval_required:
            if content.review_status not in [ReviewStatus.APPROVED, ReviewStatus.AUTO_APPROVED]:
                return False
        
        return True
    
    async def check_nsfw_policy(self, content: Content, rule: DistributionRule) -> bool:
        """
        检查 NSFW 策略是否允许分发
        
        Returns:
            True: 允许分发
            False: 阻止分发（硬失败）
        """
        if not content.is_nsfw:
            return True  # 非NSFW内容总是允许
        
        # 优先级：手动批准 > NSFW规则
        # 如果是人工手动批准的内容 (APPROVED)，则允许忽略 NSFW 阻止规则
        # 注意：自动批准 (AUTO_APPROVED) 仍然受制于 NSFW 规则
        if content.review_status == ReviewStatus.APPROVED:
            logger.info(f"人工批准内容，跳过 NSFW 检查: content_id={content.id}")
            return True
        
        policy = rule.nsfw_policy
        
        if policy == "block":
            logger.warning(f"NSFW内容被阻止分发: content_id={content.id}, rule={rule.name}")
            return False
        elif policy == "allow":
            return True
        elif policy == "separate_channel":
            # TODO: 实现分离频道逻辑（需要在 targets 中配置特殊 NSFW 频道）
            logger.info(f"NSFW内容应分发到独立频道: content_id={content.id}")
            return True
        else:
            logger.warning(f"未知的NSFW策略: {policy}")
            return False
    
    async def check_already_pushed(self, content: Content, target_id: str) -> bool:
        """
        检查内容是否已推送到目标
        
        如果内容重新经过审批 (reviewed_at > last_pushed_at)，则允许再次推送
        
        Returns:
            True: 已推送 (且无需重推)
            False: 未推送 (或需要重推)
        """
        # 获取该目标最后一次推送记录
        result = await self.db.execute(
            select(PushedRecord).where(
                and_(
                    PushedRecord.content_id == content.id,
                    PushedRecord.target_id == target_id
                )
            ).order_by(PushedRecord.pushed_at.desc()).limit(1)
        )
        record = result.scalar_one_or_none()
        
        if not record:
            return False
            
        # 如果存在推送记录，检查是否是重推情况
        if content.reviewed_at and record.pushed_at:
            # 如果审批时间晚于最后推送时间，说明是重推，允许通过
            if content.reviewed_at > record.pushed_at:
                logger.info(f"检测到重推请求: content_id={content.id}, target_id={target_id}, reviewed_at={content.reviewed_at}, last_pushed={record.pushed_at}")
                return False
        
        return True
    
    async def should_distribute(
        self, 
        content: Content, 
        rule: DistributionRule, 
        target: Dict[str, Any]
    ) -> bool:
        """
        综合检查是否应该分发到目标
        """
        target_id = target.get("target_id")
        
        if not target_id:
            return False
        
        # 检查目标是否启用
        if not target.get("enabled", True):
            logger.debug(f"目标未启用: target_id={target_id}")
            return False
        
        # NSFW 策略检查（硬失败）
        if not await self.check_nsfw_policy(content, rule):
            logger.debug(f"NSFW策略阻止: target_id={target_id}")
            return False
        
        # 去重检查
        if await self.check_already_pushed(content, target_id):
            logger.debug(f"内容已推送到目标 (去重拦截): content_id={content.id}, target_id={target_id}")
            return False
        
        return True
    
    async def create_distribution_tasks(self, content: Content) -> List[Dict[str, Any]]:
        """
        为内容创建分发任务列表
        """
        # 检查审批状态
        if content.review_status not in [ReviewStatus.APPROVED, ReviewStatus.AUTO_APPROVED]:
            logger.debug(f"内容未批准: content_id={content.id}, status={content.review_status}")
            return []
        
        # 匹配规则
        matched_rules = await self.match_rules(content)
        
        if not matched_rules:
            logger.info(f"内容无匹配规则: content_id={content.id}, tags={content.tags}")
            return []
        
        tasks = []
        for rule in matched_rules:
            targets = rule.targets or []
            if not targets:
                logger.debug(f"规则无分发目标: rule={rule.name}")
            
            for target in targets:
                if await self.should_distribute(content, rule, target):
                    tasks.append({
                        "content_id": content.id,
                        "rule_id": rule.id,
                        "target_platform": target.get("platform", "telegram"),
                        "target_id": target["target_id"],
                        "template_id": rule.template_id
                    })
                else:
                    logger.debug(f"目标不满足分发条件: target={target.get('target_id')}")
        
        logger.info(f"为内容 {content.id} 创建了 {len(tasks)} 个分发任务")
        return tasks
    
    async def get_min_interval_for_content(self, content: Content) -> int:
        """
        根据内容匹配到的所有规则，计算最严格的最小排期间隔（秒）
        默认最小 300s (5分钟)
        """
        matched_rules = await self.match_rules(content)
        if not matched_rules:
            return 300
        
        max_interval = 300
        for rule in matched_rules:
            if rule.rate_limit and rule.time_window:
                # 计算该规则要求的平均间隔 (例如 3600/10 = 360s)
                rule_interval = rule.time_window // rule.rate_limit
                max_interval = max(max_interval, rule_interval)
        
        return max_interval

    async def calculate_scheduled_at(self, content: Content, min_interval: Optional[int] = None) -> datetime:
        """
        计算内容的预计推送时间 (scheduled_at)
        策略: 寻找从现在开始的第一个可用空档
        """
        if min_interval is None:
            min_interval = await self.get_min_interval_for_content(content)
            
        now = datetime.utcnow()
        # 获取所有待推送的未来排期
        result = await self.db.execute(
            select(Content.scheduled_at)
            .where(
                Content.review_status.in_([ReviewStatus.APPROVED, ReviewStatus.AUTO_APPROVED]),
                Content.status == "pulled",
                Content.scheduled_at >= now
            )
            .order_by(Content.scheduled_at.asc())
        )
        scheduled_times = [r[0] for r in result.all()]
        
        interval = timedelta(seconds=min_interval)
        potential_time = now + timedelta(seconds=10)
        
        for st in scheduled_times:
            # 如果当前检查的时间点和下一个已有排期之间有足够间隙
            if st - potential_time >= interval:
                return potential_time
            # 否则跳到下一个排期之后继续找
            potential_time = st + interval
            
        return potential_time

    async def compact_schedule(self, immediate_ids: Optional[List[int]] = None):
        """
        队列整理（非破坏性重排）
        1. 确保所有时间都在未来
        2. 确保相邻条目符合其规则定义的最小间隔 (或是立即推送的 10s 间隔)
        3. 尊重用户手动设置的更远的未来时间
        """
        now = datetime.utcnow()
        result = await self.db.execute(
            select(Content)
            .where(
                Content.review_status.in_([ReviewStatus.APPROVED, ReviewStatus.AUTO_APPROVED]),
                Content.status == "pulled"
            )
            .order_by(Content.scheduled_at.asc().nulls_last(), Content.created_at.asc())
        )
        contents = result.scalars().all()
        
        if not contents:
            return

        last_time = now
        immediate_ids_set = set(immediate_ids or [])
        
        for content in contents:
            # 1. 确定该内容应遵循的最小间隔
            # 如果是手动设定项或指定的立即推送项，采用 10s 紧凑间隔；否则遵循规则限制
            if content.is_manual_schedule or content.id in immediate_ids_set:
                min_gap_seconds = 10
            else:
                # 常规项根据规则动态获取，默认为 300s
                min_gap_seconds = await self.get_min_interval_for_content(content)
            
            interval = timedelta(seconds=min_gap_seconds)
            
            # 2. 基础时间：如果内容已经有了一个未来的排期，先以它为准
            current_scheduled = content.scheduled_at.replace(tzinfo=None) if content.scheduled_at else None
            
            # 3. 确定最小允许时间 (上一个时间 + 间隔)
            # 如果是第一个，从 now + 5s 开始，否则从 last_time + interval 开始
            min_allowed = last_time + (timedelta(seconds=5) if last_time == now else interval)
            
            if not current_scheduled or current_scheduled < min_allowed:
                # 如果时间已过期或太挤，则推移到最小允许时间
                content.scheduled_at = min_allowed
            else:
                # 如果用户手动设置了一个更远的未来时间，且没与前项冲突，则保留
                content.scheduled_at = current_scheduled
            
            last_time = content.scheduled_at
        
        await self.db.commit()
        logger.info(f"队列时间轴已优化整理: 共有 {len(contents)} 个条目, 包含 {len(immediate_ids_set)} 个立即推送项")

    async def move_item_to_position(self, content_id: int, new_index: int):
        """
        拖动重排：调整逻辑顺序，并确保时间轴递增
        """
        # 1. 抓出所有相关条目
        result = await self.db.execute(
            select(Content)
            .where(
                Content.review_status.in_([ReviewStatus.APPROVED, ReviewStatus.AUTO_APPROVED]),
                Content.status == "pulled"
            )
            .order_by(Content.scheduled_at.asc().nulls_last(), Content.created_at.asc())
        )
        contents = result.scalars().all()
        
        moving_item = next((c for c in contents if c.id == content_id), None)
        if not moving_item: return

        # 标记为手动排期，因为是用户手动拖动的
        moving_item.is_manual_schedule = True

        # 2. 内存中调整顺序
        items = [c for c in contents if c.id != content_id]
        new_index = max(0, min(new_index, len(items)))
        items.insert(new_index, moving_item)
        
        # 3. 为移动后的条目分配一个临时时间戳以维持新的逻辑顺序（供下文 order_by 使用）
        if new_index == 0:
            # 移到最前：设为过去
            moving_item.scheduled_at = datetime.utcnow() - timedelta(hours=1)
        elif new_index >= len(items) - 1:
            # 移到最后：设为最后一个人之后 1s
            last_item = items[-2]
            moving_item.scheduled_at = (last_item.scheduled_at or datetime.utcnow()) + timedelta(seconds=1)
        else:
            # 移到中间：设为前一个条目之后 1s
            prev_item = items[new_index - 1]
            moving_item.scheduled_at = (prev_item.scheduled_at or datetime.utcnow()) + timedelta(seconds=1)
            
        # 4. 提交临时顺序，并运行一次全局紧凑整理，它会根据动态间隔拉开正确的时间
        await self.db.commit()
        await self.compact_schedule()

    async def auto_approve_if_eligible(self, content: Content) -> bool:
        """
        根据规则的自动批准条件，自动批准内容
        
        Returns:
            True: 已自动批准
            False: 不符合自动批准条件
        """
        # 获取所有启用的规则
        result = await self.db.execute(
            select(DistributionRule)
            .where(DistributionRule.enabled == True)
        )
        all_rules = result.scalars().all()
        
        for rule in all_rules:
            if not rule.auto_approve_conditions:
                continue
            
            # 检查是否匹配自动批准条件
            if await self._check_auto_approve_conditions(content, rule.auto_approve_conditions):
                content.review_status = ReviewStatus.AUTO_APPROVED
                content.reviewed_at = datetime.utcnow()
                content.review_note = f"自动批准 (规则: {rule.name})"
                content.is_manual_schedule = False  # 自动批准不标记为手动
                
                # 计算动态间隔（基于该内容的规则限制）
                min_interval = await self.get_min_interval_for_content(content)
                # 设置预计推送时间
                content.scheduled_at = await self.calculate_scheduled_at(content, min_interval=min_interval)
                
                await self.db.commit()
                
                logger.info(f"内容已自动批准并加入调度: content_id={content.id}, interval={min_interval}s, scheduled_at={content.scheduled_at}")
                return True
        
        return False
    
    async def _check_auto_approve_conditions(
        self, 
        content: Content, 
        conditions: Dict[str, Any]
    ) -> bool:
        """检查是否满足自动批准条件"""
        # 示例条件: {"tags": ["safe"], "platform": "bilibili", "is_nsfw": false}
        
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
        """
        根据最新的规则刷新整个队列：
        1. 重新评估 PENDING 内容是否符合新规则的自动批准
        2. 重新评估 AUTO_APPROVED 内容是否依然符合规则
        3. 重新整理时间轴
        """
        # 1. 获取所有待处理内容
        result = await self.db.execute(
            select(Content).where(Content.status == "pulled")
        )
        contents = result.scalars().all()
        
        # 2. 获取所有启用的规则
        rule_result = await self.db.execute(
            select(DistributionRule).where(DistributionRule.enabled == True)
        )
        enabled_rules = rule_result.scalars().all()
        
        changes = 0
        for content in contents:
            # 只有非手动审批的内容才受自动规则变更影响
            if content.review_status == ReviewStatus.AUTO_APPROVED:
                # 检查是否依然匹配任一规则的自动批准条件
                still_valid = False
                for rule in enabled_rules:
                    if rule.auto_approve_conditions and await self._check_auto_approve_conditions(content, rule.auto_approve_conditions):
                        still_valid = True
                        break
                
                if not still_valid:
                    # 不再符合规则，回退到 PENDING
                    content.review_status = ReviewStatus.PENDING
                    content.scheduled_at = None
                    changes += 1
                    
            elif content.review_status == ReviewStatus.PENDING:
                # 尝试匹配新规则
                for rule in enabled_rules:
                    if rule.auto_approve_conditions and await self._check_auto_approve_conditions(content, rule.auto_approve_conditions):
                        content.review_status = ReviewStatus.AUTO_APPROVED
                        content.reviewed_at = datetime.utcnow()
                        content.review_note = f"规则更新自适应批准 (规则: {rule.name})"
                        content.is_manual_schedule = False
                        changes += 1
                        break
        
        if changes > 0:
            await self.db.commit()
            logger.info(f"规则变更导致 {changes} 条内容状态发生更新")
            
        # 3. 无论状态是否改变，只要规则可能修改了频率限制，就触发一次重排
        await self.compact_schedule()
