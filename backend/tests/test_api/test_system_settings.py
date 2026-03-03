import pytest
from httpx import AsyncClient
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select

from app.models import SystemSetting


class TestSystemSettingsAPI:
    @pytest.mark.asyncio
    async def test_health_check(self, client: AsyncClient):
        response = await client.get("/api/v1/health")
        assert response.status_code == 200
        data = response.json()
        assert "status" in data
        assert "components" in data

    @pytest.mark.asyncio
    async def test_init_status(self, client: AsyncClient):
        response = await client.get("/api/v1/init-status")
        assert response.status_code == 200
        data = response.json()
        assert "needs_setup" in data
        assert "has_bot" in data
        assert "version" in data

    @pytest.mark.asyncio
    async def test_dashboard_stats(self, client: AsyncClient):
        response = await client.get("/api/v1/dashboard/stats")
        assert response.status_code == 200
        data = response.json()
        assert "platform_counts" in data
        assert "daily_growth" in data
        assert "storage_usage_bytes" in data

    @pytest.mark.asyncio
    async def test_dashboard_queue(self, client: AsyncClient):
        response = await client.get("/api/v1/dashboard/queue")
        assert response.status_code == 200
        data = response.json()
        assert "parse" in data
        assert "distribution" in data

    @pytest.mark.asyncio
    async def test_tags_list(self, client: AsyncClient):
        response = await client.get("/api/v1/tags")
        assert response.status_code == 200
        data = response.json()
        assert isinstance(data, list)

    @pytest.mark.asyncio
    async def test_system_settings_crud(self, client: AsyncClient):
        # 1. Update/Create a setting
        update_resp = await client.put(
            "/api/v1/settings/test_setting_key",
            json={
                "value": "test_value_123",
                "description": "A test setting"
            },
            params={"category": "test_category"}
        )
        assert update_resp.status_code == 200
        data = update_resp.json()
        assert data["key"] == "test_setting_key"
        assert data["value"] == "test_value_123"
        assert data["category"] == "test_category"

        # 2. Get the specific setting
        get_resp = await client.get("/api/v1/settings/test_setting_key")
        assert get_resp.status_code == 200
        assert get_resp.json()["value"] == "test_value_123"

        # 3. List settings (filter by category)
        list_resp = await client.get("/api/v1/settings", params={"category": "test_category"})
        assert list_resp.status_code == 200
        items = list_resp.json()
        assert len(items) >= 1
        assert any(item["key"] == "test_setting_key" for item in items)

        # 4. Delete the setting
        delete_resp = await client.delete("/api/v1/settings/test_setting_key")
        assert delete_resp.status_code == 200
        assert delete_resp.json()["status"] == "deleted"

        # Verify deletion
        verify_resp = await client.get("/api/v1/settings/test_setting_key")
        assert verify_resp.status_code == 404

    @pytest.mark.asyncio
    async def test_render_config_presets(self, client: AsyncClient):
        # List presets
        list_resp = await client.get("/api/v1/render-config-presets")
        assert list_resp.status_code == 200
        presets = list_resp.json()
        assert len(presets) > 0
        
        first_preset_id = presets[0]["id"]
        
        # Get single preset
        single_resp = await client.get(f"/api/v1/render-config-presets/{first_preset_id}")
        assert single_resp.status_code == 200
        assert single_resp.json()["id"] == first_preset_id

        # Not found test
        not_found_resp = await client.get("/api/v1/render-config-presets/nonexistent_preset_xyz")
        assert not_found_resp.status_code == 404
