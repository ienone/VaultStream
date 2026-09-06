from __future__ import annotations

from datetime import datetime, timezone
from uuid import uuid4
from typing import Any

from pydantic import TypeAdapter
from app.schemas.base import OptionalUtcDatetime

from sqlalchemy import and_, delete, select
from sqlalchemy.dialects.sqlite import insert as sqlite_insert

from app.core.db_adapter import AsyncSessionLocal
from app.core.events import event_bus
from app.core.logging import logger
from app.core.time_utils import utcnow
from app.models import BackgroundTaskRun, NotificationMessage, SystemSetting
from app.services.config_service import ConfigService
from app.services.task_run_presentation import build_task_run_presentation, TASK_TERMINAL_STATUSES

_UTC_DATETIME = TypeAdapter(OptionalUtcDatetime)
_PREFIX = "background_task_state:"
_CATEGORY = "background_tasks"
_MAX_RECENT_RUNS = 200


def _setting_key(task_name: str) -> str:
    return f"{_PREFIX}{task_name}"


def _now_iso() -> str:
    return utcnow().isoformat()


def _config_service() -> ConfigService:
    return ConfigService()


async def record_task_started(task_name: str, **metrics: Any) -> dict[str, Any]:
    state = await _load_state(task_name)
    state.update(
        {
            "task": task_name,
            "status": "running",
            "last_started_at": _now_iso(),
            **metrics,
        }
    )
    return await _save_state(task_name, state)


async def record_task_success(task_name: str, **metrics: Any) -> dict[str, Any]:
    state = await _load_state(task_name)
    state.update(
        {
            "task": task_name,
            "status": "ok",
            "last_success_at": _now_iso(),
            "last_error": None,
            **metrics,
        }
    )
    state["run_count"] = int(state.get("run_count") or 0) + 1
    saved = await _save_state(task_name, state)
    await _publish_diagnostics_update(task_name, "ok")
    return saved


async def record_task_error(task_name: str, error: BaseException | str, **metrics: Any) -> dict[str, Any]:
    state = await _load_state(task_name)
    state.update(
        {
            "task": task_name,
            "status": "error",
            "last_error_at": _now_iso(),
            "last_error": str(error)[:1000],
            **metrics,
        }
    )
    state["error_count"] = int(state.get("error_count") or 0) + 1
    saved = await _save_state(task_name, state)
    await _publish_diagnostics_update(task_name, "error")
    return saved


async def get_background_task_states() -> dict[str, dict[str, Any]]:
    async with AsyncSessionLocal() as db:
        rows = (
            await db.execute(
                select(SystemSetting.key, SystemSetting.value)
                .where(SystemSetting.category == _CATEGORY)
                .where(SystemSetting.key.like(f"{_PREFIX}%"))
            )
        ).all()

    states: dict[str, dict[str, Any]] = {}
    for key, value in rows:
        task_name = key[len(_PREFIX) :]
        if isinstance(value, dict):
            states[task_name] = value
        else:
            states[task_name] = {"task": task_name, "status": "unknown", "raw": value}
    return states


async def record_task_run_started(
    task_name: str,
    *,
    run_id: str | None = None,
    **metadata: Any,
) -> dict[str, Any]:
    run = {
        "run_id": run_id or uuid4().hex,
        "task": task_name,
        "status": "running",
        "started_at": _now_iso(),
        "finished_at": None,
        "error": None,
        **metadata,
    }
    saved, _ = await _upsert_run(task_name, run, terminal=False)
    return saved


async def record_task_run_success(
    task_name: str,
    run_id: str,
    **result: Any,
) -> dict[str, Any]:
    run = await _load_run(task_name, run_id)
    run.update(
        {
            "run_id": run_id,
            "task": task_name,
            "status": "success",
            "finished_at": _now_iso(),
            "error": None,
            "result": result,
        }
    )
    saved, transition_applied = await _upsert_run(task_name, run, terminal=True)
    await _publish_diagnostics_update(
        task_name,
        str(saved["status"]),
        run_id=run_id,
    )
    if transition_applied:
        await _record_run_notification(saved)
    return saved


async def record_task_run_error(
    task_name: str,
    run_id: str,
    error: BaseException | str,
    **result: Any,
) -> dict[str, Any]:
    run = await _load_run(task_name, run_id)
    run.update(
        {
            "run_id": run_id,
            "task": task_name,
            "status": "error",
            "finished_at": _now_iso(),
            "error": str(error)[:1000],
            "result": result,
        }
    )
    saved, transition_applied = await _upsert_run(task_name, run, terminal=True)
    await _publish_diagnostics_update(
        task_name,
        str(saved["status"]),
        run_id=run_id,
    )
    if transition_applied:
        await _record_run_notification(saved)
    return saved


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


async def _load_state(task_name: str) -> dict[str, Any]:
    state = await _config_service().get_value_fresh(_setting_key(task_name), {})
    return dict(state) if isinstance(state, dict) else {}


async def _save_state(task_name: str, state: dict[str, Any]) -> dict[str, Any]:
    await _config_service().set_value(
        _setting_key(task_name),
        state,
        category=_CATEGORY,
        description=f"Runtime state for background task {task_name}",
    )
    return state


async def _load_run(task_name: str, run_id: str) -> dict[str, Any]:
    run = await get_task_run(run_id)
    if run is not None and run.get("task") == task_name:
        return run
    return {"run_id": run_id, "task": task_name}


async def _upsert_run(
    task_name: str,
    run: dict[str, Any],
    *,
    terminal: bool,
) -> tuple[dict[str, Any], bool]:
    run_id = str(run["run_id"])
    started_at = _parse_run_datetime(run.get("started_at")) or utcnow()
    finished_at = _parse_run_datetime(run.get("finished_at"))
    known = {
        "run_id",
        "task",
        "status",
        "started_at",
        "finished_at",
        "error",
        "result",
        "presentation",
    }
    metadata = {key: value for key, value in run.items() if key not in known}
    values = {
        "run_id": run_id,
        "task": task_name,
        "status": str(run.get("status") or "unknown"),
        "started_at": started_at,
        "finished_at": finished_at,
        "error": run.get("error"),
        "run_metadata": metadata,
        "result": run.get("result"),
        "created_at": started_at,
        "updated_at": finished_at or utcnow(),
    }
    insert_statement = sqlite_insert(BackgroundTaskRun).values(**values)
    if terminal:
        statement = insert_statement.on_conflict_do_update(
            index_elements=[BackgroundTaskRun.run_id],
            set_={
                "status": values["status"],
                "finished_at": values["finished_at"],
                "error": values["error"],
                "metadata": values["run_metadata"],
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
    return _serialize_run(saved), bool(write_result.rowcount)


def _parse_run_datetime(value: Any) -> datetime | None:
    if isinstance(value, datetime):
        parsed = value
    elif isinstance(value, str) and value.strip():
        try:
            parsed = datetime.fromisoformat(value.strip().replace("Z", "+00:00"))
        except ValueError:
            return None
    else:
        return None
    if parsed.tzinfo is not None:
        return parsed.astimezone(timezone.utc).replace(tzinfo=None)
    return parsed


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
) -> None:
    payload = {"task": task_name, "status": status}
    if run_id:
        payload["run_id"] = run_id
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
