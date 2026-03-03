import pytest
from httpx import AsyncClient
from datetime import datetime, timezone

class TestCardsAPI:
    """Tests for Cards API endpoints (review UI backend)."""

    async def _setup_content(self, client: AsyncClient):
        # Initialize queue and events
        from app.core.queue import task_queue
        if task_queue._session_maker is None:
            await task_queue.connect()
        from app.core.events import event_bus
        await event_bus.start()

        suffix = datetime.now(timezone.utc).strftime("%H%M%S%f")
        resp = await client.post(
            "/api/v1/shares",
            json={"url": f"https://www.bilibili.com/video/BVcard{suffix}"}
        )
        assert resp.status_code in [200, 201]
        content_id = resp.json()["id"]
        
        # Patch some metadata to make it a nice card
        await client.patch(
            f"/api/v1/contents/{content_id}",
            json={
                "title": f"Card Title {suffix}",
                "author_name": "Card Author",
                "status": "parse_success"
            }
        )
        return content_id

    @pytest.mark.asyncio
    async def test_list_cards(self, client: AsyncClient):
        await self._setup_content(client)
        
        response = await client.get("/api/v1/cards")
        assert response.status_code == 200
        data = response.json()
        assert "items" in data
        assert "total" in data
        assert len(data["items"]) >= 1
        
        # Check structure of a card
        card = data["items"][0]
        assert "id" in card
        assert "title" in card
        assert "author_name" in card
        assert "review_status" in card

    @pytest.mark.asyncio
    async def test_get_single_card(self, client: AsyncClient):
        content_id = await self._setup_content(client)
        
        response = await client.get(f"/api/v1/cards/{content_id}")
        assert response.status_code == 200
        card = response.json()
        assert card["id"] == content_id
        assert "title" in card

    @pytest.mark.asyncio
    async def test_review_card(self, client: AsyncClient):
        content_id = await self._setup_content(client)
        
        # Approve it
        resp = await client.post(
            f"/api/v1/cards/{content_id}/review",
            json={"action": "approve", "reviewed_by": "pytest"}
        )
        assert resp.status_code == 200
        assert resp.json()["review_status"] == "approved"
        
        # Verify via GET
        card_resp = await client.get(f"/api/v1/cards/{content_id}")
        assert card_resp.json()["review_status"] == "approved"

    @pytest.mark.asyncio
    async def test_batch_review_cards(self, client: AsyncClient):
        id1 = await self._setup_content(client)
        id2 = await self._setup_content(client)
        
        resp = await client.post(
            "/api/v1/cards/batch-review",
            json={
                "content_ids": [id1, id2],
                "action": "reject",
                "note": "batch reject test",
                "reviewed_by": "pytest"
            }
        )
        assert resp.status_code == 200
        assert resp.json()["updated"] >= 2
        
        # Verify id1
        card1 = (await client.get(f"/api/v1/cards/{id1}")).json()
        assert card1["review_status"] == "rejected"
