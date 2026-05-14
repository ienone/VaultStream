from __future__ import annotations

from typing import Any

from sqlalchemy import select

from app.core.db_adapter import AsyncSessionLocal
from app.core.time_utils import utcnow
from app.models import SystemSetting
from app.services.settings_service import get_setting_value_fresh, set_setting_value

_PREFIX = "background_task_state:"
_CATEGORY = "background_tasks"


def _setting_key(task_name: str) -> str:
    return f"{_PREFIX}{task_name}"


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
