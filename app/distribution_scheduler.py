"""
定时推送调度器
按分发规则定时检查待推送内容并批量推送
"""
import asyncio
from typing import List, Dict, Any, Optional
from datetime import datetime, timedelta
from sqlalchemy import select, and_, func
from sqlalchemy.ext.asyncio import AsyncSession

from app.logging import logger
from app.database import AsyncSessionLocal
from app.models import Content, PushedRecord, DistributionRule, ReviewStatus
from app.queue import task_queue


class DistributionScheduler:
    """分发调度器 - 定时检查并推送内容"""
    
    def __init__(self, interval_seconds: int = 60):
        """
        Args:
            interval_seconds: 检查间隔（秒），默认60秒
        """
        self.interval_seconds = interval_seconds
        self.running = False
        self._task: Optional[asyncio.Task] = None
        
        # 频率限制：20条/分钟
        self.rate_limit = 20
        self.rate_window = 60  # 秒
        self.push_times: List[datetime] = []
    
    def start(self):
        """启动调度器"""
        if self.running:
            logger.warning("分发调度器已在运行")
            return
        
        self.running = True
        self._task = asyncio.create_task(self._run_loop())
        logger.info(f"分发调度器已启动，检查间隔: {self.interval_seconds}秒")
    
    async def stop(self):
        """停止调度器"""
        self.running = False
        if self._task:
            self._task.cancel()
            try:
                await self._task
            except asyncio.CancelledError:
                pass
        logger.info("分发调度器已停止")
    
    async def _run_loop(self):
        """主循环"""
        while self.running:
            try:
                await self._check_and_distribute()
            except Exception as e:
                logger.error(f"分发调度器出错: {e}", exc_info=True)
            
            # 等待下一次检查
            await asyncio.sleep(self.interval_seconds)
    
    async def _check_and_distribute(self):
        """检查并分发内容"""
        async with AsyncSessionLocal() as session:
            # 获取所有启用的分发规则
            rules_result = await session.execute(
                select(DistributionRule).where(DistributionRule.enabled == True)
            )
            rules = rules_result.scalars().all()
            
            if not rules:
                logger.debug("没有启用的分发规则")
                return
            
            logger.debug(f"找到 {len(rules)} 条启用的分发规则")
            
            # 对每条规则检查待推送内容
            for rule in rules:
                try:
                    await self._process_rule(session, rule)
                except Exception as e:
                    logger.error(f"处理分发规则失败 (rule_id={rule.id}): {e}", exc_info=True)
    
    async def _process_rule(self, session: AsyncSession, rule: DistributionRule):
        """处理单条分发规则"""
        # 构建查询条件
        conditions = [
            Content.review_status.in_([ReviewStatus.APPROVED, ReviewStatus.AUTO_APPROVED]),
            Content.status == "pulled"  # 只推送已解析成功的内容
        ]
        
        # 应用规则的匹配条件
        match_conditions = rule.match_conditions or {}
        
        # 标签过滤
        if "tags" in match_conditions and match_conditions["tags"]:
            # 检查内容的 tags 是否包含规则中的任一标签
            rule_tags = match_conditions["tags"]
            if isinstance(rule_tags, list) and rule_tags:
                # SQLite JSON 查询：检查数组重叠
                # 这里使用简单方法：对每个标签单独检查
                tag_conditions = []
                for tag in rule_tags:
                    # 使用 JSON_EACH 检查
                    tag_conditions.append(
                        func.json_each(Content.tags).op('=')(tag)
                    )
                # 任一标签匹配即可（OR）
                if tag_conditions:
                    from sqlalchemy import or_
                    conditions.append(or_(*tag_conditions))
        
        # 平台过滤
        if "platform" in match_conditions and match_conditions["platform"]:
            platform = match_conditions["platform"]
            conditions.append(Content.platform == platform)
        
        # NSFW 过滤
        if "is_nsfw" in match_conditions:
            is_nsfw = match_conditions["is_nsfw"]
            if is_nsfw is False:
                conditions.append(Content.is_nsfw == False)
            elif is_nsfw is True:
                conditions.append(Content.is_nsfw == True)
        
        # 获取所有目标
        targets = rule.targets or []
        if not targets:
            logger.debug(f"规则 {rule.id} 没有配置目标")
            return
        
        # 对每个目标查询未推送的内容
        for target in targets:
            if not target.get("enabled", True):
                continue
            
            target_platform = target.get("platform", "telegram")
            target_id = target.get("target_id")
            
            if not target_id:
                logger.warning(f"规则 {rule.id} 的目标配置缺少 target_id")
                continue
            
            # 检查频率限制
            if not self._check_rate_limit():
                logger.info("达到频率限制（20条/分钟），暂停推送")
                return
            
            # 查询未推送的内容
            # 使用 LEFT JOIN 找出没有推送记录的内容
            query = (
                select(Content)
                .where(and_(*conditions))
                .outerjoin(
                    PushedRecord,
                    and_(
                        PushedRecord.content_id == Content.id,
                        PushedRecord.target_id == target_id
                    )
                )
                .where(PushedRecord.id == None)  # 没有推送记录
                .order_by(Content.created_at.asc())
                .limit(5)  # 每次最多处理5条
            )
            
            result = await session.execute(query)
            contents = result.scalars().all()
            
            if not contents:
                logger.debug(f"规则 {rule.id} 目标 {target_id} 没有待推送内容")
                continue
            
            logger.info(
                f"规则 {rule.id} ({rule.name}) 找到 {len(contents)} 条待推送内容，"
                f"目标: {target_id}"
            )
            
            # 创建分发任务
            for content in contents:
                # 检查 NSFW 策略
                nsfw_policy = rule.nsfw_policy or "block"
                if content.is_nsfw and nsfw_policy == "block":
                    logger.info(f"内容 {content.id} 为NSFW，规则配置为阻止，跳过")
                    continue
                
                # 如果是 separate_channel 策略，需要使用不同的目标
                actual_target_id = target_id
                if content.is_nsfw and nsfw_policy == "separate_channel":
                    nsfw_target = target.get("nsfw_target_id")
                    if nsfw_target:
                        actual_target_id = nsfw_target
                    else:
                        logger.warning(f"内容 {content.id} 为NSFW，但规则未配置 nsfw_target_id，跳过")
                        continue
                
                # 创建分发任务
                task_data = {
                    "action": "distribute",
                    "content_id": content.id,
                    "rule_id": rule.id,
                    "target_platform": target_platform,
                    "target_id": actual_target_id,
                    "schema_version": 2
                }
                
                await task_queue.enqueue(task_data)
                logger.info(
                    f"已创建分发任务: content_id={content.id}, "
                    f"target={actual_target_id}"
                )
                
                # 记录推送时间（用于频率限制）
                self._record_push_time()
                
                # 检查频率限制
                if not self._check_rate_limit():
                    logger.info("达到频率限制，暂停推送")
                    return
    
    def _check_rate_limit(self) -> bool:
        """检查是否超过频率限制"""
        now = datetime.now()
        # 清理超过时间窗口的记录
        cutoff = now - timedelta(seconds=self.rate_window)
        self.push_times = [t for t in self.push_times if t > cutoff]
        
        # 检查是否超过限制
        return len(self.push_times) < self.rate_limit
    
    def _record_push_time(self):
        """记录推送时间"""
        self.push_times.append(datetime.now())


# 全局单例
_scheduler: Optional[DistributionScheduler] = None


def get_distribution_scheduler(interval_seconds: int = 60) -> DistributionScheduler:
    """获取分发调度器单例"""
    global _scheduler
    if _scheduler is None:
        _scheduler = DistributionScheduler(interval_seconds)
    return _scheduler
