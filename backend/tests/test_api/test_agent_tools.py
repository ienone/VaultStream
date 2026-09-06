import pytest
from httpx import AsyncClient


async def _invoke_and_decide(
    client: AsyncClient,
    tool_name: str,
    args: dict,
    *,
    approved: bool = True,
):
    pending = await client.post(
        f"/api/v1/agent/tools/{tool_name}/invoke",
        json={"args": args},
    )
    assert pending.status_code == 200
    payload = pending.json()
    assert payload["confirmation_required"] is True
    return await client.post(
        f"/api/v1/agent/confirmations/{payload['confirmation']['id']}/decide",
        json={"approved": approved},
    )


@pytest.mark.asyncio
async def test_agent_tool_cannot_self_assert_confirmation(client: AsyncClient):
    response = await client.post(
        "/api/v1/agent/tools/import_favorites/invoke",
        json={"args": {"platform": "zhihu"}, "confirmed": True},
    )
    assert response.status_code == 422


@pytest.mark.asyncio
@pytest.mark.parametrize("operation", ["stop", "clear", "delete"])
async def test_agent_confirmation_is_cancelled_with_owning_context(
    client: AsyncClient,
    monkeypatch,
    operation: str,
):
    executed = False

    async def _fake_sync(self, platform: str):
        nonlocal executed
        executed = True
        return {"platform": platform, "status": "success"}

    monkeypatch.setattr(
        "app.services.agent.tools.favorites.FavoritesSyncTask.sync_platform_by_name",
        _fake_sync,
    )
    pending = await client.post(
        "/api/v1/agent/tools/import_favorites/invoke",
        json={"args": {"platform": "zhihu"}},
    )
    payload = pending.json()
    confirmation = payload["confirmation"]

    if operation == "stop":
        response = await client.post(
            f"/api/v1/agent/runs/{confirmation['run_id']}/stop"
        )
    elif operation == "clear":
        response = await client.post(
            f"/api/v1/agent/sessions/{confirmation['session_id']}/clear"
        )
    else:
        response = await client.delete(
            f"/api/v1/agent/sessions/{confirmation['session_id']}"
        )
    assert response.status_code == 200

    detail = await client.get(
        f"/api/v1/agent/confirmations/{confirmation['id']}"
    )
    assert detail.status_code == 200
    assert detail.json()["status"] == "cancelled"

    decision = await client.post(
        f"/api/v1/agent/confirmations/{confirmation['id']}/decide",
        json={"approved": True},
    )
    assert decision.status_code == 404
    assert decision.json()["error_code"] == "agent_confirmation_not_found"
    assert executed is False

    inbox = await client.get(
        "/api/v1/notifications",
        params={"category": "agent", "state": "all"},
    )
    notice = next(
        item
        for item in inbox.json()["items"]
        if item["source_id"] == confirmation["id"]
    )
    assert notice["payload"]["status"] == "cancelled"
    assert notice["dismissed_at"] is not None
