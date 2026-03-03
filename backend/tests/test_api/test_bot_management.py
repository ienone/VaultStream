import pytest
from httpx import AsyncClient


from typing import Dict, Any

class TestBotManagementExtraAPI:
    @pytest.fixture
    async def create_bot_config(self, client: AsyncClient) -> Dict[str, Any]:
        resp = await client.post(
            "/api/v1/bot-config",
            json={
                "platform": "telegram",
                "name": "mgmt-test-bot",
                "bot_token": "dummy_token_123",
                "enabled": True,
                "is_primary": True,
            },
        )
        assert resp.status_code == 201
        return resp.json()

    @pytest.mark.asyncio
    async def test_bot_chats_crud(self, client: AsyncClient, create_bot_config):
        # The endpoints here are for bot chats management
        config_id = create_bot_config["id"]
        
        # 1. UPSERT a bot chat directly
        upsert_resp = await client.put(
            "/api/v1/bot/chats:upsert",
            json={
                "bot_config_id": config_id,
                "chat_id": "-100crudtest",
                "chat_type": "supergroup",
                "title": "CRUD Test Title",
                "is_accessible": True,
            }
        )
        assert upsert_resp.status_code in [200, 201]  # Might be 201 created or 200 updated
        chat = upsert_resp.json()
        assert chat["chat_id"] == "-100crudtest"
        target_chat_id = chat["chat_id"]

        # 2. GET single chat
        get_resp = await client.get(f"/api/v1/bot/chats/{target_chat_id}")
        assert get_resp.status_code == 200
        assert get_resp.json()["chat_id"] == target_chat_id

        # 3. PATCH single chat
        patch_resp = await client.patch(
            f"/api/v1/bot/chats/{target_chat_id}",
            json={"title": "Updated Title"}
        )
        assert patch_resp.status_code == 200
        assert patch_resp.json()["title"] == "Updated Title"

        # 4. TOGGLE single chat
        toggle_resp = await client.post(
            f"/api/v1/bot/chats/{target_chat_id}/toggle"
        )
        assert toggle_resp.status_code == 200
        assert toggle_resp.json()["enabled"] is False

        # 5. GET All chats
        all_chats_resp = await client.get("/api/v1/bot/chats")
        assert all_chats_resp.status_code == 200
        # items is a list for /bot/chats (it returns List[BotChatResponse])
        assert isinstance(all_chats_resp.json(), list)

        # 6. DELETE single chat
        delete_resp = await client.delete(f"/api/v1/bot/chats/{target_chat_id}")
        assert delete_resp.status_code == 200 # Note: bot_management.py returns a dict for delete, not 204
        assert delete_resp.json()["status"] == "deleted"

        # Verify deletion
        verify_resp = await client.get(f"/api/v1/bot/chats/{target_chat_id}")
        assert verify_resp.status_code == 404

    @pytest.mark.asyncio
    async def test_sync_all_chats(self, client: AsyncClient):
        # Test synchronizing all bot chats
        resp = await client.post("/api/v1/bot/chats/sync")
        # With dummy token, it returns 400. If no config, it returns 200 with 0 total.
        assert resp.status_code in [200, 400]
        if resp.status_code == 200:
            data = resp.json()
            assert "total" in data

    @pytest.mark.asyncio
    async def test_bot_heartbeat(self, client: AsyncClient):
        resp = await client.post(
            "/api/v1/bot/heartbeat",
            json={
                "bot_id": "123456789",
                "bot_username": "TestBot",
                "bot_first_name": "Test Bot",
                "version": "1.0",
            }
        )
        assert resp.status_code == 200
        assert resp.json()["status"] == "ok"

    @pytest.mark.asyncio
    async def test_bot_runtime(self, client: AsyncClient):
        resp = await client.get("/api/v1/bot/runtime")
        assert resp.status_code == 200
        assert "is_running" in resp.json()

    @pytest.mark.asyncio
    async def test_bot_status(self, client: AsyncClient):
        resp = await client.get("/api/v1/bot/status")
        assert resp.status_code == 200
        data = resp.json()
        assert "uptime_seconds" in data
        assert "is_running" in data
