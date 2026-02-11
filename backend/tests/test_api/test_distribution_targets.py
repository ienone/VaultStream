"""
Distribution Targets API Tests - Test the new DistributionTarget CRUD API
"""
import pytest
from httpx import AsyncClient


class TestDistributionTargetsAPI:
    """Test suite for distribution targets endpoints"""
    
    @pytest.mark.asyncio
    async def test_list_targets_empty(self, client: AsyncClient):
        """Test GET /api/v1/distribution-rules/{rule_id}/targets with non-existent rule"""
        response = await client.get("/api/v1/distribution-rules/999/targets")
        # Should return 404 for non-existent rule or empty list
        assert response.status_code in [200, 404]
    
    @pytest.mark.asyncio
    async def test_create_target_missing_rule(self, client: AsyncClient):
        """Test POST /api/v1/distribution-rules/{rule_id}/targets with non-existent rule"""
        payload = {
            "bot_chat_id": 1,
            "enabled": True,
        }
        response = await client.post("/api/v1/distribution-rules/999/targets", json=payload)
        # Should return 404 for non-existent rule
        assert response.status_code == 404
    
    @pytest.mark.asyncio
    async def test_update_target_not_found(self, client: AsyncClient):
        """Test PATCH /api/v1/distribution-rules/{rule_id}/targets/{target_id} with non-existent target"""
        payload = {"enabled": False}
        response = await client.patch("/api/v1/distribution-rules/1/targets/999", json=payload)
        # Should return 404 for non-existent target
        assert response.status_code == 404
    
    @pytest.mark.asyncio
    async def test_delete_target_not_found(self, client: AsyncClient):
        """Test DELETE /api/v1/distribution-rules/{rule_id}/targets/{target_id} with non-existent target"""
        response = await client.delete("/api/v1/distribution-rules/1/targets/999")
        # Should return 404 for non-existent target
        assert response.status_code == 404
