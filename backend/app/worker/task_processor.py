"""
任务处理器主模块

负责任务队列的轮询和任务分发
"""
import asyncio
from app.core.logging import logger, ensure_task_id
from app.core.queue import task_queue

from .parser import ContentParser


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
                # 从队列获取任务
                task_data = await task_queue.dequeue(timeout=5)
                
                if task_data:
                    await self.process_task(task_data)
                    
            except Exception as e:
                logger.error(f"Worker error: {e}")
                await asyncio.sleep(1)
    
    async def stop(self):
        """停止worker"""
        self.running = False
        logger.info("Task worker stopped")
    
    async def process_task(self, task_data: dict):
        """
        处理单个任务
        
        Args:
            task_data: 任务数据，包含 content_id 和可选的 action 字段
        """
        content_id = task_data.get('content_id')
        task_id = ensure_task_id(task_data.get("task_id"))
        
        if not content_id:
            logger.warning("任务数据缺少 content_id")
            return
        
        await self.parser.process_parse_task(task_data, task_id)

    async def retry_parse(self, content_id: int, max_retries: int = 3, force: bool = False):
        """
        手动触发重试解析 (代理到 Parser)
        
        这是给 API 调用的便捷方法
        """
        return await self.parser.retry_parse(content_id, max_retries=max_retries, force=force)
