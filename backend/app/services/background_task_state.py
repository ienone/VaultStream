from __future__ import annotations

from uuid import uuid4
from typing import Any

from pydantic import TypeAdapter
from app.schemas.base import OptionalUtcDatetime

from sqlalchemy import and_, case, delete, func, select, true, union_all
from sqlalchemy.dialects.sqlite import insert as sqlite_insert

from app.core.db_adapter import AsyncSessionLocal
from app.core.events import event_bus
from app.core.logging import logger
from app.core.time_utils import utcnow
from app.models import BackgroundTaskRun, NotificationMessage
from app.services.task_run_presentation import build_task_run_presentation, TASK_TERMINAL_STATUSES

_UTC_DATETIME = TypeAdapter(OptionalUtcDatetime)
_MAX_RECENT_RUNS = 200


def latest_favorites_runs():
    """Keep each platform's latest result even when other platforms fill the history window."""
    run = BackgroundTaskRun
    items = func.json_each(run.result, "$.results").table_valued("key", "value")
    criteria = (run.task == "favorites_sync", run.status.in_(TASK_TERMINAL_STATUSES))
    single = select(run.run_id, run.result["platform"].as_string().label("platform"), run.finished_at).where(
        *criteria, func.json_type(run.result, "$.result") == "object",
        run.result["platform"].as_string().is_not(None),
    )
    multiple = select(run.run_id, items.c.key.label("platform"), run.finished_at).join(
        items, true(),
    ).where(*criteria)
    results = union_all(single, multiple).subquery()
    ranked = select(results.c.run_id, results.c.platform, func.row_number().over(
        partition_by=results.c.platform,
        order_by=(results.c.finished_at.desc(), results.c.run_id.desc()),
    ).label("rank")).subquery()
    return select(ranked.c.run_id, ranked.c.platform).where(ranked.c.rank == 1).subquery()


async def get_background_task_states() -> dict[str, dict[str, Any]]:
    """Project current status and retained-history counts from the run ledger."""
    latest = select(
        BackgroundTaskRun.run_id,
        func.row_number().over(partition_by=BackgroundTaskRun.task,
            order_by=(BackgroundTaskRun.started_at.desc(), BackgroundTaskRun.run_id.desc())).label("rank"),
    ).subquery()
    history = select(
        BackgroundTaskRun.task,
        func.max(BackgroundTaskRun.started_at).label("last_started_at"),
        func.max(case((BackgroundTaskRun.status == "success", BackgroundTaskRun.finished_at))).label("last_success_at"),
        func.max(case((BackgroundTaskRun.status == "error", BackgroundTaskRun.finished_at))).label("last_error_at"),
        func.count().label("run_count"),
        func.sum(case((BackgroundTaskRun.status == "error", 1), else_=0)).label("error_count"),
    ).group_by(BackgroundTaskRun.task).subquery()
    async with AsyncSessionLocal() as db:
        rows = (await db.execute(select(BackgroundTaskRun, history).join(
            latest, latest.c.run_id == BackgroundTaskRun.run_id,
        ).join(history, history.c.task == BackgroundTaskRun.task).where(latest.c.rank == 1))).all()
    states = {}
    for row in rows:
        run = row[0]
        stats = dict(row._mapping)
        stats.pop("BackgroundTaskRun")
        states[run.task] = {
            **(run.run_metadata or {}),
            **{key: value for key, value in (run.result or {}).items() if key not in {"result", "results"}},
            **stats,
            "status": "ok" if run.status == "success" else run.status,
            "last_error": run.error,
        }
    return states


async def record_task_run_started(
    task_name: str,
    *,
    run_id: str | None = None,
    **metadata: Any,
) -> dict[str, Any]:
    return await _upsert_run(task_name, run_id or uuid4().hex, status="running", metadata=metadata)


async def record_task_run_success(
    task_name: str,
    run_id: str | None = None,
    **result: Any,
) -> dict[str, Any]:
    return await _upsert_run(task_name, run_id or uuid4().hex, status="success", result=result)


async def record_task_run_error(
    task_name: str,
    run_id: str | None,
    error: BaseException | str,
    **result: Any,
) -> dict[str, Any]:
    return await _upsert_run(task_name, run_id or uuid4().hex, status="error", error=str(error)[:1000], result=result)


async def get_recent_task_runs(task_name: str, limit: int = _MAX_RECENT_RUNS) -> list[dict[str, Any]]:
    bounded_limit = max(0, min(limit, _MAX_RECENT_RUNS))
    if bounded_limit == 0:
        return []
    async with AsyncSessionLocal() as db:
        rows = (
            await db.execute(
                select(BackgroundTaskRun)
                .where(BackgroundTaskRun.task == task_name)
                .order_by(BackgroundTaskRun.started_at.desc())
                .limit(bounded_limit)
            )
        ).scalars().all()
    return [_serialize_run(row) for row in rows]


async def get_recent_task_runs_all(
    limit: int = _MAX_RECENT_RUNS,
) -> list[dict[str, Any]]:
    bounded_limit = max(0, min(limit, _MAX_RECENT_RUNS))
    if bounded_limit == 0:
        return []
    async with AsyncSessionLocal() as db:
        rows = (
            await db.execute(
                select(BackgroundTaskRun)
                .order_by(BackgroundTaskRun.started_at.desc())
                .limit(bounded_limit)
            )
        ).scalars().all()
    return [_serialize_run(row) for row in rows]


async def get_task_run(run_id: str) -> dict[str, Any] | None:
    async with AsyncSessionLocal() as db:
        row = await db.get(BackgroundTaskRun, run_id)
    return _serialize_run(row) if row is not None else None


async def _upsert_run(
    task_name: str,
    run_id: str,
    *,
    status: str,
    metadata: dict[str, Any] | None = None,
    result: dict[str, Any] | None = None,
    error: str | None = None,
) -> dict[str, Any]:
    """Write lifecycle fields directly; API serialization is output-only."""
    now = utcnow()
    terminal = status != "running"
    values = {
        "run_id": run_id,
        "task": task_name,
        "status": status,
        "started_at": now,
        "finished_at": now if terminal else None,
        "error": error,
        "run_metadata": metadata or {},
        "result": result,
        "created_at": now,
        "updated_at": now,
    }
    insert_statement = sqlite_insert(BackgroundTaskRun).values(**values)
    if terminal:
        statement = insert_statement.on_conflict_do_update(
            index_elements=[BackgroundTaskRun.run_id],
            set_={
                "status": values["status"],
                "finished_at": values["finished_at"],
                "error": values["error"],
                "result": values["result"],
                "updated_at": values["updated_at"],
            },
            where=and_(
                BackgroundTaskRun.task == task_name,
                BackgroundTaskRun.status == "running",
            ),
        )
    else:
        statement = insert_statement.on_conflict_do_nothing(
            index_elements=[BackgroundTaskRun.run_id]
        )

    async with AsyncSessionLocal() as db:
        async with db.begin():
            write_result = await db.execute(statement)
            stale_run_ids = (
                select(BackgroundTaskRun.run_id)
                .where(
                    BackgroundTaskRun.task == task_name,
                    BackgroundTaskRun.status.in_(TASK_TERMINAL_STATUSES),
                )
                .order_by(BackgroundTaskRun.started_at.desc(), BackgroundTaskRun.run_id.desc())
                .offset(_MAX_RECENT_RUNS)
            )
            if task_name == "favorites_sync":
                stale_run_ids = stale_run_ids.where(
                    ~BackgroundTaskRun.run_id.in_(select(latest_favorites_runs().c.run_id))
                )
            await db.execute(
                delete(BackgroundTaskRun).where(
                    BackgroundTaskRun.run_id.in_(stale_run_ids),
                    BackgroundTaskRun.run_id != run_id,
                    ~BackgroundTaskRun.run_id.in_(
                        select(NotificationMessage.source_id).where(
                            NotificationMessage.source_type == "background_task_run",
                            NotificationMessage.source_id.is_not(None),
                        )
                    ),
                )
            )
        saved = await db.get(BackgroundTaskRun, run_id)
    if saved is None:
        raise RuntimeError(f"Background task run was not persisted: {run_id}")
    if saved.task != task_name:
        raise RuntimeError(
            f"Background task run id belongs to another task: {run_id}"
        )
    serialized = _serialize_run(saved)
    if write_result.rowcount:
        await _publish_diagnostics_update(
            task_name, saved.status, run_id=run_id,
            content_id=serialized.get("content_id"),
        )
        if terminal:
            await _record_run_notification(serialized)
    return serialized


def _serialize_run(row: BackgroundTaskRun) -> dict[str, Any]:
    metadata = row.run_metadata if isinstance(row.run_metadata, dict) else {}
    payload = dict(metadata)
    payload.update(
        {
            "run_id": row.run_id,
            "task": row.task,
            "status": row.status,
            "started_at": _UTC_DATETIME.dump_python(row.started_at, mode="json"),
            "finished_at": _UTC_DATETIME.dump_python(row.finished_at, mode="json"),
            "error": row.error,
            "result": row.result,
        }
    )
    payload["presentation"] = build_task_run_presentation(
        {
            **payload,
            "metadata": metadata,
        }
    )
    return payload


async def _publish_diagnostics_update(
    task_name: str,
    status: str,
    *,
    run_id: str | None = None,
    content_id: int | None = None,
) -> None:
    payload = {"task": task_name, "status": status}
    if run_id:
        payload["run_id"] = run_id
    if content_id is not None:
        payload["content_id"] = content_id
    try:
        await event_bus.publish("background_task_updated", payload)
    except Exception as error:
        logger.bind(component="background_task_state", task=task_name).warning(
            "后台任务状态事件发布失败: {}",
            error,
        )


async def _record_run_notification(run: dict[str, Any]) -> None:
    try:
        from app.services.notification_inbox import record_task_run_notification

        await record_task_run_notification(run)
    except Exception as error:
        logger.bind(
            component="background_task_state",
            task=run.get("task"),
            run_id=run.get("run_id"),
        ).warning("任务通知写入失败，不影响运行账本结算: {}", error)
