"""
System API Tests - Health checks, system info, etc.
"""
import pytest
from httpx import AsyncClient


class TestSystemAPI:
    """Test suite for system endpoints"""
    
    @pytest.mark.asyncio
    async def test_health_check(self, client: AsyncClient):
        """Test /health endpoint"""
        response = await client.get("/health")
        assert response.status_code == 200
        
        data = response.json()
        assert "status" in data
        assert data["status"] in ["ok", "degraded"]
        assert "db" in data
        assert "redis" in data
    
    @pytest.mark.asyncio
    async def test_api_root(self, client: AsyncClient):
        """Test /api root endpoint"""
        response = await client.get("/api")
        assert response.status_code == 200
        
        data = response.json()
        assert "name" in data
        assert "version" in data
        assert data["name"] == "VaultStream"
    
    @pytest.mark.asyncio
    async def test_system_stats(self, client: AsyncClient):
        """Test /api/v1/dashboard/stats endpoint"""
        response = await client.get("/api/v1/dashboard/stats")
        assert response.status_code == 200
        
        data = response.json()
        # Should have basic stats structure
        assert isinstance(data, dict)
