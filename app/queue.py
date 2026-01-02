"""
Redis 任务队列服务
"""
import json
import redis.asyncio as aioredis
from typing import Optional, Dict, Any
from app.logging import logger, ensure_task_id, log_context

from app.config import settings


class TaskQueue:
    """Redis 任务队列"""
    
    QUEUE_NAME = "vaultstream:tasks"
    PROCESSING_SET = "vaultstream:processing"
    
    def __init__(self):
        self.redis: Optional[aioredis.Redis] = None
    
    async def connect(self):
        """连接Redis"""
        self.redis = await aioredis.from_url(
            settings.redis_url,
            encoding="utf-8",
            decode_responses=True
        )
        logger.info("Redis connected")
    
    async def disconnect(self):
        """断开连接"""
        if self.redis:
            await self.redis.close()
            logger.info("Redis disconnected")

    async def ping(self) -> bool:
        """用于健康检查的轻量 Redis 探活。"""
        try:
            if not self.redis:
                return False
            await self.redis.ping()
            return True
        except Exception:
            return False
    
    async def enqueue(self, task_data: Dict[str, Any]) -> bool:
        """
        将任务加入队列
        
        Args:
            task_data: 任务数据，应包含 content_id 等信息
            
        Returns:
            是否成功
        """
        try:
            task_id = ensure_task_id(task_data.get("task_id"))
            task_data = {**task_data, "task_id": task_id}
            content_id = task_data.get("content_id")
            task_json = json.dumps(task_data)
            await self.redis.lpush(self.QUEUE_NAME, task_json)
            with log_context(task_id=task_id, content_id=content_id):
                logger.info("任务已入队")
            return True
        except Exception as e:
            logger.error(f"任务入队失败: {e}")
            return False
    
    async def dequeue(self, timeout: int = 5) -> Optional[Dict[str, Any]]:
        """
        从队列取出任务（阻塞）
        
        Args:
            timeout: 超时时间（秒）
            
        Returns:
            任务数据或None
        """
        try:
            result = await self.redis.brpop(self.QUEUE_NAME, timeout=timeout)
            if result:
                _, task_json = result
                task_data = json.loads(task_json)
                
                # 标记为处理中
                content_id = task_data.get('content_id')
                if content_id:
                    await self.redis.sadd(self.PROCESSING_SET, content_id)
                
                return task_data
        except Exception as e:
            logger.error(f"任务出队失败: {e}")
        return None
    
    async def mark_complete(self, content_id: int):
        """标记任务完成"""
        try:
            await self.redis.srem(self.PROCESSING_SET, content_id)
            logger.info(f"任务已完成: {content_id}")
        except Exception as e:
            logger.error(f"标记任务完成失败: {e}")
    
    async def is_processing(self, content_id: int) -> bool:
        """检查任务是否正在处理"""
        try:
            return await self.redis.sismember(self.PROCESSING_SET, content_id)
        except Exception as e:
            logger.error(f"检查任务状态失败: {e}")
            return False
    
    async def get_queue_size(self) -> int:
        """获取队列大小"""
        try:
            return await self.redis.llen(self.QUEUE_NAME)
        except Exception as e:
            logger.error(f"获取队列大小失败: {e}")
            return 0


# 全局实例
task_queue = TaskQueue()
