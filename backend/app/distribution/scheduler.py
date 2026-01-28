"""
定时推送调度器
按分发规则定时检查待推送内容并批量推送
"""
import asyncio
from typing import List, Optional
from datetime import datetime, timedelta
from sqlalchemy import select

from app.core.logging import logger
from app.core.database import AsyncSessionLocal
from app.models import Content, ReviewStatus
from app.distribution.engine import DistributionEngine
from app.core.queue import task_queue


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
        
        # 全局频率限制：20条/分钟
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
            
            await asyncio.sleep(self.interval_seconds)

    async def trigger_run(self):
        """手动触发一次分发"""
        logger.info("手动触发分发...")
        await self._check_and_distribute()
    
    async def _check_and_distribute(self):
        """检查并分发内容"""
        async with AsyncSessionLocal() as session:
            # 查询候选内容：已批准 + 已拉取
            result = await session.execute(
                select(Content)
                .where(
                    Content.review_status.in_([ReviewStatus.APPROVED, ReviewStatus.AUTO_APPROVED]),
                    Content.status == "pulled"
                )
                .order_by(Content.queue_priority.desc(), Content.created_at.asc())
                .limit(50)
            )
            contents = result.scalars().all()
            
            if not contents:
                logger.debug("没有待分发的内容")
                return
            
            logger.info(f"分发调度器: 找到 {len(contents)} 条候选内容")
            
            engine = DistributionEngine(session)
            
            for content in contents:
                if not self._check_rate_limit():
                    logger.info("达到频率限制（20条/分钟），暂停推送")
                    return
                
                try:
                    tasks = await engine.create_distribution_tasks(content)
                    
                    if not tasks:
                        logger.warning(f"内容 {content.id} 未生成任何分发任务 (可能被过滤)")
                        continue

                    for task in tasks:
                        task_data = {
                            "action": "distribute",
                            "content_id": task["content_id"],
                            "rule_id": task["rule_id"],
                            "target_platform": task["target_platform"],
                            "target_id": task["target_id"],
                            "schema_version": 2
                        }
                        
                        await task_queue.enqueue(task_data)
                        logger.info(
                            f"已创建分发任务: content_id={task['content_id']}, "
                            f"target={task['target_id']}"
                        )
                        
                        self._record_push_time()
                        
                        if not self._check_rate_limit():
                            logger.info("达到频率限制，暂停推送")
                            return
                            
                except Exception as e:
                    logger.error(f"处理内容分发失败 (content_id={content.id}): {e}", exc_info=True)
    
    def _check_rate_limit(self) -> bool:
        """检查是否超过频率限制"""
        now = datetime.now()
        cutoff = now - timedelta(seconds=self.rate_window)
        self.push_times = [t for t in self.push_times if t > cutoff]
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
