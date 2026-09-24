"""
任务处理器主模块

负责任务队列的轮询和任务分发
"""
import asyncio
from app.core.logging import logger, ensure_task_id
from app.core.queue import task_queue
from app.models import Task
from app.services.background_task_state import (
    record_task_run_error,
)
from app.services.automation_policy import AutomationPolicyService

from .parsing import ContentParser


class TaskWorker:
    """任务处理器主类"""
    
    def __init__(self):
        self.running = False
        self.parser = ContentParser()
    
    async def start(self):
        """启动worker"""
        self.running = True

        logger.info("Task worker started")
        
        while self.running:
            try:
                decision = await AutomationPolicyService().parse_worker_poll()
                if not decision.allowed:
                    logger.bind(
                        component="parse_worker",
                        policy=decision.as_dict(),
                    ).debug("Parse worker polling skipped by automation policy")
                    await asyncio.sleep(1)
                    continue

                # 从队列获取任务
                claimed_task = await task_queue.dequeue(timeout=5)
                
                if claimed_task:
                    await self.process_task(claimed_task)
                    
            except Exception as e:
                logger.error(f"Worker error: {e}")
                await record_task_run_error("parse_worker", None, e)
                await asyncio.sleep(1)
    
    async def stop(self):
        """停止worker"""
        self.running = False
        logger.info("Task worker stopped")
    
    async def process_task(self, claimed_task: Task):
        """
        处理单个任务
        
        Args:
            claimed_task: 已领取的数据库任务行及其外部 payload
        """
        task_data = claimed_task.payload
        content_id = task_data.get('content_id')
        task_id = ensure_task_id(task_data.get("task_id"))
        
        if not content_id:
            logger.warning("任务数据缺少 content_id")
            await task_queue.mark_failed(
                claimed_task,
                reason="missing_content_id",
            )
            return
        
        await self.parser.process_parse_task(
            task_data,
            task_id,
            claimed_task=claimed_task,
        )

    async def retry_parse(self, content_id: int, force: bool = False):
        """
        手动触发重试解析 (代理到 Parser)
        
        这是给 API 调用的便捷方法
        """
        return await self.parser.retry_parse(content_id, force=force)
