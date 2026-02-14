"""
Distribution API Tests - Auto-distribution and Telegram push
"""
import pytest
from httpx import AsyncClient


class TestDistributionAPI:
    """Test suite for distribution endpoints"""
    
    @pytest.mark.asyncio
    async def test_get_distribution_status(self, client: AsyncClient):
        """Test GET /api/v1/distribution-queue/stats"""
        response = await client.get("/api/v1/distribution-queue/stats")
        assert response.status_code == 200
        
        data = response.json()
        assert "will_push" in data
        assert "filtered" in data
        assert "pending_review" in data
        assert "pushed" in data
        assert "total" in data
        assert "due_now" in data
        assert isinstance(data["will_push"], int)
        assert isinstance(data["filtered"], int)
        assert isinstance(data["pending_review"], int)
        assert isinstance(data["pushed"], int)
        assert isinstance(data["total"], int)
        assert isinstance(data["due_now"], int)
    
    @pytest.mark.asyncio
    async def test_trigger_distribution(self, client: AsyncClient):
        """Test POST /api/v1/distribution/trigger-run"""
        response = await client.post("/api/v1/distribution/trigger-run")
        
        assert response.status_code == 200
        data = response.json()
        assert data.get("status") == "triggered"
        assert isinstance(data.get("enqueued_count"), int)
    
    @pytest.mark.asyncio
    async def test_distribution_history(self, client: AsyncClient):
        """Test GET /api/v1/distribution-queue/items"""
        response = await client.get("/api/v1/distribution-queue/items?page=1&size=20")
        assert response.status_code == 200
        
        data = response.json()
        assert isinstance(data, dict)
        assert "items" in data
        assert "total" in data
        assert isinstance(data["items"], list)
        assert isinstance(data["total"], int)

    @pytest.mark.asyncio
    async def test_distribution_content_status_action(self, client: AsyncClient):
        """Test POST /api/v1/distribution-queue/content/{content_id}/status"""
        response = await client.post(
            "/api/v1/distribution-queue/content/1/status",
            json={"status": "filtered"},
        )
        assert response.status_code == 200

        data = response.json()
        assert data.get("status") == "ok"
        assert "moved" in data

    @pytest.mark.asyncio
    async def test_distribution_content_batch_actions(self, client: AsyncClient):
        """Test migrated batch action endpoints under /distribution-queue/content/*"""
        response = await client.post(
            "/api/v1/distribution-queue/content/batch-push-now",
            json={"content_ids": [1, 2]},
        )
        assert response.status_code == 200
        assert "changed" in response.json()

        response = await client.post(
            "/api/v1/distribution-queue/content/batch-reschedule",
            json={
                "content_ids": [1],
                "start_time": "2026-02-13T12:00:00Z",
                "interval_seconds": 300,
            },
        )
        assert response.status_code == 200
        assert "changed" in response.json()
