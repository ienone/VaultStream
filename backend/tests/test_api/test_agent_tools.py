from __future__ import annotations

from datetime import timedelta
import uuid

import pytest
from fastapi.testclient import TestClient
from httpx import AsyncClient
from pydantic import SecretStr
from sqlalchemy import select
from starlette.websockets import WebSocketDisconnect

from app.core.config import settings
from app.core.time_utils import utcnow
from app.main import app
from app.models import (
    BotChat,
    BotChatType,
    BotConfig,
    BotConfigPlatform,
    Content,
    ContentQueueItem,
    ContentStatus,
    DistributionRule,
    DistributionTarget,
    Platform,
    QueueItemStatus,
    ReviewStatus,
    AgentMessage,
    AgentRun,
)
from app.services.agent import AgentRunResult, AgentService
from app.services.embedding_service import SemanticSearchHit


@pytest.mark.asyncio
async def test_agent_list_tools(client: AsyncClient):
    resp = await client.get("/api/v1/agent/tools")
    assert resp.status_code == 200
    names = {item["name"] for item in resp.json()}
    assert {
        "api_catalog",
        "api_get",
        "api_mutation",
        "search_content",
        "list_groups",
        "import_favorites",
        "create_rule",
        "manage_tags",
        "get_stats",
        "push_batch",
    }.issubset(names)
    for item in resp.json():
        assert item["result_schema"]["type"] == "object"
        assert item["permission_level"] in {"read", "write", "external_side_effect", "dangerous"}


@pytest.mark.asyncio
async def test_agent_invoke_unknown_tool(client: AsyncClient):
    resp = await client.post("/api/v1/agent/tools/not-exists/invoke", json={"args": {}})
    assert resp.status_code == 404
    assert resp.json()["error_code"] == "agent_tool_not_found"


@pytest.mark.asyncio
async def test_agent_invoke_search_content(client: AsyncClient, db_session, monkeypatch):
    content = Content(
        platform=Platform.BILIBILI,
        url="https://www.bilibili.com/video/BV-agent-search",
        canonical_url="agent://search/1",
        status=ContentStatus.PARSE_SUCCESS,
        review_status=ReviewStatus.APPROVED,
        title="Rust Agent 检索",
        body="语义搜索测试内容",
        created_at=utcnow(),
    )
    db_session.add(content)
    await db_session.commit()
    await db_session.refresh(content)

    async def _fake_search(self, **kwargs):
        return [SemanticSearchHit(content=content, score=0.93, match_source="hybrid")]

    monkeypatch.setattr(
        "app.services.agent.tools.search.EmbeddingService.search",
        _fake_search,
    )

    resp = await client.post(
        "/api/v1/agent/tools/search_content/invoke",
        json={"args": {"query": "Rust"}},
    )
    assert resp.status_code == 200
    data = resp.json()
    assert data["ok"] is True
    assert data["tool"] == "search_content"
    assert data["result"]["count"] == 1
    assert data["result"]["items"][0]["content_id"] == content.id


@pytest.mark.asyncio
async def test_agent_invoke_list_groups(client: AsyncClient, db_session):
    cfg = BotConfig(platform=BotConfigPlatform.TELEGRAM, name="agent-test")
    db_session.add(cfg)
    await db_session.flush()
    chat = BotChat(
        bot_config_id=cfg.id,
        chat_id="-100agentgroup",
        chat_type=BotChatType.SUPERGROUP,
        title="Agent Group",
        enabled=True,
        is_accessible=True,
    )
    db_session.add(chat)
    await db_session.commit()

    resp = await client.post("/api/v1/agent/tools/list_groups/invoke", json={"args": {}})
    assert resp.status_code == 200
    data = resp.json()
    assert data["ok"] is True
    assert any(group["chat_id"] == "-100agentgroup" for group in data["result"]["groups"])


@pytest.mark.asyncio
async def test_agent_invoke_import_favorites_validation(client: AsyncClient):
    resp = await client.post("/api/v1/agent/tools/import_favorites/invoke", json={"args": {}})
    assert resp.status_code == 400


@pytest.mark.asyncio
async def test_agent_invoke_import_favorites_success(client: AsyncClient, monkeypatch):
    async def _fake_sync(self, platform: str):
        return {"platform": platform, "status": "success", "imported": 3}

    monkeypatch.setattr(
        "app.services.agent.tools.favorites.FavoritesSyncTask.sync_platform_by_name",
        _fake_sync,
    )

    resp = await client.post(
        "/api/v1/agent/tools/import_favorites/invoke",
        json={"args": {"platform": "zhihu"}},
    )
    assert resp.status_code == 200
    data = resp.json()
    assert data["ok"] is False
    assert data["confirmation_required"] is True
    confirmation_id = data["confirmation"]["id"]

    detail = await client.get(f"/api/v1/agent/confirmations/{confirmation_id}")
    assert detail.status_code == 200
    assert detail.json()["status"] == "pending"

    decided = await client.post(
        f"/api/v1/agent/confirmations/{confirmation_id}/decide",
        json={"approved": True},
    )
    assert decided.status_code == 200
    decided_data = decided.json()
    assert decided_data["status"] == "completed"
    assert decided_data["result"]["platform"] == "zhihu"
    assert decided_data["result"]["result"]["imported"] == 3


@pytest.mark.asyncio
async def test_agent_run_uses_list_groups_tool(client: AsyncClient, db_session, monkeypatch):
    cfg = BotConfig(platform=BotConfigPlatform.TELEGRAM, name="agent-run-test")
    db_session.add(cfg)
    await db_session.flush()
    db_session.add(
        BotChat(
            bot_config_id=cfg.id,
            chat_id="-100agentrun",
            chat_type=BotChatType.SUPERGROUP,
            title="Agent Run Group",
            enabled=True,
            is_accessible=True,
        )
    )
    await db_session.commit()

    async def _fake_run(self, *, message: str, session_id: str | None = None):
        return AgentRunResult(
            session_id=session_id or "sess_test",
            run_id="run_test",
            status="completed",
            tool="list_groups",
            result={"groups": [{"chat_id": "-100agentrun"}]},
            message="ok",
            events=[{"type": "start"}, {"type": "final", "status": "completed"}],
        )

    monkeypatch.setattr("app.routers.agent.AgentService.run_message", _fake_run)

    resp = await client.post("/api/v1/agent/run", json={"message": "请列出可用群组"})
    assert resp.status_code == 200
    data = resp.json()
    assert data["tool"] == "list_groups"
    assert "groups" in data["result"]


@pytest.mark.asyncio
async def test_agent_run_rejects_blank_message(client: AsyncClient):
    resp = await client.post("/api/v1/agent/run", json={"message": "   "})
    assert resp.status_code == 400
    assert "message is required" in str(resp.json())


@pytest.mark.asyncio
async def test_agent_invoke_create_rule(client: AsyncClient, db_session):
    cfg = BotConfig(platform=BotConfigPlatform.TELEGRAM, name="agent-create-rule")
    db_session.add(cfg)
    await db_session.flush()

    chat = BotChat(
        bot_config_id=cfg.id,
        chat_id="-100ruletarget",
        chat_type=BotChatType.SUPERGROUP,
        title="Rule Target",
        enabled=True,
        is_accessible=True,
    )
    db_session.add(chat)
    await db_session.commit()

    resp = await client.post(
        "/api/v1/agent/tools/create_rule/invoke",
        json={
            "args": {
                "name": f"agent-rule-{int(utcnow().timestamp())}",
                "platform": "bilibili",
                "tags": ["Rust", "Async"],
                "target_bot_chat_id": chat.id,
            },
            "confirmed": True,
        },
    )
    assert resp.status_code == 200
    data = resp.json()
    assert data["ok"] is True
    assert data["result"]["rule_id"] > 0
    assert data["result"]["target"]["bot_chat_id"] == chat.id


@pytest.mark.asyncio
async def test_agent_invoke_manage_tags(client: AsyncClient, db_session):
    content = Content(
        platform=Platform.ZHIHU,
        url="https://www.zhihu.com/question/42/answer/7",
        canonical_url=f"agent://tags/{int(utcnow().timestamp())}",
        status=ContentStatus.PARSE_SUCCESS,
        review_status=ReviewStatus.APPROVED,
        title="Tag Tool",
        tags=["old"],
        created_at=utcnow(),
    )
    db_session.add(content)
    await db_session.commit()

    add_resp = await client.post(
        "/api/v1/agent/tools/manage_tags/invoke",
        json={"args": {"content_id": content.id, "add_tags": ["new", "rust"]}, "confirmed": True},
    )
    assert add_resp.status_code == 200
    add_data = add_resp.json()
    assert add_data["ok"] is True
    assert "new" in add_data["result"]["tags"]

    remove_resp = await client.post(
        "/api/v1/agent/tools/manage_tags/invoke",
        json={"args": {"content_id": content.id, "remove_tags": ["old"]}, "confirmed": True},
    )
    assert remove_resp.status_code == 200
    remove_data = remove_resp.json()
    assert remove_data["ok"] is True
    assert "old" not in remove_data["result"]["tags"]


@pytest.mark.asyncio
async def test_agent_invoke_manage_tags_not_found(client: AsyncClient):
    resp = await client.post(
        "/api/v1/agent/tools/manage_tags/invoke",
        json={"args": {"content_id": 999999, "add_tags": ["x"]}, "confirmed": True},
    )
    assert resp.status_code == 400


@pytest.mark.asyncio
async def test_agent_invoke_get_stats(client: AsyncClient):
    resp = await client.post(
        "/api/v1/agent/tools/get_stats/invoke",
        json={"args": {"include_rule_breakdown": True}},
    )
    assert resp.status_code == 200
    data = resp.json()
    assert data["ok"] is True
    assert "parse" in data["result"]
    assert "distribution" in data["result"]


@pytest.mark.asyncio
async def test_agent_api_catalog_lists_client_api_surface(client: AsyncClient):
    resp = await client.post(
        "/api/v1/agent/tools/api_catalog/invoke",
        json={"args": {"prefix": "/contents", "include_mutations": True}},
    )
    assert resp.status_code == 200
    data = resp.json()
    assert data["ok"] is True
    endpoints = {(item["method"], item["path"]) for item in data["result"]["endpoints"]}
    assert ("GET", "/api/v1/contents") in endpoints
    assert ("PATCH", "/api/v1/contents/{content_id}") in endpoints


@pytest.mark.asyncio
async def test_agent_api_get_reuses_internal_content_api(client: AsyncClient, db_session):
    content = Content(
        platform=Platform.BILIBILI,
        url="https://www.bilibili.com/video/BV-agent-api-get",
        canonical_url=f"agent://api-get/{int(utcnow().timestamp())}",
        status=ContentStatus.PARSE_SUCCESS,
        review_status=ReviewStatus.APPROVED,
        title="Agent API GET",
        body="read through api bridge",
        created_at=utcnow(),
    )
    db_session.add(content)
    await db_session.commit()
    await db_session.refresh(content)

    resp = await client.post(
        "/api/v1/agent/tools/api_get/invoke",
        json={"args": {"path": f"/contents/{content.id}"}},
    )
    assert resp.status_code == 200
    data = resp.json()
    assert data["ok"] is True
    assert data["result"]["status_code"] == 200
    assert data["result"]["data"]["id"] == content.id
    assert data["result"]["data"]["title"] == "Agent API GET"


@pytest.mark.asyncio
async def test_agent_api_mutation_requires_confirmation(client: AsyncClient):
    resp = await client.post(
        "/api/v1/agent/tools/api_mutation/invoke",
        json={
            "args": {
                "method": "PATCH",
                "path": "/contents/1",
                "body": {"title": "blocked"},
                "reason": "测试 mutation confirmation",
            }
        },
    )
    assert resp.status_code == 200
    data = resp.json()
    assert data["ok"] is False
    assert data["confirmation_required"] is True
    assert data["confirmation"]["tool_name"] == "api_mutation"


@pytest.mark.asyncio
async def test_agent_api_mutation_reuses_internal_content_update_api(client: AsyncClient, db_session):
    content = Content(
        platform=Platform.ZHIHU,
        url="https://www.zhihu.com/question/1/answer/agent-api-mutation",
        canonical_url=f"agent://api-mutation/{int(utcnow().timestamp())}",
        status=ContentStatus.PARSE_SUCCESS,
        review_status=ReviewStatus.PENDING,
        title="Before API Mutation",
        body="write through api bridge",
        created_at=utcnow(),
    )
    db_session.add(content)
    await db_session.commit()
    await db_session.refresh(content)

    resp = await client.post(
        "/api/v1/agent/tools/api_mutation/invoke",
        json={
            "confirmed": True,
            "args": {
                "method": "PATCH",
                "path": f"/contents/{content.id}",
                "body": {
                    "title": "After API Mutation",
                    "review_status": "approved",
                    "review_note": "agent api bridge",
                },
                "reason": "通过 Agent 调用内容编辑 API",
            },
        },
    )
    assert resp.status_code == 200
    data = resp.json()
    assert data["ok"] is True
    assert data["result"]["status_code"] == 200
    assert data["result"]["data"]["title"] == "After API Mutation"
    assert data["result"]["data"]["review_status"] == "approved"


@pytest.mark.asyncio
async def test_agent_invoke_push_batch(client: AsyncClient, db_session):
    cfg = BotConfig(platform=BotConfigPlatform.TELEGRAM, name="agent-push-tool")
    db_session.add(cfg)
    await db_session.flush()
    chat = BotChat(
        bot_config_id=cfg.id,
        chat_id="-100pushbatch",
        chat_type=BotChatType.SUPERGROUP,
        title="Push Batch",
        enabled=True,
        is_accessible=True,
    )
    db_session.add(chat)
    await db_session.flush()

    rule = DistributionRule(
        name=f"push-batch-rule-{int(utcnow().timestamp())}",
        description="for push batch tool test",
        match_conditions={},
        enabled=True,
        approval_required=False,
    )
    db_session.add(rule)
    await db_session.flush()

    db_session.add(
        DistributionTarget(
            rule_id=rule.id,
            bot_chat_id=chat.id,
            enabled=True,
            backfill_watermark=utcnow() - timedelta(days=1),
        )
    )

    content = Content(
        platform=Platform.BILIBILI,
        url="https://www.bilibili.com/video/BV-agent-push",
        canonical_url=f"agent://push/{int(utcnow().timestamp())}",
        status=ContentStatus.PARSE_SUCCESS,
        review_status=ReviewStatus.APPROVED,
        title="Push Batch Content",
        body="should be queued",
        created_at=utcnow(),
    )
    db_session.add(content)
    await db_session.commit()

    resp = await client.post(
        "/api/v1/agent/tools/push_batch/invoke",
        json={"args": {"content_ids": [content.id], "bot_chat_id": chat.id}, "confirmed": True},
    )
    assert resp.status_code == 200
    data = resp.json()
    assert data["ok"] is True
    assert data["result"]["scheduled_count"] >= 1

    queue_item = (
        await db_session.execute(
            select(ContentQueueItem).where(ContentQueueItem.content_id == content.id)
        )
    ).scalar_one_or_none()
    assert queue_item is not None
    assert queue_item.status == QueueItemStatus.SCHEDULED


@pytest.mark.asyncio
async def test_agent_session_messages_stop_redo_and_clear(client: AsyncClient, monkeypatch):
    async def _fake_run(self, *, message: str, session_id: str | None = None):
        session = await self.ensure_session(session_id, title="session api")
        run = AgentRun(
            id=f"run_session_api_{uuid.uuid4().hex}",
            session_id=session.id,
            status="completed",
            input_message=message,
            output_message="done",
        )
        self.db.add(run)
        self.db.add(AgentMessage(session_id=session.id, run_id=run.id, role="user", content=message))
        self.db.add(AgentMessage(session_id=session.id, run_id=run.id, role="assistant", content="done"))
        await self.db.commit()
        return AgentRunResult(session_id=session.id, run_id=run.id, status="completed", message="done")

    monkeypatch.setattr("app.routers.agent.AgentService.run_message", _fake_run)

    created = await client.post("/api/v1/agent/sessions", json={"title": "A"})
    assert created.status_code == 200
    session_id = created.json()["id"]

    renamed = await client.patch(f"/api/v1/agent/sessions/{session_id}", json={"title": "B"})
    assert renamed.status_code == 200
    assert renamed.json()["title"] == "B"

    run = await client.post("/api/v1/agent/run", json={"session_id": session_id, "message": "hello"})
    assert run.status_code == 200
    messages = await client.get(f"/api/v1/agent/sessions/{session_id}/messages")
    assert messages.status_code == 200
    assert len(messages.json()["messages"]) >= 2

    stopped = await client.post(f"/api/v1/agent/runs/{run.json()['run_id']}/stop")
    assert stopped.status_code == 200

    redo = await client.post(f"/api/v1/agent/sessions/{session_id}/redo")
    assert redo.status_code == 200

    cleared = await client.post(f"/api/v1/agent/sessions/{session_id}/clear")
    assert cleared.status_code == 200
    messages_after = await client.get(f"/api/v1/agent/sessions/{session_id}/messages")
    assert messages_after.json()["messages"] == []


@pytest.mark.asyncio
async def test_agent_context_compression_records_summary(db_session):
    service = AgentService(db_session)
    session = await service.ensure_session("ctx-test", title="ctx")
    run = AgentRun(id="run_ctx", session_id=session.id, status="running", input_message="now")
    db_session.add(run)
    for idx in range(18):
        db_session.add(
            AgentMessage(
                session_id=session.id,
                role="user" if idx % 2 == 0 else "assistant",
                content=f"message-{idx} " + ("x" * 2000),
            )
        )
    await db_session.commit()

    events: list[dict] = []
    messages = await service._build_context_messages(session.id, run.id, events)
    assert any(event["type"] == "context_summary" for event in events)
    assert any("历史摘要" in getattr(message, "content", "") for message in messages)


@pytest.mark.asyncio
async def test_agent_run_import_favorites_end_to_end(client: AsyncClient, monkeypatch):
    async def _fake_sync(self, platform: str):
        return {"platform": platform, "status": "success", "imported": 2}

    async def _fake_run(self, *, message: str, session_id: str | None = None):
        return AgentRunResult(
            session_id=session_id or "sess_fav",
            run_id="run_fav",
            status="waiting_confirmation",
            tool="import_favorites",
            confirmation={
                "id": "confirm_fav",
                "tool_name": "import_favorites",
                "permission_level": "external_side_effect",
                "args": {"platform": "zhihu"},
                "summary": "sync zhihu",
            },
            events=[{"type": "confirmation_required"}],
        )

    monkeypatch.setattr("app.routers.agent.AgentService.run_message", _fake_run)

    resp = await client.post("/api/v1/agent/run", json={"message": "请同步知乎收藏"})
    assert resp.status_code == 200
    data = resp.json()
    assert data["status"] == "waiting_confirmation"
    assert data["confirmation_required"] is True
    assert data["confirmation"]["tool_name"] == "import_favorites"


def _ws_headers() -> dict[str, str]:
    token = settings.api_token.get_secret_value() if settings.api_token else ""
    return {"X-API-Token": token} if token else {}


def test_agent_ws_stream_tool_success():
    with TestClient(app) as sync_client:
        with sync_client.websocket_connect(
            "/api/v1/agent/ws",
            headers=_ws_headers(),
        ) as ws:
            ws.send_json({"tool": "list_groups", "args": {}})
            events = []
            for _ in range(8):
                evt = ws.receive_json()
                events.append(evt)
                if evt.get("type") == "final":
                    break

            types = {event.get("type") for event in events}
            assert {"start", "tool_call", "tool_result", "final"}.issubset(types)


def test_agent_ws_stream_tool_unknown():
    with TestClient(app) as sync_client:
        with sync_client.websocket_connect(
            "/api/v1/agent/ws",
            headers=_ws_headers(),
        ) as ws:
            ws.send_json({"tool": "not_exists_tool", "args": {}})
            event = ws.receive_json()
            assert event.get("type") == "error"
            assert event.get("error_code") == "agent_tool_not_found"
            assert "Unknown tool" in str(event.get("message"))


def test_agent_ws_unauthorized(monkeypatch):
    monkeypatch.setattr(settings, "api_token", SecretStr("ws-token-required"))
    with TestClient(app) as sync_client:
        with pytest.raises(WebSocketDisconnect):
            with sync_client.websocket_connect("/api/v1/agent/ws"):
                pass


def test_agent_ws_rejects_query_token(monkeypatch):
    monkeypatch.setattr(settings, "api_token", SecretStr("ws-token-required"))
    with TestClient(app) as sync_client:
        with pytest.raises(WebSocketDisconnect):
            with sync_client.websocket_connect("/api/v1/agent/ws?token=ws-token-required"):
                pass
