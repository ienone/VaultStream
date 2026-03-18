
import pytest
from httpx import AsyncClient
from datetime import datetime, timezone

class TestDistributionQueueExtraAPI:
    """Extra tests for distribution queue management endpoints."""

    async def _setup_data(self, client: AsyncClient):
        # Ensure task queue and event bus are connected/started
        from app.core.queue import task_queue
        if task_queue._session_maker is None:
            await task_queue.connect()
        
        from app.core.events import event_bus
        await event_bus.start()

        # 1. Create a bot config
        suffix = datetime.now(timezone.utc).strftime("%H%M%S%f")
        bot_resp = await client.post(
            "/api/v1/bot-config",
            json={
                "platform": "telegram",
                "name": f"test-bot-{suffix}",
                "bot_token": f"123456:ABC-{suffix}",
                "enabled": True,
                "is_primary": True
            }
        )
        assert bot_resp.status_code == 201
        bot_id = bot_resp.json()["id"]

        # 2. Create a bot chat
        chat_resp = await client.post(
            "/api/v1/bot/chats",
            json={
                "bot_config_id": bot_id,
                "chat_id": f"-100{suffix}",
                "chat_type": "channel",
                "title": f"Test Chat {suffix}",
                "enabled": True
            }
        )
        assert chat_resp.status_code == 200
        chat_id = chat_resp.json()["id"]

        # 3. Create a distribution rule
        rule_resp = await client.post(
            "/api/v1/distribution-rules",
            json={
                "name": f"test-rule-{suffix}",
                "match_conditions": {"tags": ["test-tag"], "tags_match_mode": "any"},
                "enabled": True,
                "priority": 10,
                "nsfw_policy": "allow",
                "approval_required": True
            }
        )
        assert rule_resp.status_code == 200
        rule_id = rule_resp.json()["id"]

        # 4. Bind target
        target_resp = await client.post(
            f"/api/v1/distribution-rules/{rule_id}/targets",
            json={
                "bot_chat_id": chat_id,
                "enabled": True
            }
        )
        assert target_resp.status_code == 201

        # 5. Create content
        content_resp = await client.post(
            "/api/v1/shares",
            json={"url": f"https://www.bilibili.com/video/BV{suffix}"}
        )
        # It might return 200 if already exists, or 201 if created
        assert content_resp.status_code in [200, 201]
        content_id = content_resp.json()["id"]

        # 6. Manually update content status and tags to match rule
        await client.patch(
            f"/api/v1/contents/{content_id}",
            json={
                "tags": ["test-tag"],
                "status": "parse_success",
                "title": f"Test Title {suffix}",
                "author_name": "Test Author"
            }
        )
        await client.post(
            f"/api/v1/cards/{content_id}/review",
            json={"action": "approve"},
        )

        return content_id, rule_id, chat_id

    @pytest.mark.asyncio
    async def test_enqueue_and_item_lifecycle(self, client: AsyncClient):
        content_id, rule_id, chat_id = await self._setup_data(client)

        # 1. Enqueue manually
        enqueue_resp = await client.post(f"/api/v1/distribution-queue/enqueue/{content_id}", json={"force": True})
        assert enqueue_resp.status_code == 200
        # The enqueued_count might be 0 if the rule was already processed during creation
        # but with force=True it should try again or at least not fail.
        # Actually, in _setup_data, the rule creation might have already triggered enqueueing.
        
        # 2. List items to find the ID
        items_resp = await client.get(f"/api/v1/distribution-queue/items?content_id={content_id}")
        assert items_resp.status_code == 200
        items = items_resp.json()["items"]
        if not items:
            # Try to enqueue again if not auto-enqueued
            enqueue_resp = await client.post(f"/api/v1/distribution-queue/enqueue/{content_id}", json={"force": True})
            items_resp = await client.get(f"/api/v1/distribution-queue/items?content_id={content_id}")
            items = items_resp.json()["items"]
        
        assert len(items) > 0, f"No queue items found for content {content_id}"
        item_id = items[0]["id"]

        # 3. Get single item
        get_resp = await client.get(f"/api/v1/distribution-queue/items/{item_id}")
        assert get_resp.status_code == 200
        assert get_resp.json()["id"] == item_id

        # 4. Cancel item
        cancel_resp = await client.post(f"/api/v1/distribution-queue/items/{item_id}/cancel")
        assert cancel_resp.status_code == 200
        
        # Verify status
        verify_resp = await client.get(f"/api/v1/distribution-queue/items/{item_id}")
        assert verify_resp.json()["status"] == "failed"

        # 5. Retry item
        retry_resp = await client.post(
            f"/api/v1/distribution-queue/items/{item_id}/retry",
            json={"reset_attempts": True}
        )
        assert retry_resp.status_code == 200
        assert retry_resp.json()["status"] == "scheduled"

    @pytest.mark.asyncio
    async def test_batch_retry(self, client: AsyncClient):
        content_id, _, _ = await self._setup_data(client)
        
        # Enqueue
        await client.post(f"/api/v1/distribution-queue/enqueue/{content_id}", json={"force": True})
        
        # Find item and cancel it so we can retry it
        items_resp = await client.get(f"/api/v1/distribution-queue/items?content_id={content_id}")
        item_id = items_resp.json()["items"][0]["id"]
        await client.post(f"/api/v1/distribution-queue/items/{item_id}/cancel")

        # Batch retry
        batch_resp = await client.post(
            "/api/v1/distribution-queue/batch-retry",
            json={
                "item_ids": [item_id],
                "reset_attempts": True
            }
        )
        assert batch_resp.status_code == 200
        assert batch_resp.json()["retried_count"] == 1

    @pytest.mark.asyncio
    async def test_content_repush_and_reorder(self, client: AsyncClient):
        content_id, _, _ = await self._setup_data(client)

        # Enqueue first
        await client.post(f"/api/v1/distribution-queue/enqueue/{content_id}", json={"force": True})

        # Repush now
        repush_resp = await client.post(f"/api/v1/distribution-queue/content/{content_id}/repush-now")
        assert repush_resp.status_code == 200
        assert "changed" in repush_resp.json()

        # Reorder
        reorder_resp = await client.post(
            f"/api/v1/distribution-queue/content/{content_id}/reorder",
            json={"index": 0}
        )
        assert reorder_resp.status_code == 200
        assert reorder_resp.json()["changed"] >= 1

        # Push now (content dimension)
        push_now_resp = await client.post(f"/api/v1/distribution-queue/content/{content_id}/push-now")
        assert push_now_resp.status_code == 200

        # Batch repush now
        batch_repush_resp = await client.post(
            "/api/v1/distribution-queue/content/batch-repush-now",
            json={"content_ids": [content_id]}
        )
        assert batch_repush_resp.status_code == 200
        assert batch_repush_resp.json()["changed"] >= 1

    @pytest.mark.asyncio
    async def test_item_push_now(self, client: AsyncClient):
        content_id, _, _ = await self._setup_data(client)
        await client.post(f"/api/v1/distribution-queue/enqueue/{content_id}", json={"force": True})
        
        items_resp = await client.get(f"/api/v1/distribution-queue/items?content_id={content_id}")
        item_id = items_resp.json()["items"][0]["id"]
        
        resp = await client.post(f"/api/v1/distribution-queue/items/{item_id}/push-now")
        assert resp.status_code == 200
        assert resp.json()["status"] == "scheduled"

