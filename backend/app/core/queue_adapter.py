"""
任务队列 - 基于 SQLite 任务表
"""
import asyncio
from contextlib import nullcontext
from dataclasses import dataclass
from datetime import datetime, timedelta
from typing import Any, Optional
from sqlalchemy import select, update, and_, or_, cast, String
from sqlalchemy.ext.asyncio import AsyncSession, async_sessionmaker

from app.core.logging import logger, log_context, ensure_task_id
from app.core.time_utils import utcnow
from app.models import Content, ContentStatus, Task, TaskStatus


@dataclass(frozen=True)
class ClaimedTask:
    """A claimed database row plus its external task payload."""

    db_id: int
    payload: dict[str, Any]
    started_at: datetime
    generation: int


class TaskQueue:
    """基于 SQLite 任务表的队列"""
    
    DEFAULT_TASK_SCHEMA_VERSION = 1
    LEASE_DURATION = timedelta(minutes=30)
    
    def __init__(self):
        self._session_maker: async_sessionmaker[AsyncSession] | None = None
    
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
    
    async def enqueue(self, task_data: dict[str, Any]) -> bool:
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
    
    async def dequeue(self, timeout: int = 5) -> Optional[ClaimedTask]:
        """Claim pending work or an expired execution lease with a fenced CAS."""
        from app.models import Task, TaskStatus
        
        for _ in range(timeout):
            try:
                async with self._session_maker() as session:
                    # 1. 查找候选任务
                    now = utcnow()
                    expires_before = now - self.LEASE_DURATION
                    expired = or_(Task.started_at.is_(None), Task.started_at <= expires_before)
                    stmt = (
                        select(Task.id, Task.status, Task.retry_count, Task.max_retries, Task.payload)
                        .where(or_(
                            Task.status == TaskStatus.PENDING,
                            and_(Task.status == TaskStatus.RUNNING, expired),
                        ))
                        .order_by(Task.priority.desc(), Task.created_at)
                        .limit(1)
                    )
                    result = await session.execute(stmt)
                    row = result.first()
                    
                    if not row:
                        await asyncio.sleep(1)
                        continue
                    
                    candidate_id, candidate_status, retries, max_retries, payload = row

                    if candidate_status == TaskStatus.RUNNING and retries >= max_retries:
                        exhausted = await session.execute(
                            update(Task)
                            .where(
                                Task.id == candidate_id,
                                Task.status == TaskStatus.RUNNING,
                                expired,
                                Task.retry_count == retries,
                            )
                            .values(
                                status=TaskStatus.FAILED,
                                last_error="execution_lease_expired: max_retries_reached",
                                completed_at=now,
                            )
                        )
                        if exhausted.rowcount:
                            await self._release_exhausted_content(
                                session,
                                candidate_id,
                                (payload or {}).get("content_id"),
                            )
                        await session.commit()
                        continue
                    
                    # 2. CAS 领取待处理任务或同一代已过期任务
                    claim_time = utcnow()
                    ownership_condition = (
                        Task.status == TaskStatus.PENDING
                        if candidate_status == TaskStatus.PENDING
                        else and_(
                            Task.status == TaskStatus.RUNNING,
                            expired,
                            Task.retry_count == retries,
                        )
                    )
                    cas_stmt = (
                        update(Task)
                        .where(Task.id == candidate_id, ownership_condition)
                        .values(
                            status=TaskStatus.RUNNING,
                            started_at=claim_time,
                            retry_count=Task.retry_count + 1,
                        )
                    )
                    cas_result = await session.execute(cas_stmt)
                    
                    if cas_result.rowcount == 0:
                        # 被其他 worker 抢占，重试
                        continue
                    
                    # Capture this generation before releasing the writer lock.
                    # A delayed post-commit read could adopt a replacement lease.
                    task = (await session.execute(
                        select(Task).where(Task.id == candidate_id)
                    )).scalar_one()
                    
                    claim = ClaimedTask(
                        db_id=task.id,
                        payload=dict(task.payload or {}),
                        started_at=task.started_at,
                        generation=task.retry_count,
                    )
                    await session.commit()
                    return claim
                    
            except Exception as e:
                logger.error(f"任务出队失败: {e}")
                await asyncio.sleep(1)
        
        return None
    
    @classmethod
    def ownership_predicate(cls, task_model: type[Task], claim: ClaimedTask):
        return and_(
            task_model.id == claim.db_id,
            task_model.status == TaskStatus.RUNNING,
            task_model.started_at == claim.started_at,
            task_model.retry_count == claim.generation,
            task_model.started_at > utcnow() - cls.LEASE_DURATION,
        )

    async def owns(self, session: AsyncSession, claim: ClaimedTask) -> bool:
        """Acquire SQLite's write lock and validate an unexpired claim."""
        from app.models import Task
        result = await session.execute(
            update(Task)
            .where(self.ownership_predicate(Task, claim))
            .values(started_at=Task.started_at)
        )
        return result.rowcount == 1

    async def mark_complete(
        self,
        claim: ClaimedTask,
        *,
        session: AsyncSession | None = None,
    ) -> bool:
        try:
            from app.models import Task, TaskStatus
            owns_session = session is None
            if owns_session:
                session = self._session_maker()
            async with session if owns_session else nullcontext(session):
                stmt = (
                    update(Task)
                    .where(self.ownership_predicate(Task, claim))
                    .values(status=TaskStatus.COMPLETED, completed_at=utcnow())
                )
                result = await session.execute(stmt)
                if owns_session:
                    await session.commit()
                changed = result.rowcount == 1
                logger.debug(f"任务已完成: task_db_id={claim.db_id}, changed={changed}")
                return changed
        except Exception as e:
            logger.error(f"标记任务完成失败: {e}")
            return False

    async def mark_failed(
        self,
        claim: ClaimedTask,
        *,
        reason: str,
        session: AsyncSession | None = None,
    ) -> bool:
        try:
            from app.models import Task, TaskStatus

            owns_session = session is None
            if owns_session:
                session = self._session_maker()
            async with session if owns_session else nullcontext(session):
                stmt = (
                    update(Task)
                    .where(
                        and_(
                            self.ownership_predicate(Task, claim),
                        )
                    )
                    .values(status=TaskStatus.FAILED, last_error=reason, completed_at=utcnow())
                )
                result = await session.execute(stmt)
                if owns_session:
                    await session.commit()
                return result.rowcount == 1
        except Exception as e:
            logger.error(f"标记任务失败: {e}")
            return False

    async def _release_exhausted_content(
        self,
        session: AsyncSession,
        task_db_id: int,
        content_id: int | None,
    ) -> None:
        """Settle exhausted task and its content inside the caller's transaction."""
        if not content_id:
            return
        other = select(Task.id).where(
            Task.id != task_db_id,
            Task.status == TaskStatus.RUNNING,
            cast(Task.payload["content_id"], String) == str(content_id),
        ).exists()
        await session.execute(
            update(Content).where(
                Content.id == content_id,
                Content.deleted_at.is_(None),
                Content.status == ContentStatus.PROCESSING,
                ~other,
            ).values(
                status=ContentStatus.PARSE_FAILED,
                last_error="execution lease expired",
                last_error_type="LeaseExpired",
                last_error_at=utcnow(),
            )
        )
    
    async def is_processing(self, content_id: int) -> bool:
        try:
            from app.models import Task, TaskStatus
            from sqlalchemy import cast, String
            
            async with self._session_maker() as session:
                stmt = select(Task.id).where(
                    and_(
                        cast(Task.payload['content_id'], String) == str(content_id),
                        Task.status == TaskStatus.RUNNING
                    )
                ).limit(1)
                result = await session.execute(stmt)
                return result.first() is not None
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
