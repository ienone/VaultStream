"""SQLite 解析队列：每行只执行一次，超时失败，不自动重新领取。"""
import asyncio
from contextlib import nullcontext
from datetime import timedelta
from typing import Any

from sqlalchemy import select, update, func, or_
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.db_adapter import AsyncSessionLocal
from app.core.logging import logger, ensure_task_id
from app.core.time_utils import utcnow
from app.models import Content, ContentStatus, Task, TaskStatus


class TaskQueue:
    EXECUTION_TIMEOUT = timedelta(minutes=30)

    async def connect(self):
        logger.info("SQLite 队列已连接")

    async def disconnect(self):
        logger.info("SQLite 队列已断开")

    async def ping(self) -> bool:
        try:
            async with AsyncSessionLocal() as session:
                await session.execute(select(Task.id).limit(1))
            return True
        except Exception:
            return False

    async def enqueue(self, task_data: dict[str, Any]) -> bool:
        try:
            async with AsyncSessionLocal() as session:
                task = Task(
                    task_type="parse_content",
                    payload={**task_data, "task_id": ensure_task_id(task_data.get("task_id"))},
                    status=TaskStatus.PENDING,
                    priority=int(task_data.get("priority", 0)),
                )
                session.add(task)
                await session.commit()
                logger.info("任务已入队: task_db_id={}", task.id)
            return True
        except Exception as e:
            logger.error(f"任务入队失败: {e}")
            return False

    async def dequeue(self, timeout: int = 5) -> Task | None:
        for _ in range(timeout):
            try:
                async with AsyncSessionLocal() as session:
                    now = utcnow()
                    # 崩溃或取消后留下的任务只结算失败，不重跑外部解析。
                    expired = (await session.execute(
                        update(Task).where(
                            Task.status == TaskStatus.RUNNING,
                            or_(Task.started_at.is_(None), Task.started_at <= now - self.EXECUTION_TIMEOUT),
                        ).values(
                            status=TaskStatus.FAILED,
                            last_error="Parsing timed out",
                            completed_at=now,
                        ).returning(Task.payload, Task.task_type)
                    )).all()
                    if expired:
                        other_running = select(Task.id).where(
                            Task.status == TaskStatus.RUNNING,
                            Task.payload["content_id"].as_integer() == Content.id,
                        ).exists()
                        await session.execute(update(Content).where(
                            Content.id.in_([payload["content_id"] for payload, kind in expired
                                            if kind == "parse_content" and payload.get("content_id")]),
                            Content.deleted_at.is_(None),
                            Content.status == ContentStatus.PROCESSING,
                            ~other_running,
                        ).values(
                            status=ContentStatus.PARSE_FAILED,
                            last_error="Parsing timed out",
                            last_error_type="TimeoutError",
                            last_error_at=now,
                        ))

                    candidate = select(Task.id).where(
                        Task.status == TaskStatus.PENDING,
                    ).order_by(Task.priority.desc(), Task.created_at, Task.id).limit(1).scalar_subquery()
                    task = (await session.execute(
                        update(Task).where(Task.id == candidate, Task.status == TaskStatus.PENDING)
                        .values(status=TaskStatus.RUNNING, started_at=now)
                        .returning(Task)
                    )).scalar_one_or_none()
                    await session.commit()
                    if task is not None:
                        return task
                await asyncio.sleep(1)
            except Exception as e:
                logger.error(f"任务出队失败: {e}")
                await asyncio.sleep(1)
        return None

    async def owns(self, session: AsyncSession, task: Task) -> bool:
        """一次性任务仍在运行才允许写结果；同时取得 SQLite 写锁。"""
        result = await session.execute(
            update(Task).where(Task.id == task.id, Task.status == TaskStatus.RUNNING)
            .values(started_at=Task.started_at)
        )
        return result.rowcount == 1

    async def mark_complete(self, task: Task, *, session: AsyncSession | None = None) -> bool:
        owns_session = session is None
        async with AsyncSessionLocal() if owns_session else nullcontext(session) as db:
            result = await db.execute(
                update(Task).where(Task.id == task.id, Task.status == TaskStatus.RUNNING)
                .values(status=TaskStatus.COMPLETED, completed_at=utcnow())
            )
            if owns_session:
                await db.commit()
            return result.rowcount == 1

    async def mark_failed(
        self, task: Task, *, reason: str, session: AsyncSession | None = None,
    ) -> bool:
        owns_session = session is None
        async with AsyncSessionLocal() if owns_session else nullcontext(session) as db:
            result = await db.execute(
                update(Task).where(Task.id == task.id, Task.status == TaskStatus.RUNNING)
                .values(status=TaskStatus.FAILED, last_error=reason, completed_at=utcnow())
            )
            if owns_session:
                await db.commit()
            return result.rowcount == 1

    async def get_queue_size(self) -> int:
        async with AsyncSessionLocal() as session:
            return (await session.execute(
                select(func.count(Task.id)).where(Task.status == TaskStatus.PENDING)
            )).scalar_one()
