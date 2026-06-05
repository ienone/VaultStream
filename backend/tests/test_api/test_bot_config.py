import pytest
from httpx import AsyncClient
from types import SimpleNamespace
from typing import Dict, Any

class TestBotConfigExtraAPI:
    @pytest.fixture
    async def create_qq_config(self, client: AsyncClient) -> Dict[str, Any]:
        resp = await client.post(
            "/api/v1/bot-config",
            json={
                "platform": "qq",
                "name": "test-qq-bot",
                "napcat_http_url": "http://localhost:3000",
                "napcat_ws_url": "ws://localhost:3001",
                "napcat_access_token": "test_token",
                "enabled": True,
                "is_primary": False,
            },
        )
        assert resp.status_code == 201
        return resp.json()

    @pytest.mark.asyncio
    async def test_get_qr_code(self, client: AsyncClient, create_qq_config):
        config_id = create_qq_config["id"]
        # Since napcat_http_url is a dummy URL, this will fail the HTTP request but won't crash the server.
        resp = await client.get(f"/api/v1/bot-config/{config_id}/qr-code")
        assert resp.status_code == 200
        data = resp.json()
        assert data["status"] in ["error", "pending", "ok"]
        assert "message" in data

    @pytest.mark.asyncio
    async def test_sync_qq_chats(self, client: AsyncClient, create_qq_config):
        # Even with a dummy napcat URL, it should return gracefully handled 400 errors instead of internal crashes
        config_id = create_qq_config["id"]
        resp = await client.post(f"/api/v1/bot-config/{config_id}/sync-chats")
        # According to BotConfig API code, an HTTPError during get_group_list raises HTTPException 400
        assert resp.status_code == 400
        assert "Failed to fetch napcat group list" in resp.json()["detail"]

    @pytest.mark.asyncio
    async def test_telegram_service_commands(self, client: AsyncClient):
        # We can test the endpoints for starting/stopping/restarting
        start_resp = await client.post("/api/v1/bot-config/service/telegram/start")
        assert start_resp.status_code == 200

        stop_resp = await client.post("/api/v1/bot-config/service/telegram/stop")
        assert stop_resp.status_code == 200

        restart_resp = await client.post("/api/v1/bot-config/service/telegram/restart")
        assert restart_resp.status_code == 200
        assert "status" in restart_resp.json()

    @pytest.mark.asyncio
    async def test_targets_test_endpoint(self, client: AsyncClient):
        # Targeting the /targets/test endpoint inside distribution
        resp = await client.post(
            "/api/v1/targets/test",
            json={
                "platform": "telegram",
                "target_id": "dummy_id"
            }
        )
        assert resp.status_code == 200
        assert resp.json()["status"] == "error" # Should fail normally since bot is not actually configured
        assert resp.json()["run_id"]

    @pytest.mark.asyncio
    async def test_targets_test_endpoint_records_success_run(
        self,
        client: AsyncClient,
        monkeypatch,
    ):
        class FakeBot:
            async def get_chat(self, target_id: str):
                return SimpleNamespace(
                    title="Push Channel",
                    type="channel",
                    username="push_channel",
                )

        class FakeTelegramPushService:
            async def _get_bot(self):
                return FakeBot()

        monkeypatch.setattr(
            "app.push.telegram.TelegramPushService",
            FakeTelegramPushService,
        )

        resp = await client.post(
            "/api/v1/targets/test",
            json={"platform": "telegram", "target_id": "target-1"},
        )
        assert resp.status_code == 200
        data = resp.json()
        assert data["status"] == "ok"
        assert data["platform"] == "telegram"
        assert data["target_id"] == "target-1"
        assert data["run_id"]
        assert "Push Channel" in data["message"]

        diagnostics = await client.get("/api/v1/background-tasks/diagnostics")
        latest = next(
            run
            for run in diagnostics.json()["recent_task_runs"]
            if run["run_id"] == data["run_id"]
        )
        assert latest["task"] == "distribution_target_test"
        assert latest["status"] == "success"
        assert latest["target_id"] == "target-1"
        assert latest["result"]["message"] == data["message"]

    @pytest.mark.asyncio
    async def test_targets_send_test_endpoint_records_success_run(
        self,
        client: AsyncClient,
        monkeypatch,
    ):
        class FakePushService:
            async def push(self, content: Dict[str, Any], target_id: str):
                assert target_id == "target-1"
                assert content["title"] == "VaultStream 推送目标真实发送测试"
                assert content["render_config"]["media_mode"] == "none"
                return "message-123"

        monkeypatch.setattr(
            "app.push.factory.get_push_service",
            lambda platform: FakePushService(),
        )

        resp = await client.post(
            "/api/v1/targets/send-test",
            json={"platform": "telegram", "target_id": "target-1"},
        )
        assert resp.status_code == 200
        data = resp.json()
        assert data["status"] == "ok"
        assert data["platform"] == "telegram"
        assert data["target_id"] == "target-1"
        assert data["run_id"]
        assert data["details"]["message_id"] == "message-123"

        diagnostics = await client.get("/api/v1/background-tasks/diagnostics")
        latest = next(
            run
            for run in diagnostics.json()["recent_task_runs"]
            if run["run_id"] == data["run_id"]
        )
        assert latest["task"] == "distribution_target_send_test"
        assert latest["status"] == "success"
        assert latest["target_id"] == "target-1"
        assert latest["result"]["details"]["message_id"] == "message-123"

    @pytest.mark.asyncio
    async def test_targets_batch_update_endpoint(self, client: AsyncClient):
        # Create a rule and a target
        rule_resp = await client.post(
            "/api/v1/distribution-rules",
            json={
                "name": "test-batch-update-rule",
                "description": "test",
                "match_conditions": {"tags": ["t1"]},
                "enabled": True,
                "priority": 1,
                "nsfw_policy": "block",
                "approval_required": False,
            }
        )
        assert rule_resp.status_code == 200
        rule = rule_resp.json()

        resp = await client.post(
            "/api/v1/targets/batch-update",
            json={
                "rule_ids": [rule["id"]],
                "target_platform": "telegram",
                "target_id": "-100dummy",
                "enabled": False,
            }
        )
        # Should raise 404 because building a chat failed since -100dummy does not exist in BotChat table
        assert resp.status_code == 404
