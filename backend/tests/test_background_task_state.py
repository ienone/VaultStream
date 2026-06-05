import pytest

from app.services.background_task_state import (
    get_background_task_states,
    get_recent_task_runs,
    record_task_run_error,
    record_task_run_started,
    record_task_run_success,
    record_task_error,
    record_task_started,
    record_task_success,
)


@pytest.mark.asyncio
async def test_background_task_state_records_lifecycle(db_session):
    await record_task_started("unit_test_worker", worker="test")
    await record_task_success("unit_test_worker", processed=2)
    await record_task_error("unit_test_worker", RuntimeError("boom"), failed=1)

    states = await get_background_task_states()
    state = states["unit_test_worker"]

    assert state["task"] == "unit_test_worker"
    assert state["status"] == "error"
    assert state["last_started_at"]
    assert state["last_success_at"]
    assert state["last_error_at"]
    assert state["last_error"] == "boom"
    assert state["run_count"] == 1
    assert state["error_count"] == 1
    assert state["processed"] == 2
    assert state["failed"] == 1


@pytest.mark.asyncio
async def test_background_task_run_records_lifecycle(db_session):
    started = await record_task_run_started("unit_test_runs", scope="zhihu", trigger="manual")
    run_id = started["run_id"]

    await record_task_run_success("unit_test_runs", run_id, imported=2)
    await record_task_run_started("unit_test_runs", run_id="failed-run", scope="twitter")
    await record_task_run_error("unit_test_runs", "failed-run", RuntimeError("boom"), failed=1)

    runs = await get_recent_task_runs("unit_test_runs")

    assert runs[0]["run_id"] == "failed-run"
    assert runs[0]["status"] == "error"
    assert runs[0]["error"] == "boom"
    assert runs[1]["run_id"] == run_id
    assert runs[1]["status"] == "success"
    assert runs[1]["result"]["imported"] == 2
