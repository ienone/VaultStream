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
                claimed_task = await task_queue.dequeue(timeout=5, parse_enabled=decision.allowed)

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
        if claimed_task.task_type == "repair_media":
            from app.services.media_repair import process_media_repair_task
            await process_media_repair_task(claimed_task)
            return
        if claimed_task.task_type in {"content_scoring", "content_summary", "content_distribution", "content_embedding"}:
            from app.services.post_ingest import process_content_task
            await process_content_task(claimed_task)
            return
        if claimed_task.task_type != "parse_content":
            await task_queue.mark_failed(claimed_task, reason="unknown_task_type")
            return
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
