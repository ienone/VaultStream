
import pytest
from httpx import AsyncClient
from datetime import datetime, timedelta, timezone

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
        push_now_data = push_now_resp.json()
        assert push_now_data["run_id"]

        diagnostics = await client.get("/api/v1/background-tasks/diagnostics")
        runs = diagnostics.json()["recent_task_runs"]
        content_run = next(run for run in runs if run["run_id"] == push_now_data["run_id"])
        assert content_run["task"] == "distribution_schedule"
        assert content_run["action"] == "content_push_now"
        assert content_run["status"] == "success"
        assert content_run["content_id"] == content_id
        assert content_run["result"]["changed"] >= 0

        # Batch push now
        batch_push_resp = await client.post(
            "/api/v1/distribution-queue/content/batch-push-now",
            json={"content_ids": [content_id]},
        )
        assert batch_push_resp.status_code == 200
        batch_push_data = batch_push_resp.json()
        assert batch_push_data["run_id"]

        diagnostics = await client.get("/api/v1/background-tasks/diagnostics")
        runs = diagnostics.json()["recent_task_runs"]
        batch_run = next(run for run in runs if run["run_id"] == batch_push_data["run_id"])
        assert batch_run["task"] == "distribution_schedule"
        assert batch_run["action"] == "content_batch_push_now"
        assert batch_run["status"] == "success"
        assert batch_run["content_ids"] == [content_id]

        # Batch repush now
        batch_repush_resp = await client.post(
            "/api/v1/distribution-queue/content/batch-repush-now",
            json={"content_ids": [content_id]}
        )
        assert batch_repush_resp.status_code == 200
        assert batch_repush_resp.json()["changed"] >= 1

    @pytest.mark.asyncio
    async def test_content_repush_with_target_id_is_target_scoped(self, client: AsyncClient):
        content_id, rule_id, _ = await self._setup_data(client)

        suffix = datetime.now(timezone.utc).strftime("%H%M%S%f")
        bot_resp = await client.post(
            "/api/v1/bot-config",
            json={
                "platform": "telegram",
                "name": f"repush-scope-bot-{suffix}",
                "bot_token": f"123456:RETRY-{suffix}",
                "enabled": True,
                "is_primary": False,
            },
        )
        assert bot_resp.status_code == 201

        chat_resp = await client.post(
            "/api/v1/bot/chats",
            json={
                "bot_config_id": bot_resp.json()["id"],
                "chat_id": f"-200{suffix}",
                "chat_type": "channel",
                "title": f"Repush Scope Chat {suffix}",
                "enabled": True,
            },
        )
        assert chat_resp.status_code == 200

        target_resp = await client.post(
            f"/api/v1/distribution-rules/{rule_id}/targets",
            json={"bot_chat_id": chat_resp.json()["id"], "enabled": True},
        )
        assert target_resp.status_code == 201
        await client.post(f"/api/v1/distribution-queue/enqueue/{content_id}", json={"force": True})

        items_resp = await client.get(f"/api/v1/distribution-queue/items?content_id={content_id}")
        items = items_resp.json()["items"]
        assert len(items) >= 2
        target_ids = [item["target_id"] for item in items]
        selected_target_id = target_ids[0]
        untouched_target_id = next(target_id for target_id in target_ids if target_id != selected_target_id)
        expected_remaining_target_ids = set(target_ids) - {selected_target_id}

        from sqlalchemy import and_, delete, select
        from app.core.db_adapter import AsyncSessionLocal
        from app.core.time_utils import utcnow
        from app.models import ContentQueueItem, PushedRecord, QueueItemStatus

        async with AsyncSessionLocal() as session:
            await session.execute(delete(PushedRecord).where(PushedRecord.content_id == content_id))
            rows = (
                await session.execute(
                    select(ContentQueueItem).where(ContentQueueItem.content_id == content_id)
                )
            ).scalars().all()
            for item in rows:
                item.status = QueueItemStatus.FAILED
                item.last_error = "failed before retry"
                item.last_error_type = "push_failed"
                item.last_error_at = utcnow()
                session.add(
                    PushedRecord(
                        content_id=content_id,
                        target_platform=item.target_platform,
                        target_id=item.target_id,
                        message_id=f"message-{item.target_id}",
                        push_status="failed",
                        error_message="failed before retry",
                    )
                )
            await session.commit()

        repush_resp = await client.post(
            f"/api/v1/distribution-queue/content/{content_id}/repush-now",
            params={"target_id": selected_target_id},
        )
        assert repush_resp.status_code == 200
        assert repush_resp.json()["changed"] == 1
        assert repush_resp.json()["deleted_records"] == 1

        async with AsyncSessionLocal() as session:
            selected = (
                await session.execute(
                    select(ContentQueueItem).where(
                        and_(
                            ContentQueueItem.content_id == content_id,
                            ContentQueueItem.target_id == selected_target_id,
                        )
                    )
                )
            ).scalar_one()
            untouched = (
                await session.execute(
                    select(ContentQueueItem).where(
                        and_(
                            ContentQueueItem.content_id == content_id,
                            ContentQueueItem.target_id == untouched_target_id,
                        )
                    )
                )
            ).scalar_one()
            remaining_records = (
                await session.execute(
                    select(PushedRecord).where(PushedRecord.content_id == content_id)
                )
            ).scalars().all()

        assert selected.status == QueueItemStatus.SCHEDULED
        assert selected.last_error is None
        assert untouched.status == QueueItemStatus.FAILED
        assert untouched.last_error == "failed before retry"
        assert {record.target_id for record in remaining_records} == expected_remaining_target_ids

    @pytest.mark.asyncio
    async def test_item_push_now(self, client: AsyncClient, monkeypatch):
        class FakeQueueWorker:
            async def process_item_now(self, item_id: int, worker_name: str = "api-manual"):
                from app.core.db_adapter import AsyncSessionLocal
                from app.core.time_utils import utcnow
                from app.models import ContentQueueItem, QueueItemStatus

                async with AsyncSessionLocal() as session:
                    item = await session.get(ContentQueueItem, item_id)
                    item.status = QueueItemStatus.SUCCESS
                    item.message_id = "test-message-id"
                    item.completed_at = utcnow()
                    item.last_error = None
                    item.last_error_type = None
                    item.last_error_at = None
                    await session.commit()

        monkeypatch.setattr(
            "app.routers.distribution_queue.get_queue_worker",
            lambda: FakeQueueWorker(),
        )

        content_id, _, _ = await self._setup_data(client)
        await client.post(f"/api/v1/distribution-queue/enqueue/{content_id}", json={"force": True})
        
        items_resp = await client.get(f"/api/v1/distribution-queue/items?content_id={content_id}")
        item_id = items_resp.json()["items"][0]["id"]
        
        resp = await client.post(f"/api/v1/distribution-queue/items/{item_id}/push-now")
        assert resp.status_code == 200
        data = resp.json()
        assert data["status"] == "success"
        assert data["run_id"]
        assert data["message_id"] == "test-message-id"

        diagnostics = await client.get("/api/v1/background-tasks/diagnostics")
        runs = diagnostics.json()["recent_task_runs"]
        latest = next(run for run in runs if run["run_id"] == data["run_id"])
        assert latest["task"] == "distribution_push"
        assert latest["status"] == "success"
        assert latest["queue_item_id"] == item_id
        assert latest["content_id"] == content_id
        assert latest["result"]["message_id"] == "test-message-id"

    @pytest.mark.asyncio
    async def test_item_status_schedule_and_reorder_are_item_scoped(self, client: AsyncClient):
        content_id, _, _ = await self._setup_data(client)
        await client.post(f"/api/v1/distribution-queue/enqueue/{content_id}", json={"force": True})

        items_resp = await client.get(f"/api/v1/distribution-queue/items?content_id={content_id}")
        items = items_resp.json()["items"]
        assert len(items) >= 1
        item_id = items[0]["id"]

        status_resp = await client.post(
            f"/api/v1/distribution-queue/items/{item_id}/status",
            json={"status": "filtered", "reason": "skip this target only"},
        )
        assert status_resp.status_code == 200
        assert status_resp.json()["id"] == item_id
        assert status_resp.json()["status"] == "failed"
        assert status_resp.json()["last_error_type"] == "manual_filtered"

        scheduled_at = datetime.now(timezone.utc).isoformat()
        schedule_resp = await client.post(
            f"/api/v1/distribution-queue/items/{item_id}/schedule",
            json={"scheduled_at": scheduled_at},
        )
        assert schedule_resp.status_code == 200
        assert schedule_resp.json()["id"] == item_id
        assert schedule_resp.json()["status"] == "scheduled"

        reorder_resp = await client.post(
            f"/api/v1/distribution-queue/items/{item_id}/reorder",
            json={"index": 0},
        )
        assert reorder_resp.status_code == 200
        assert reorder_resp.json()["id"] == item_id
        assert reorder_resp.json()["priority"] >= 1000

    @pytest.mark.asyncio
    async def test_item_batch_push_and_schedule_are_item_scoped(self, client: AsyncClient):
        content_id, _, _ = await self._setup_data(client)
        await client.post(f"/api/v1/distribution-queue/enqueue/{content_id}", json={"force": True})

        items_resp = await client.get(f"/api/v1/distribution-queue/items?content_id={content_id}")
        items = items_resp.json()["items"]
        assert len(items) >= 1
        item_id = items[0]["id"]

        push_resp = await client.post(
            "/api/v1/distribution-queue/items/batch-push-now",
            json={"item_ids": [item_id]},
        )
        assert push_resp.status_code == 200
        push_data = push_resp.json()
        assert push_data["changed"] == 1
        assert push_data["run_id"]

        diagnostics = await client.get("/api/v1/background-tasks/diagnostics")
        runs = diagnostics.json()["recent_task_runs"]
        push_run = next(run for run in runs if run["run_id"] == push_data["run_id"])
        assert push_run["task"] == "distribution_schedule"
        assert push_run["action"] == "item_batch_push_now"
        assert push_run["queue_item_ids"] == [item_id]
        assert push_run["result"]["queue_item_ids"] == [item_id]

        start_time = (datetime.now(timezone.utc) + timedelta(minutes=5)).isoformat()
        schedule_resp = await client.post(
            "/api/v1/distribution-queue/items/batch-schedule",
            json={
                "item_ids": [item_id],
                "start_time": start_time,
                "interval_seconds": 60,
            },
        )
        assert schedule_resp.status_code == 200
        assert schedule_resp.json()["changed"] == 1

        item_resp = await client.get(f"/api/v1/distribution-queue/items/{item_id}")
        assert item_resp.status_code == 200
        assert item_resp.json()["id"] == item_id
        assert item_resp.json()["status"] == "scheduled"
