from __future__ import annotations

from datetime import timedelta

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
)
from app.services.embedding_service import SemanticSearchHit


@pytest.mark.asyncio
async def test_agent_list_tools(client: AsyncClient):
    resp = await client.get("/api/v1/agent/tools")
    assert resp.status_code == 200
    names = {item["name"] for item in resp.json()}
    assert {
        "search_content",
        "list_groups",
        "import_favorites",
        "create_rule",
        "manage_tags",
        "get_stats",
        "push_batch",
    }.issubset(names)


@pytest.mark.asyncio
async def test_agent_invoke_unknown_tool(client: AsyncClient):
    resp = await client.post("/api/v1/agent/tools/not-exists/invoke", json={"args": {}})
    assert resp.status_code == 404


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
    assert data["ok"] is True
    assert data["result"]["platform"] == "zhihu"
    assert data["result"]["result"]["imported"] == 3


@pytest.mark.asyncio
async def test_agent_run_uses_list_groups_tool(client: AsyncClient, db_session):
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
            }
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
        json={"args": {"content_id": content.id, "add_tags": ["new", "rust"]}},
    )
    assert add_resp.status_code == 200
    add_data = add_resp.json()
    assert add_data["ok"] is True
    assert "new" in add_data["result"]["tags"]

    remove_resp = await client.post(
        "/api/v1/agent/tools/manage_tags/invoke",
        json={"args": {"content_id": content.id, "remove_tags": ["old"]}},
    )
    assert remove_resp.status_code == 200
    remove_data = remove_resp.json()
    assert remove_data["ok"] is True
    assert "old" not in remove_data["result"]["tags"]


@pytest.mark.asyncio
async def test_agent_invoke_manage_tags_not_found(client: AsyncClient):
    resp = await client.post(
        "/api/v1/agent/tools/manage_tags/invoke",
        json={"args": {"content_id": 999999, "add_tags": ["x"]}},
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
        json={"args": {"content_ids": [content.id], "bot_chat_id": chat.id}},
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
async def test_agent_run_import_favorites_end_to_end(client: AsyncClient, monkeypatch):
    async def _fake_sync(self, platform: str):
        return {"platform": platform, "status": "success", "imported": 2}

    monkeypatch.setattr(
        "app.services.agent.tools.favorites.FavoritesSyncTask.sync_platform_by_name",
        _fake_sync,
    )

    resp = await client.post("/api/v1/agent/run", json={"message": "请同步知乎收藏"})
    assert resp.status_code == 200
    data = resp.json()
    assert data["tool"] == "import_favorites"
    assert data["result"]["result"]["imported"] == 2


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
            assert {"start", "tool_call", "delta", "final"}.issubset(types)


def test_agent_ws_stream_tool_unknown():
    with TestClient(app) as sync_client:
        with sync_client.websocket_connect(
            "/api/v1/agent/ws",
            headers=_ws_headers(),
        ) as ws:
            ws.send_json({"tool": "not_exists_tool", "args": {}})
            first = ws.receive_json()
            second = ws.receive_json()
            assert first.get("type") == "start"
            assert second.get("type") == "error"
            assert "Unknown tool" in str(second.get("error"))


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
