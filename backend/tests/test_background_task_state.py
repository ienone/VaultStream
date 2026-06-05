import pytest

from app.services import background_task_state as state


class _FakeConfigService:
    def __init__(self) -> None:
        self.values: dict[str, object] = {}
        self.set_calls: list[dict[str, object]] = []

    async def get_value_fresh(self, key: str, default=None):
        return self.values.get(key, default)

    async def set_value(self, key: str, value, *, category: str = "general", description=None):
        self.values[key] = value
        self.set_calls.append(
            {
                "key": key,
                "value": value,
                "category": category,
                "description": description,
            }
        )


@pytest.mark.asyncio
async def test_background_task_state_uses_config_service(monkeypatch):
    config = _FakeConfigService()
    monkeypatch.setattr(state, "_config_service", lambda: config)

    saved = await state.record_task_success("demo_task", indexed=True)

    key = "background_task_state:demo_task"
    assert config.values[key] == saved
    assert saved["task"] == "demo_task"
    assert saved["status"] == "ok"
    assert saved["run_count"] == 1
    assert saved["indexed"] is True
    assert config.set_calls[-1]["category"] == "background_tasks"


@pytest.mark.asyncio
async def test_recent_task_runs_use_config_service(monkeypatch):
    config = _FakeConfigService()
    monkeypatch.setattr(state, "_config_service", lambda: config)

    started = await state.record_task_run_started(
        "demo_runs",
        run_id="run-1",
        trigger="manual",
    )
    finished = await state.record_task_run_success(
        "demo_runs",
        "run-1",
        indexed=2,
    )
    runs = await state.get_recent_task_runs("demo_runs")

    key = "background_task_runs:demo_runs"
    assert runs == [finished]
    assert config.values[key] == [finished]
    assert started["trigger"] == "manual"
    assert finished["status"] == "success"
    assert finished["result"] == {"indexed": 2}
