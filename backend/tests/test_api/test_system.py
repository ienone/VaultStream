"""
System API Tests - Health checks, system info, etc.
"""
import asyncio

import pytest
from httpx import AsyncClient

from app.main import app
from app.services.background_task_state import (
    record_task_run_error,
    record_task_run_started,
    record_task_run_success,
)


class _FakeFavoritesSyncTask:
    def is_running(self) -> bool:
        return True

    def get_supported_platforms(self) -> list[str]:
        return ["zhihu"]

    def get_fetcher_cls(self, platform: str):
        return None

    def default_rate_for(self, platform: str) -> float:
        return 5.0

    async def load_enabled_platforms(self) -> list[str]:
        return []

    async def create_run(
        self,
        *,
        platform: str | None,
        trigger: str,
        retry_of: str | None = None,
    ) -> dict:
        run_id = "api-test-retry-run" if trigger == "retry" else "api-test-run"
        return await record_task_run_started(
            "favorites_sync",
            run_id=run_id,
            scope=platform or "all",
            trigger=trigger,
            **({"retry_of": retry_of} if retry_of else {}),
        )

    async def sync_platform_by_name(self, platform: str, *, run_id: str | None = None, trigger: str = "manual") -> dict:
        await record_task_run_success(
            "favorites_sync",
            run_id or "api-test-run",
            platform=platform,
            result={"status": "success", "imported": 1},
        )
        return {"status": "success", "imported": 1}

    async def sync_all_platforms_once(self, *, run_id: str | None = None, trigger: str = "manual") -> dict:
        await record_task_run_success(
            "favorites_sync",
            run_id or "api-test-run",
            results={},
        )
        return {}


class _HealthyFavoritesFetcher:
    async def check_auth(self) -> bool:
        return True


class _FakePlatformHealthFavoritesSyncTask(_FakeFavoritesSyncTask):
    def get_fetcher_cls(self, platform: str):
        return _HealthyFavoritesFetcher

    async def load_enabled_platforms(self) -> list[str]:
        return ["zhihu"]


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
        assert "components" in data
        assert "db" in data["components"]
        assert "fts" in data["components"]
        assert "checks" in data
        assert data["checks"]["database"]["fts"]["available"] is True
        assert data["checks"]["database"]["schema"]["status"] == "ok"
        assert "background_tasks" in data["checks"]
        assert "task_states" in data["checks"]["background_tasks"]
    
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
        """Test /api/v1/dashboard/stats endpoint returns expected fields."""
        response = await client.get("/api/v1/dashboard/stats")
        assert response.status_code == 200
        
        data = response.json()
        assert "platform_counts" in data
        assert isinstance(data["platform_counts"], dict)
        assert "daily_growth" in data
        assert isinstance(data["daily_growth"], list)
        assert "storage_usage_bytes" in data
        assert isinstance(data["storage_usage_bytes"], int)

    @pytest.mark.asyncio
    async def test_background_task_diagnostics(self, client: AsyncClient):
        response = await client.get("/api/v1/background-tasks/diagnostics")
        assert response.status_code == 200

        data = response.json()
        assert "summary" in data
        assert "task_states" in data
        assert "failed_parse_tasks" in data
        assert "failed_distribution_items" in data
        assert "failed_discovery_sources" in data

    @pytest.mark.asyncio
    async def test_background_task_metrics(self, client: AsyncClient):
        response = await client.get("/api/v1/background-tasks/metrics")
        assert response.status_code == 200
        assert "vaultstream_parse_tasks" in response.text
        assert "vaultstream_distribution_queue" in response.text

    @pytest.mark.asyncio
    async def test_favorites_sync_trigger_returns_run_id_and_status_lists_recent_runs(
        self,
        client: AsyncClient,
    ):
        previous = getattr(app.state, "favorites_sync_task", None)
        app.state.favorites_sync_task = _FakeFavoritesSyncTask()
        try:
            trigger = await client.post("/api/v1/favorites-sync/sync", json={"platform": "zhihu"})
            assert trigger.status_code == 202
            assert trigger.json()["run_id"] == "api-test-run"

            await asyncio.sleep(0)

            status = await client.get("/api/v1/favorites-sync/status")
            assert status.status_code == 200
            runs = status.json()["recent_runs"]
            assert runs
            assert runs[0]["run_id"] == "api-test-run"
            assert runs[0]["status"] in {"running", "success"}
        finally:
            if previous is None:
                app.state._state.pop("favorites_sync_task", None)
            else:
                app.state.favorites_sync_task = previous

    @pytest.mark.asyncio
    async def test_favorites_sync_retry_run_uses_recorded_scope(self, client: AsyncClient):
        previous = getattr(app.state, "favorites_sync_task", None)
        app.state.favorites_sync_task = _FakeFavoritesSyncTask()
        await record_task_run_started(
            "favorites_sync",
            run_id="failed-favorites-run",
            scope="zhihu",
            trigger="manual",
        )
        await record_task_run_error(
            "favorites_sync",
            "failed-favorites-run",
            "auth failed",
            platform="zhihu",
        )
        try:
            retry = await client.post("/api/v1/favorites-sync/runs/failed-favorites-run/retry")
            assert retry.status_code == 202
            assert retry.json()["run_id"] == "api-test-retry-run"
            assert retry.json()["retry_of"] == "failed-favorites-run"
            assert retry.json()["platform"] == "zhihu"

            await asyncio.sleep(0)

            status = await client.get("/api/v1/favorites-sync/status")
            latest = status.json()["recent_runs"][0]
            assert latest["run_id"] == "api-test-retry-run"
            assert latest["retry_of"] == "failed-favorites-run"
            assert latest["trigger"] == "retry"
        finally:
            if previous is None:
                app.state._state.pop("favorites_sync_task", None)
            else:
                app.state.favorites_sync_task = previous

    @pytest.mark.asyncio
    async def test_platform_health_aggregates_auth_and_favorites_sync(
        self,
        client: AsyncClient,
        monkeypatch,
    ):
        previous = getattr(app.state, "favorites_sync_task", None)
        app.state.favorites_sync_task = _FakePlatformHealthFavoritesSyncTask()
        await record_task_run_started(
            "favorites_sync",
            run_id="platform-health-run",
            scope="zhihu",
            trigger="manual",
        )
        await record_task_run_success(
            "favorites_sync",
            "platform-health-run",
            imported=2,
            skipped=1,
        )

        async def _cookie_configured(platform: str) -> bool:
            return platform == "zhihu"

        async def _browser_auth_valid(platform: str) -> bool:
            return platform == "zhihu"

        monkeypatch.setattr(
            "app.routers.system._is_any_platform_cookie_configured",
            _cookie_configured,
        )
        monkeypatch.setattr(
            "app.services.browser_auth_service.browser_auth_service.check_platform_status",
            _browser_auth_valid,
        )

        try:
            response = await client.get("/api/v1/platform-health")
            assert response.status_code == 200
            data = response.json()
            zhihu = next(item for item in data["platforms"] if item["platform"] == "zhihu")
            assert zhihu["health"] == "ok"
            assert zhihu["auth"]["cookie_configured"] is True
            assert zhihu["auth"]["browser_auth_valid"] is True
            assert zhihu["favorites_sync"]["enabled"] is True
            assert zhihu["favorites_sync"]["authenticated"] is True
            assert zhihu["favorites_sync"]["last_run"]["run_id"] == "platform-health-run"
        finally:
            if previous is None:
                app.state._state.pop("favorites_sync_task", None)
            else:
                app.state.favorites_sync_task = previous
