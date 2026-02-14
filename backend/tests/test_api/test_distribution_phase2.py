"""Phase 2 API tests for distribution workflow refactor."""

from datetime import datetime

import pytest
from httpx import AsyncClient


class TestDistributionPhase2API:
    @staticmethod
    async def _create_primary_bot_config(client: AsyncClient, suffix: str) -> int:
        cfg_resp = await client.post(
            "/api/v1/bot-config",
            json={
                "platform": "telegram",
                "name": f"phase2-primary-{suffix}",
                "bot_token": f"123456:{suffix}",
                "enabled": True,
                "is_primary": True,
            },
        )
        assert cfg_resp.status_code == 201
        return cfg_resp.json()["id"]

    @pytest.mark.asyncio
    async def test_create_rule_then_bind_target_via_target_api(self, client: AsyncClient):
        suffix = datetime.utcnow().strftime("%H%M%S%f")
        chat_id = f"-100phase2{suffix[-6:]}"
        bot_config_id = await self._create_primary_bot_config(client, suffix)

        chat_resp = await client.post(
            "/api/v1/bot/chats",
            json={
                "bot_config_id": bot_config_id,
                "chat_id": chat_id,
                "chat_type": "channel",
                "title": f"Phase2 Chat {suffix}",
                "enabled": True,
            },
        )
        assert chat_resp.status_code == 200
        chat = chat_resp.json()

        rule_resp = await client.post(
            "/api/v1/distribution-rules",
            json={
                "name": f"phase2-rule-{suffix}",
                "description": "phase2 target create",
                "match_conditions": {"tags": ["phase2"], "tags_match_mode": "any"},
                "enabled": True,
                "priority": 1,
                "nsfw_policy": "block",
                "approval_required": False,
            },
        )
        assert rule_resp.status_code == 200
        rule = rule_resp.json()

        create_target_resp = await client.post(
            f"/api/v1/distribution-rules/{rule['id']}/targets",
            json={
                "bot_chat_id": chat["id"],
                "enabled": True,
            },
        )
        assert create_target_resp.status_code == 201

        targets_resp = await client.get(f"/api/v1/distribution-rules/{rule['id']}/targets")
        assert targets_resp.status_code == 200
        targets = targets_resp.json()
        assert len(targets) >= 1
        assert any(t["bot_chat_id"] == chat["id"] for t in targets)

    @pytest.mark.asyncio
    async def test_assign_rules_for_chat(self, client: AsyncClient):
        suffix = datetime.utcnow().strftime("%H%M%S%f")
        chat_id = f"-100bind{suffix[-6:]}"
        bot_config_id = await self._create_primary_bot_config(client, suffix)

        chat_resp = await client.post(
            "/api/v1/bot/chats",
            json={
                "bot_config_id": bot_config_id,
                "chat_id": chat_id,
                "chat_type": "group",
                "title": f"RuleBinding Chat {suffix}",
                "enabled": True,
            },
        )
        assert chat_resp.status_code == 200

        rule_ids = []
        for i in range(2):
            create_rule_resp = await client.post(
                "/api/v1/distribution-rules",
                json={
                    "name": f"phase2-bind-{i}-{suffix}",
                    "match_conditions": {"tags": ["bind", str(i)], "tags_match_mode": "any"},
                    "enabled": True,
                    "priority": i,
                    "nsfw_policy": "block",
                    "approval_required": False,
                },
            )
            assert create_rule_resp.status_code == 200
            rule_ids.append(create_rule_resp.json()["id"])

        assign_resp = await client.put(
            f"/api/v1/bot/chats/{chat_id}/rules",
            json={"rule_ids": rule_ids},
        )
        assert assign_resp.status_code == 200
        assigned = assign_resp.json()
        assert set(assigned["rule_ids"]) == set(rule_ids)

        chat_detail_resp = await client.get(f"/api/v1/bot/chats/{chat_id}")
        assert chat_detail_resp.status_code == 200
        chat_detail = chat_detail_resp.json()
        assert set(chat_detail["applied_rule_ids"]) == set(rule_ids)
        assert chat_detail["applied_rule_count"] == len(rule_ids)

    @pytest.mark.asyncio
    async def test_delete_rule_with_targets(self, client: AsyncClient):
        suffix = datetime.utcnow().strftime("%H%M%S%f")
        chat_id = f"-100del{suffix[-6:]}"
        bot_config_id = await self._create_primary_bot_config(client, suffix)

        chat_resp = await client.post(
            "/api/v1/bot/chats",
            json={
                "bot_config_id": bot_config_id,
                "chat_id": chat_id,
                "chat_type": "channel",
                "title": f"Delete Rule Chat {suffix}",
                "enabled": True,
            },
        )
        assert chat_resp.status_code == 200
        chat = chat_resp.json()

        rule_resp = await client.post(
            "/api/v1/distribution-rules",
            json={
                "name": f"phase2-delete-{suffix}",
                "match_conditions": {"tags": ["delete", "target"], "tags_match_mode": "any"},
                "enabled": True,
                "priority": 1,
                "nsfw_policy": "block",
                "approval_required": False,
            },
        )
        assert rule_resp.status_code == 200
        rule = rule_resp.json()

        create_target_resp = await client.post(
            f"/api/v1/distribution-rules/{rule['id']}/targets",
            json={
                "bot_chat_id": chat["id"],
                "enabled": True,
            },
        )
        assert create_target_resp.status_code == 201

        delete_rule_resp = await client.delete(f"/api/v1/distribution-rules/{rule['id']}")
        assert delete_rule_resp.status_code == 200
        assert delete_rule_resp.json()["status"] == "deleted"

        verify_resp = await client.get(f"/api/v1/distribution-rules/{rule['id']}")
        assert verify_resp.status_code == 404

    @pytest.mark.asyncio
    async def test_bot_config_crud_and_activate(self, client: AsyncClient):
        suffix = datetime.utcnow().strftime("%H%M%S%f")
        create_resp = await client.post(
            "/api/v1/bot-config",
            json={
                "platform": "telegram",
                "name": f"tg-phase2-{suffix}",
                "bot_token": "123456:TEST_TOKEN",
                "enabled": True,
                "is_primary": False,
            },
        )
        assert create_resp.status_code == 201
        cfg = create_resp.json()

        list_resp = await client.get("/api/v1/bot-config")
        assert list_resp.status_code == 200
        assert any(item["id"] == cfg["id"] for item in list_resp.json())

        activate_resp = await client.post(f"/api/v1/bot-config/{cfg['id']}/activate")
        assert activate_resp.status_code == 200
        assert activate_resp.json()["is_primary"] is True

        patch_resp = await client.patch(
            f"/api/v1/bot-config/{cfg['id']}",
            json={"name": f"tg-phase2-updated-{suffix}", "enabled": False},
        )
        assert patch_resp.status_code == 200
        assert patch_resp.json()["enabled"] is False

        delete_resp = await client.delete(f"/api/v1/bot-config/{cfg['id']}")
        assert delete_resp.status_code == 204
