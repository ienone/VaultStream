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
    
    async def check_rate_limit(self, rule: DistributionRule, target_id: str) -> bool:
        """
        检查是否超过频率限制
        
        Returns:
            True: 允许推送
            False: 超过限制
        """
        if not rule.rate_limit or not rule.time_window:
            return True  # 无限制
        
        # 统计时间窗口内的推送次数
        window_start = datetime.utcnow() - timedelta(seconds=rule.time_window)
        
        result = await self.db.execute(
            select(PushedRecord).where(
                and_(
                    PushedRecord.target_id == target_id,
                    PushedRecord.pushed_at >= window_start
                )
            )
        )
        recent_pushes = result.scalars().all()
        
        if len(recent_pushes) >= rule.rate_limit:
            logger.warning(
                f"频率限制: target_id={target_id}, "
                f"已推送{len(recent_pushes)}次 (限制{rule.rate_limit}次/{rule.time_window}秒)"
            )
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
        
        # 频率限制检查
        if not await self.check_rate_limit(rule, target_id):
            logger.debug(f"频率限制拦截: target_id={target_id}")
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
            logger.warning(f"内容无匹配规则: content_id={content.id}, tags={content.tags}")
            return []
        
        tasks = []
        for rule in matched_rules:
            targets = rule.targets or []
            if not targets:
                logger.warning(f"规则无分发目标: rule={rule.name}")
            
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
                
                await self.db.commit()
                
                logger.info(f"内容已自动批准: content_id={content.id}, rule={rule.name}")
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
