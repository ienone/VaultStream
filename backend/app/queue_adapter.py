"""
队列适配器层 - 支持 SQLite 任务表和 Redis 切换
"""
from abc import ABC, abstractmethod
from typing import Optional, Dict, Any
import asyncio
from datetime import datetime, timezone
from sqlalchemy import select, update, and_

from app.config import settings
from app.logging import logger, log_context, ensure_task_id


def utcnow() -> datetime:
    """返回UTC时间的当前时间戳"""
    return datetime.now(timezone.utc).replace(tzinfo=None)


class QueueAdapter(ABC):
    """队列适配器基类"""
    
    @abstractmethod
    async def connect(self):
        """连接队列"""
        pass
    
    @abstractmethod
    async def disconnect(self):
        """断开连接"""
        pass
    
    @abstractmethod
    async def ping(self) -> bool:
        """健康检查"""
        pass
    
    @abstractmethod
    async def enqueue(self, task_data: Dict[str, Any]) -> bool:
        """入队"""
        pass
    
    @abstractmethod
    async def dequeue(self, timeout: int = 5) -> Optional[Dict[str, Any]]:
        """出队"""
        pass
    
    @abstractmethod
    async def mark_complete(self, content_id: int):
        """标记完成"""
        pass


class SQLiteQueueAdapter(QueueAdapter):
    """基于 SQLite 任务表的队列（轻量模式）"""
    
    DEFAULT_TASK_SCHEMA_VERSION = 1
    
    def __init__(self):
        self._session_maker = None
    
    async def connect(self):
        """初始化会话工厂"""
        from app.database import AsyncSessionLocal
        self._session_maker = AsyncSessionLocal
        logger.info("SQLite 队列已连接")
    
    async def disconnect(self):
        """断开连接（无需操作）"""
        logger.info("SQLite 队列已断开")
    
    async def ping(self) -> bool:
        """健康检查"""
        try:
            from app.models import Task
            async with self._session_maker() as session:
                await session.execute(select(Task).limit(1))
            return True
        except Exception:
            return False
    
    async def enqueue(self, task_data: Dict[str, Any]) -> bool:
        """将任务加入队列（写入任务表）"""
        try:
            from app.models import Task, TaskStatus
            
            task_id = ensure_task_id(task_data.get("task_id"))
            content_id = task_data.get("content_id")
            
            task_payload = {
                "schema_version": int(task_data.get("schema_version") or self.DEFAULT_TASK_SCHEMA_VERSION),
                "action": task_data.get("action") or "parse",
                "attempt": int(task_data.get("attempt") or 0),
                "max_attempts": int(task_data.get("max_attempts") or 3),
                **task_data,
                "task_id": task_id,
            }
            
            async with self._session_maker() as session:
                task = Task(
                    task_type="parse_content",
                    payload=task_payload,
                    status=TaskStatus.PENDING,
                    priority=int(task_data.get("priority", 0)),
                    max_retries=int(task_data.get("max_attempts") or 3)
                )
                session.add(task)
                await session.commit()
                
                with log_context(task_id=task_id, content_id=content_id):
                    logger.info(f"任务已入队 (SQLite): task_db_id={task.id}")
            
            return True
        except Exception as e:
            logger.error(f"任务入队失败 (SQLite): {e}")
            return False
    
    async def dequeue(self, timeout: int = 5) -> Optional[Dict[str, Any]]:
        """从队列取出任务（原子性获取）"""
        from app.models import Task, TaskStatus
        
        # 轮询模式（简化实现）
        max_attempts = timeout
        for attempt in range(max_attempts):
            try:
                async with self._session_maker() as session:
                    async with session.begin():
                        # 使用 SELECT FOR UPDATE SKIP LOCKED 实现原子性
                        stmt = (
                            select(Task)
                            .where(Task.status == TaskStatus.PENDING)
                            .order_by(Task.priority.desc(), Task.created_at)
                            .limit(1)
                            .with_for_update(skip_locked=True)
                        )
                        
                        result = await session.execute(stmt)
                        task = result.scalar_one_or_none()
                        
                        if not task:
                            await asyncio.sleep(1)
                            continue
                        
                        # 标记为运行中
                        task.status = TaskStatus.RUNNING
                        task.started_at = utcnow()
                        task.retry_count += 1
                        await session.commit()
                        
                        return task.payload
                    
            except Exception as e:
                logger.error(f"任务出队失败 (SQLite): {e}")
                await asyncio.sleep(1)
        
        return None
    
    async def mark_complete(self, content_id: int):
        """标记任务完成"""
        try:
            from app.models import Task, TaskStatus
            from sqlalchemy import cast, String
            
            async with self._session_maker() as session:
                # 使用 cast 来兼容 SQLite 的 JSON 查询
                stmt = (
                    update(Task)
                    .where(
                        and_(
                            cast(Task.payload['content_id'], String) == str(content_id),
                            Task.status == TaskStatus.RUNNING
                        )
                    )
                    .values(
                        status=TaskStatus.COMPLETED,
                        completed_at=utcnow()
                    )
                )
                await session.execute(stmt)
                await session.commit()
                logger.info(f"任务已完成: {content_id}")
        except Exception as e:
            logger.error(f"标记任务完成失败 (SQLite): {e}")
    
    async def push_dead_letter(self, task_data: Dict[str, Any], *, reason: str):
        """将任务标记为失败"""
        try:
            from app.models import Task, TaskStatus
            from sqlalchemy import cast, String
            content_id = task_data.get("content_id")
            
            async with self._session_maker() as session:
                stmt = (
                    update(Task)
                    .where(
                        and_(
                            cast(Task.payload['content_id'], String) == str(content_id),
                            Task.status == TaskStatus.RUNNING
                        )
                    )
                    .values(
                        status=TaskStatus.FAILED,
                        last_error=reason,
                        completed_at=utcnow()
                    )
                )
                await session.execute(stmt)
                await session.commit()
        except Exception as e:
            logger.error(f"写入死信队列失败 (SQLite): {e}")
    
    async def is_processing(self, content_id: int) -> bool:
        """检查任务是否正在处理"""
        try:
            from app.models import Task, TaskStatus
            from sqlalchemy import cast, String
            
            async with self._session_maker() as session:
                stmt = select(Task).where(
                    and_(
                        cast(Task.payload['content_id'], String) == str(content_id),
                        Task.status == TaskStatus.RUNNING
                    )
                )
                result = await session.execute(stmt)
                return result.scalar_one_or_none() is not None
        except Exception as e:
            logger.error(f"检查任务状态失败 (SQLite): {e}")
            return False
    
    async def get_queue_size(self) -> int:
        """获取队列大小"""
        try:
            from app.models import Task, TaskStatus
            from sqlalchemy import func
            
            async with self._session_maker() as session:
                stmt = select(func.count(Task.id)).where(Task.status == TaskStatus.PENDING)
                result = await session.execute(stmt)
                return result.scalar() or 0
        except Exception as e:
            logger.error(f"获取队列大小失败 (SQLite): {e}")
            return 0


# Redis 队列适配器已移除，如需使用请参考 git 历史或文档重新实现
# class RedisQueueAdapter(QueueAdapter):
#     """基于 Redis 的队列（生产模式 - 已废弃）"""
#     pass


def get_queue_adapter() -> QueueAdapter:
    """根据配置获取队列适配器"""
    queue_type = settings.queue_type
    
    if queue_type == "sqlite":
        return SQLiteQueueAdapter()
    else:
        raise ValueError(
            f"不支持的队列类型: {queue_type}。"
            f"当前仅支持 'sqlite'。如需 Redis 支持，请参考文档重新实现 RedisQueueAdapter。"
        )
