"""
任务队列 - 基于 SQLite 任务表
"""
import asyncio
from typing import Optional, Dict, Any
from sqlalchemy import select, update, and_

from app.core.logging import logger, log_context, ensure_task_id
from app.core.time_utils import utcnow


class TaskQueue:
    """基于 SQLite 任务表的队列"""
    
    DEFAULT_TASK_SCHEMA_VERSION = 1
    
    def __init__(self):
        self._session_maker = None
    
    async def connect(self):
        from app.core.database import AsyncSessionLocal
        self._session_maker = AsyncSessionLocal
        logger.info("SQLite 队列已连接")
    
    async def disconnect(self):
        logger.info("SQLite 队列已断开")
    
    async def ping(self) -> bool:
        try:
            from app.models import Task
            async with self._session_maker() as session:
                await session.execute(select(Task).limit(1))
            return True
        except Exception:
            return False
    
    async def enqueue(self, task_data: Dict[str, Any]) -> bool:
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
                    logger.info(f"任务已入队: task_db_id={task.id}")
            
            return True
        except Exception as e:
            logger.error(f"任务入队失败: {e}")
            return False
    
    async def dequeue(self, timeout: int = 5) -> Optional[Dict[str, Any]]:
        """从队列取出任务（CAS 原子性获取，兼容 SQLite）"""
        from app.models import Task, TaskStatus
        
        for _ in range(timeout):
            try:
                async with self._session_maker() as session:
                    # 1. 查找候选任务
                    stmt = (
                        select(Task.id)
                        .where(Task.status == TaskStatus.PENDING)
                        .order_by(Task.priority.desc(), Task.created_at)
                        .limit(1)
                    )
                    result = await session.execute(stmt)
                    row = result.first()
                    
                    if not row:
                        await asyncio.sleep(1)
                        continue
                    
                    candidate_id = row[0]
                    
                    # 2. CAS 更新：仅当状态仍为 PENDING 时才标记为 RUNNING
                    cas_stmt = (
                        update(Task)
                        .where(and_(Task.id == candidate_id, Task.status == TaskStatus.PENDING))
                        .values(
                            status=TaskStatus.RUNNING,
                            started_at=utcnow(),
                            retry_count=Task.retry_count + 1,
                        )
                    )
                    cas_result = await session.execute(cas_stmt)
                    
                    if cas_result.rowcount == 0:
                        # 被其他 worker 抢占，重试
                        continue
                    
                    await session.commit()
                    
                    # 3. 重新读取 payload
                    task = (await session.execute(
                        select(Task).where(Task.id == candidate_id)
                    )).scalar_one()
                    
                    return task.payload
                    
            except Exception as e:
                logger.error(f"任务出队失败: {e}")
                await asyncio.sleep(1)
        
        return None
    
    async def mark_complete(self, content_id: int):
        try:
            from app.models import Task, TaskStatus
            from sqlalchemy import cast, String
            
            async with self._session_maker() as session:
                stmt = (
                    update(Task)
                    .where(
                        and_(
                            cast(Task.payload['content_id'], String) == str(content_id),
                            Task.status == TaskStatus.RUNNING
                        )
                    )
                    .values(status=TaskStatus.COMPLETED, completed_at=utcnow())
                )
                await session.execute(stmt)
                await session.commit()
                logger.info(f"任务已完成: {content_id}")
        except Exception as e:
            logger.error(f"标记任务完成失败: {e}")
    
    async def push_dead_letter(self, task_data: Dict[str, Any], *, reason: str):
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
                    .values(status=TaskStatus.FAILED, last_error=reason, completed_at=utcnow())
                )
                await session.execute(stmt)
                await session.commit()
        except Exception as e:
            logger.error(f"写入死信队列失败: {e}")
    
    async def is_processing(self, content_id: int) -> bool:
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
            logger.error(f"检查任务状态失败: {e}")
            return False
    
    async def get_queue_size(self) -> int:
        try:
            from app.models import Task, TaskStatus
            from sqlalchemy import func
            
            async with self._session_maker() as session:
                stmt = select(func.count(Task.id)).where(Task.status == TaskStatus.PENDING)
                result = await session.execute(stmt)
                return result.scalar() or 0
        except Exception as e:
            logger.error(f"获取队列大小失败: {e}")
            return 0
