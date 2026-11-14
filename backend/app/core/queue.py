"""SQLite 解析队列：每行只执行一次，超时失败，不自动重新领取。"""
import asyncio
from contextlib import nullcontext
from datetime import timedelta
from typing import Any
from uuid import uuid4
from time import monotonic

from sqlalchemy import select, update, func, or_
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import aliased

from app.core.db_adapter import AsyncSessionLocal
from app.core.logging import logger, ensure_task_id
from app.core.time_utils import utcnow
from app.models import Content, ContentStatus, Task, TaskStatus, BackgroundTaskRun


class TaskQueue:
    EXECUTION_TIMEOUT = timedelta(minutes=30)

    def __init__(self):
        self._next_recovery = 0.0

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

    def add(
        self, session: AsyncSession, task_type: str, payload: dict[str, Any],
        *, run_name: str | None = None,
    ) -> Task:
        """任务与运行身份随业务事务一同提交。"""
        run_id = uuid4().hex
        data = {**payload, "task_id": ensure_task_id(payload.get("task_id")),
                "run_id": run_id, "run_name": run_name or task_type}
        task = Task(task_type=task_type, payload=data, status=TaskStatus.PENDING,
                    priority=int(payload.get("priority", 0)))
        session.add(task)
        session.add(BackgroundTaskRun(
            run_id=run_id, task=data["run_name"], status="pending",
            run_metadata={key: value for key, value in data.items()
                          if key not in ("run_id", "run_name")},
        ))
        return task

    async def enqueue_parse(self, session: AsyncSession, content_id: int, *, manual: bool = False) -> Task:
        await session.execute(update(Content).where(Content.id == content_id).values(updated_at=Content.updated_at))
        pending = await session.scalar(select(Task).where(
            Task.task_type == "parse_content", Task.status == TaskStatus.PENDING,
            Task.payload["content_id"].as_integer() == content_id,
        ).order_by(Task.id).limit(1))
        payload = {"content_id": content_id, "force": manual,
                   "trigger": "manual" if manual else "auto", "priority": 10 if manual else 0}
        if pending is None:
            return self.add(session, "parse_content", payload,
                            run_name="content_reparse" if manual else "content_parse")
        if manual:
            data = {**pending.payload, **payload, "run_name": "content_reparse"}
            data["run_id"] = data.get("run_id") or uuid4().hex
            pending.payload = data
            pending.priority = 10
            run = await session.get(BackgroundTaskRun, data["run_id"])
            metadata = {key: value for key, value in data.items() if key not in ("run_id", "run_name")}
            if run is None:
                session.add(BackgroundTaskRun(run_id=data["run_id"], task="content_reparse",
                                             status="pending", run_metadata=metadata))
            else:
                run.task = "content_reparse"
                run.run_metadata = metadata
        return pending

    async def dequeue(self, timeout: int = 5, *, parse_enabled: bool = True) -> Task | None:
        for _ in range(timeout):
            try:
                async with AsyncSessionLocal() as session:
                    if monotonic() >= self._next_recovery:
                        self._next_recovery = monotonic() + 60
                        await self._recover_expired(session)
                        await self._settle_orphaned_runs()
                    now = utcnow()
                    active = aliased(Task)
                    eligible = or_(Task.task_type != "parse_content",
                                   Task.payload["trigger"].as_string() == "manual")
                    candidate = select(Task.id).where(
                        Task.status == TaskStatus.PENDING,
                        True if parse_enabled else eligible,
                        ~select(active.id).where(
                            active.status == TaskStatus.RUNNING,
                            active.payload["content_id"].as_integer() == Task.payload["content_id"].as_integer(),
                        ).exists(),
                    ).order_by(Task.priority.desc(), Task.created_at, Task.id).limit(1)
                    candidate_id = await session.scalar(candidate)
                    if candidate_id is not None:
                        # Re-evaluate eligibility while holding the SQLite writer lock.
                        task = (await session.execute(
                            update(Task).where(Task.id == candidate_id, Task.id == candidate.scalar_subquery())
                            .values(status=TaskStatus.RUNNING, started_at=now)
                            .returning(Task)
                        )).scalar_one_or_none()
                        if task is not None and not task.payload.get("run_id"):
                            run_name = {"parse_content": "content_parse", "repair_media": "media_repair"}.get(task.task_type, task.task_type)
                            data = {**task.payload, "run_id": uuid4().hex, "run_name": run_name}
                            task.payload = data
                            session.add(BackgroundTaskRun(run_id=data["run_id"], task=data["run_name"],
                                                         status="pending", run_metadata={"content_id": data.get("content_id")}))
                        await session.commit()
                        if task is not None:
                            return task
                await asyncio.sleep(1)
            except Exception as e:
                logger.error(f"任务出队失败: {e}")
                await asyncio.sleep(1)
        return None

    async def _recover_expired(self, session: AsyncSession) -> None:
        now = utcnow()
        # 崩溃或取消后留下的任务只结算失败，不重跑外部解析。
        expired = (await session.execute(
            update(Task).where(
                Task.status == TaskStatus.RUNNING,
                or_(Task.started_at.is_(None), Task.started_at <= now - self.EXECUTION_TIMEOUT),
            ).values(
                status=TaskStatus.FAILED,
                last_error="Task execution timed out",
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
                last_error="Task execution timed out",
                last_error_type="TimeoutError",
                last_error_at=now,
            ))

        await session.commit()

    async def _settle_orphaned_runs(self) -> None:
        from app.services.background_task_state import record_task_run_error, record_task_run_success

        async with AsyncSessionLocal() as db:
            rows = (await db.execute(select(Task).join(
                BackgroundTaskRun, BackgroundTaskRun.run_id == Task.payload["run_id"].as_string(),
            ).where(
                BackgroundTaskRun.status.in_(["pending", "running"]),
                Task.status.in_([TaskStatus.FAILED, TaskStatus.COMPLETED]),
                Task.completed_at < utcnow() - timedelta(minutes=1),
            ).limit(50))).scalars().all()
        for task in rows:
            data = task.payload
            result = {"content_id": data.get("content_id"), "task_db_id": task.id}
            if task.status == TaskStatus.FAILED:
                await record_task_run_error(data["run_name"], data["run_id"], task.last_error or "Task failed", **result)
            else:
                await record_task_run_success(data["run_name"], data["run_id"], **result)

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

task_queue = TaskQueue()
