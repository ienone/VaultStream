import asyncio
import time

import pytest

from app.services.background_task_state import get_recent_task_runs
from app.services.post_ingest import PostIngestService


@pytest.mark.asyncio
async def test_schedule_embedding_index_records_content_embedding_run(monkeypatch, client):
    async def fake_index_content(self, content_id: int, *, session=None):
        return True

    monkeypatch.setattr(
        "app.services.embedding_service.EmbeddingService.index_content",
        fake_index_content,
    )

    PostIngestService().schedule_embedding_index(123, source="unit-test")

    deadline = time.monotonic() + 2
    while time.monotonic() < deadline:
        runs = await get_recent_task_runs("content_embedding")
        if runs and runs[0]["content_id"] == 123 and runs[0]["status"] == "success":
            break
        await asyncio.sleep(0.01)

    runs = await get_recent_task_runs("content_embedding")
    latest = runs[0]
    assert latest["task"] == "content_embedding"
    assert latest["status"] == "success"
    assert latest["content_id"] == 123
    assert latest["source"] == "unit-test"
    assert latest["trigger"] == "auto"
    assert latest["result"]["indexed"] is True

    diagnostics = await client.get("/api/v1/background-tasks/diagnostics")
    assert diagnostics.status_code == 200
    diagnostic_run = next(
        run
        for run in diagnostics.json()["recent_task_runs"]
        if run["run_id"] == latest["run_id"]
    )
    assert diagnostic_run["task"] == "content_embedding"
    assert diagnostic_run["status"] == "success"
