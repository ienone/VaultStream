from __future__ import annotations

from uuid import uuid4
from typing import Any

from sqlalchemy import select

from app.core.db_adapter import AsyncSessionLocal
from app.core.time_utils import utcnow
from app.models import SystemSetting
from app.services.settings_service import get_setting_value_fresh, set_setting_value

_PREFIX = "background_task_state:"
_RUNS_PREFIX = "background_task_runs:"
_CATEGORY = "background_tasks"
_MAX_RECENT_RUNS = 20


def _setting_key(task_name: str) -> str:
    return f"{_PREFIX}{task_name}"


def _runs_key(task_name: str) -> str:
    return f"{_RUNS_PREFIX}{task_name}"


def _now_iso() -> str:
    return utcnow().isoformat()


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
    return await _save_state(task_name, state)


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
    return await _save_state(task_name, state)


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
    await _upsert_run(task_name, run)
    return run


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
    await _upsert_run(task_name, run)
    return run


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
    await _upsert_run(task_name, run)
    return run


async def get_recent_task_runs(task_name: str, limit: int = _MAX_RECENT_RUNS) -> list[dict[str, Any]]:
    runs = await _load_runs(task_name)
    return runs[: max(0, limit)]


async def _load_state(task_name: str) -> dict[str, Any]:
    state = await get_setting_value_fresh(_setting_key(task_name), {})
    return dict(state) if isinstance(state, dict) else {}


async def _save_state(task_name: str, state: dict[str, Any]) -> dict[str, Any]:
    await set_setting_value(
        _setting_key(task_name),
        state,
        category=_CATEGORY,
        description=f"Runtime state for background task {task_name}",
    )
    return state


async def _load_runs(task_name: str) -> list[dict[str, Any]]:
    runs = await get_setting_value_fresh(_runs_key(task_name), [])
    if not isinstance(runs, list):
        return []
    return [dict(run) for run in runs if isinstance(run, dict)]


async def _load_run(task_name: str, run_id: str) -> dict[str, Any]:
    for run in await _load_runs(task_name):
        if run.get("run_id") == run_id:
            return run
    return {"run_id": run_id, "task": task_name}


async def _upsert_run(task_name: str, run: dict[str, Any]) -> None:
    runs = await _load_runs(task_name)
    filtered = [item for item in runs if item.get("run_id") != run.get("run_id")]
    next_runs = [run, *filtered][:_MAX_RECENT_RUNS]
    await set_setting_value(
        _runs_key(task_name),
        next_runs,
        category=_CATEGORY,
        description=f"Recent runtime records for background task {task_name}",
    )
