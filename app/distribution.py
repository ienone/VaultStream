"""
M4: 分发引擎模块
处理内容的自动分发逻辑
"""
from typing import List, Dict, Any, Optional
from sqlalchemy import select, and_
from sqlalchemy.ext.asyncio import AsyncSession
from datetime import datetime, timedelta

from app.logging import logger
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
        
        matched_rules = []
        for rule in all_rules:
            if await self._check_match(content, rule):
                matched_rules.append(rule)
        
        return matched_rules
    
    async def _check_match(self, content: Content, rule: DistributionRule) -> bool:
        """
        检查内容是否匹配规则条件
        
        match_conditions 示例:
        {
            "tags": ["tech", "news"],  # 包含任一标签
            "platform": "bilibili",     # 平台匹配
            "is_nsfw": false            # NSFW状态
        }
        """
        conditions = rule.match_conditions
        
        if not conditions:
            return False
        
        # 检查标签匹配
        if "tags" in conditions:
            required_tags = conditions["tags"]
            if isinstance(required_tags, list) and required_tags:
                content_tags = content.tags or []
                # 任一标签匹配即可
                if not any(tag in content_tags for tag in required_tags):
                    return False
        
        # 检查平台匹配
        if "platform" in conditions:
            if conditions["platform"] != content.platform.value:
                return False
        
        # 检查 NSFW 状态
        if "is_nsfw" in conditions:
            if conditions["is_nsfw"] != content.is_nsfw:
                return False
        
        # 检查审批状态（只分发已批准的内容）
        if rule.approval_required:
            if content.review_status != ReviewStatus.APPROVED:
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
    
    async def check_already_pushed(self, content_id: int, target_id: str) -> bool:
        """
        检查内容是否已推送到目标
        
        Returns:
            True: 已推送
            False: 未推送
        """
        result = await self.db.execute(
            select(PushedRecord).where(
                and_(
                    PushedRecord.content_id == content_id,
                    PushedRecord.target_id == target_id
                )
            )
        )
        record = result.scalar_one_or_none()
        return record is not None
    
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
        
        target 示例: {"platform": "telegram", "target_id": "@my_channel", "enabled": true}
        """
        target_id = target.get("target_id")
        
        if not target_id:
            return False
        
        # 检查目标是否启用
        if not target.get("enabled", True):
            return False
        
        # NSFW 策略检查（硬失败）
        if not await self.check_nsfw_policy(content, rule):
            return False
        
        # 去重检查
        if await self.check_already_pushed(content.id, target_id):
            logger.debug(f"内容已推送到目标: content_id={content.id}, target_id={target_id}")
            return False
        
        # 频率限制检查
        if not await self.check_rate_limit(rule, target_id):
            return False
        
        return True
    
    async def create_distribution_tasks(self, content: Content) -> List[Dict[str, Any]]:
        """
        为内容创建分发任务列表
        
        Returns:
            任务列表，每个任务包含 target_platform, target_id, rule_id 等信息
        """
        # 检查审批状态（只分发已批准或自动批准的内容）
        if content.review_status not in [ReviewStatus.APPROVED, ReviewStatus.AUTO_APPROVED]:
            logger.debug(f"内容未批准，跳过分发: content_id={content.id}, review_status={content.review_status}")
            return []
        
        # 匹配规则
        matched_rules = await self.match_rules(content)
        
        if not matched_rules:
            logger.debug(f"无匹配规则: content_id={content.id}")
            return []
        
        tasks = []
        for rule in matched_rules:
            targets = rule.targets or []
            
            for target in targets:
                if await self.should_distribute(content, rule, target):
                    tasks.append({
                        "content_id": content.id,
                        "rule_id": rule.id,
                        "target_platform": target.get("platform", "telegram"),
                        "target_id": target["target_id"],
                        "template_id": rule.template_id
                    })
        
        logger.info(f"为内容创建了 {len(tasks)} 个分发任务: content_id={content.id}")
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
