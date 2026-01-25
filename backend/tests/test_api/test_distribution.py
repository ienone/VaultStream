"""
Distribution API Tests - Auto-distribution and Telegram push
"""
import pytest
from httpx import AsyncClient


class TestDistributionAPI:
    """Test suite for distribution endpoints"""
    
    @pytest.mark.asyncio
    async def test_get_distribution_status(self, client: AsyncClient):
        """Test GET /api/v1/distribution/status"""
        response = await client.get("/api/v1/distribution/status")
        assert response.status_code == 200
        
        data = response.json()
        assert "enabled" in data
        assert isinstance(data["enabled"], bool)
    
    @pytest.mark.asyncio
    async def test_trigger_distribution(self, client: AsyncClient):
        """Test POST /api/v1/distribution/trigger"""
        response = await client.post("/api/v1/distribution/trigger")
        
        # Should succeed or return appropriate status
        assert response.status_code in [200, 202]
    
    @pytest.mark.asyncio
    async def test_distribution_history(self, client: AsyncClient):
        """Test GET /api/v1/distribution/history"""
        response = await client.get("/api/v1/distribution/history")
        assert response.status_code == 200
        
        data = response.json()
        assert isinstance(data, (list, dict))
