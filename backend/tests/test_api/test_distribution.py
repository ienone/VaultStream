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
        assert "total" in data
        assert "due_now" in data
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
