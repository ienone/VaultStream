"""
System API Tests - Health checks, system info, etc.
"""
import asyncio
from types import SimpleNamespace

import pytest
from httpx import AsyncClient

from app.adapters.favorites.base import FavoriteItem
from app.main import app
from app.services.background_task_state import (
    record_task_run_error,
    record_task_run_started,
    record_task_run_success,
)
from app.services.config_service import FavoritesSyncConfig, FavoritesSyncPlatformState
from app.tasks.favorites_sync import FavoritesSyncTask


class _FakeFavoritesFetcher:
    async def check_auth(self) -> bool:
        return True

    def platform_name(self) -> str:
        return "zhihu"

    async def fetch_favorites(self, *, max_items: int = 50, cursor: str | None = None):
        return ([FavoriteItem(url="https://example.com/existing", title="已有收藏")], None)


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
        return ["zhihu"]

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


class _FakeFavoritesConfigService:
    async def get_favorites_sync_config(self, **kwargs) -> FavoritesSyncConfig:
        return FavoritesSyncConfig(
            enabled_platforms=[],
            interval_minutes=kwargs["default_interval_minutes"],
            max_items=50,
            duplicate_strategy="skip",
            scope_strategy="all_favorites",
            first_sync_strategy="latest_page",
            unfavorite_strategy="keep_local",
            last_sync_at=None,
        )

    async def get_favorites_sync_platform_state(
        self,
        platform: str,
        **kwargs,
    ) -> FavoritesSyncPlatformState:
        return FavoritesSyncPlatformState(
            platform=platform,
            rate_per_minute=100,
            cursor=None,
            last_result=None,
        )

    async def set_favorites_sync_cursor(self, platform: str, value: str):
        raise AssertionError("cursor should not be updated in this test")


class _HealthyFavoritesFetcher:
    async def check_auth(self) -> bool:
        return True


class _FakePlatformHealthFavoritesSyncTask(_FakeFavoritesSyncTask):
    def get_fetcher_cls(self, platform: str):
        return _HealthyFavoritesFetcher

    async def load_enabled_platforms(self) -> list[str]:
        return ["zhihu"]


class _DisabledFavoritesSyncTask(_FakeFavoritesSyncTask):
    async def load_enabled_platforms(self) -> list[str]:
        return []


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
        assert "providers" in data["checks"]
        providers = data["checks"]["providers"]
        assert "summary" in providers
        assert "embedding" in providers
        assert "agent_chat" in providers
        assert "text_llm" in providers
        assert "vision_llm" in providers
        assert "enabled" in providers["summary"]
        assert "api_version" in providers["summary"]
        assert "output_dimensionality" in providers["embedding"]
        assert "search_max_rows" in providers["embedding"]
        assert "base_url" in providers["agent_chat"]
        assert "base_url" in providers["text_llm"]
        assert "base_url" in providers["vision_llm"]
    
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
    async def test_background_task_run_lookup_by_id(self, client: AsyncClient):
        await record_task_run_started(
            "platform_parse_test",
            run_id="task-result-run",
            trigger="manual",
            platform="zhihu",
            content_id=123,
        )
        await record_task_run_error(
            "platform_parse_test",
            "task-result-run",
            "parse failed",
            url="https://example.com/post",
        )

        response = await client.get("/api/v1/background-tasks/runs/task-result-run")
        assert response.status_code == 200
        data = response.json()
        assert data["run_id"] == "task-result-run"
        assert data["task"] == "platform_parse_test"
        assert data["status"] == "error"
        assert data["platform"] == "zhihu"
        assert data["content_id"] == 123
        assert data["error"] == "parse failed"
        assert data["result"]["url"] == "https://example.com/post"

        missing = await client.get("/api/v1/background-tasks/runs/missing-run")
        assert missing.status_code == 404
        assert missing.json()["error_code"] == "background_task_run_not_found"

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
            assert status.json()["policies"]["duplicate_strategy"] in {"merge", "skip"}
            assert status.json()["policies"]["scope_strategy"] == "all_favorites"
            assert status.json()["policies"]["first_sync_strategy"] == "latest_page"
            assert status.json()["policies"]["unfavorite_strategy"] == "keep_local"
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
    async def test_favorites_sync_trigger_rejects_disabled_platform_by_default(
        self,
        client: AsyncClient,
    ):
        previous = getattr(app.state, "favorites_sync_task", None)
        app.state.favorites_sync_task = _DisabledFavoritesSyncTask()
        try:
            response = await client.post(
                "/api/v1/favorites-sync/sync",
                json={"platform": "zhihu"},
            )
            assert response.status_code == 409
            data = response.json()
            assert data["error_code"] == "favorites_platform_disabled"
            assert data["policy"]["allowed"] is False

            forced = await client.post(
                "/api/v1/favorites-sync/sync",
                json={"platform": "zhihu", "force": True},
            )
            assert forced.status_code == 202
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
    async def test_favorites_sync_retry_single_failed_item_records_run(
        self,
        client: AsyncClient,
        monkeypatch,
    ):
        async def fake_create_share(self, **kwargs):
            assert kwargs["url"] == "https://example.com/fail"
            assert kwargs["source_name"] == "favorites_sync:zhihu:retry"
            assert kwargs["client_context"]["source_run_id"] == "failed-run"
            return SimpleNamespace(id=123)

        monkeypatch.setattr(
            "app.services.content_service.ContentService.create_share",
            fake_create_share,
        )

        retry = await client.post(
            "/api/v1/favorites-sync/items/retry",
            json={
                "platform": "zhihu",
                "url": "https://example.com/fail",
                "title": "失败收藏",
                "item_id": "fav-1",
                "source_run_id": "failed-run",
            },
        )
        assert retry.status_code == 200
        data = retry.json()
        assert data["status"] == "success"
        assert data["run_id"]
        assert data["content_id"] == 123
        assert data["source_run_id"] == "failed-run"

        status = await client.get("/api/v1/favorites-sync/status")
        latest = next(
            run
            for run in status.json()["recent_runs"]
            if run["run_id"] == data["run_id"]
        )
        assert latest["trigger"] == "item_retry"
        assert latest["scope"] == "zhihu"
        assert latest["result"]["content_id"] == 123
        assert latest["result"]["url"] == "https://example.com/fail"

    @pytest.mark.asyncio
    async def test_favorites_sync_batch_retry_failed_items_records_run(
        self,
        client: AsyncClient,
        monkeypatch,
    ):
        async def fake_create_share(self, **kwargs):
            if kwargs["url"].endswith("/bad"):
                raise RuntimeError("still broken")
            return SimpleNamespace(id=456)

        monkeypatch.setattr(
            "app.services.content_service.ContentService.create_share",
            fake_create_share,
        )

        retry = await client.post(
            "/api/v1/favorites-sync/items/batch-retry",
            json={
                "platform": "zhihu",
                "source_run_id": "failed-run",
                "items": [
                    {"url": "https://example.com/good", "title": "成功收藏"},
                    {"url": "https://example.com/bad", "title": "失败收藏"},
                ],
            },
        )
        assert retry.status_code == 200
        data = retry.json()
        assert data["status"] == "partial_success"
        assert data["run_id"]
        assert data["imported"] == 1
        assert data["failed"] == 1

        status = await client.get("/api/v1/favorites-sync/status")
        latest = next(
            run
            for run in status.json()["recent_runs"]
            if run["run_id"] == data["run_id"]
        )
        assert latest["trigger"] == "item_batch_retry"
        assert latest["scope"] == "zhihu"
        assert latest["result"]["imported"] == 1
        assert latest["result"]["failed"] == 1
        assert latest["result"]["failed_items"][0]["url"] == "https://example.com/bad"

    @pytest.mark.asyncio
    async def test_favorites_sync_duplicate_skip_strategy_skips_existing_item(
        self,
        monkeypatch,
    ):
        async def fake_exists(session, url: str) -> bool:
            assert url == "https://example.com/existing"
            return True

        async def fail_create_share(self, **kwargs):
            raise AssertionError("duplicate skip should not import existing item")

        monkeypatch.setattr(
            FavoritesSyncTask,
            "_favorite_item_exists",
            staticmethod(fake_exists),
        )
        monkeypatch.setattr(
            "app.tasks.favorites_sync.ContentService.create_share",
            fail_create_share,
        )

        result = await FavoritesSyncTask(
            config_service=_FakeFavoritesConfigService()
        )._sync_platform(_FakeFavoritesFetcher())

        assert result["status"] == "success"
        assert result["imported"] == 0
        assert result["skipped"] == 1
        assert result["duplicate_skipped"] == 1
        assert result["duplicate_strategy"] == "skip"

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
        await record_task_run_started(
            "cookie_keepalive_zhihu",
            run_id="cookie-health-run",
            trigger="scheduled",
        )
        await record_task_run_success(
            "cookie_keepalive_zhihu",
            "cookie-health-run",
            ok=True,
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
            assert data["cookie_keepalive"]["enabled"] is True
            assert data["cookie_keepalive"]["recent_run"]["run_id"] == "cookie-health-run"
        finally:
            if previous is None:
                app.state._state.pop("favorites_sync_task", None)
            else:
                app.state.favorites_sync_task = previous

    @pytest.mark.asyncio
    async def test_ai_capabilities_report_user_facing_status(
        self,
        client: AsyncClient,
        monkeypatch,
    ):
        values = {
            "text_llm_api_key": "text-key",
            "vision_llm_api_key": "",
            "summary_api_key": "summary-key",
            "enable_auto_summary": False,
            "embedding_api_key": "embedding-key",
        }

        async def _setting_value(key: str, default=None):
            return values.get(key, default)

        async def _index_status(self, session):
            return {
                "indexed_total": 0,
                "parse_success_total": 3,
                "pending_total": 3,
                "failed_total": 0,
            }

        monkeypatch.setattr("app.routers.system._get_configured_setting", _setting_value)
        monkeypatch.setattr(
            "app.services.embedding_service.EmbeddingService.get_index_status",
            _index_status,
        )

        response = await client.get("/api/v1/ai/capabilities")
        assert response.status_code == 200
        capabilities = {
            item["key"]: item
            for item in response.json()["capabilities"]
        }

        assert capabilities["content_understanding"]["status"] == "partial"
        assert capabilities["text_llm"]["status"] == "available"
        assert capabilities["vision_llm"]["status"] == "unavailable"
        assert capabilities["discovery_patrol"]["status"] == "available"
        assert capabilities["discovery_patrol"]["details"]["ai_scoring_enabled"] is True
        assert capabilities["summary_generation"]["status"] == "disabled"
        assert capabilities["semantic_search"]["status"] == "pending"
        assert capabilities["agent"]["status"] == "available"
        assert capabilities["agent"]["details"]["agent_chat"] is True

    @pytest.mark.asyncio
    async def test_ai_connectivity_test_records_run_and_updates_capabilities(
        self,
        client: AsyncClient,
        monkeypatch,
    ):
        async def fake_connectivity(target: str):
            assert target == "agent_chat"
            return {
                "target": target,
                "response_present": True,
                "preview": "OK",
            }

        async def _setting_value(key: str, default=None):
            values = {
                "text_llm_api_key": "text-key",
                "vision_llm_api_key": "",
                "summary_api_key": "",
                "enable_auto_summary": False,
                "embedding_api_key": "",
            }
            return values.get(key, default)

        async def _index_status(self, session):
            return {
                "indexed_total": 0,
                "parse_success_total": 0,
                "pending_total": 0,
                "failed_total": 0,
            }

        monkeypatch.setattr("app.routers.system._run_ai_connectivity_target", fake_connectivity)
        monkeypatch.setattr("app.routers.system._get_configured_setting", _setting_value)
        monkeypatch.setattr(
            "app.services.embedding_service.EmbeddingService.get_index_status",
            _index_status,
        )

        response = await client.post(
            "/api/v1/ai/connectivity-test",
            json={"target": "agent"},
        )
        assert response.status_code == 200
        data = response.json()
        assert data["ok"] is True
        assert data["run_id"]
        assert data["target"] == "agent_chat"

        diagnostics = await client.get("/api/v1/background-tasks/diagnostics")
        latest = next(
            run
            for run in diagnostics.json()["recent_task_runs"]
            if run["run_id"] == data["run_id"]
        )
        assert latest["task"] == "ai_connectivity_test"
        assert latest["status"] == "success"
        assert latest["target"] == "agent_chat"
        assert latest["result"]["response_present"] is True

        capabilities_resp = await client.get("/api/v1/ai/capabilities")
        capabilities = {
            item["key"]: item
            for item in capabilities_resp.json()["capabilities"]
        }
        connectivity = capabilities["agent"]["details"]["connectivity"]
        assert connectivity["run_id"] == data["run_id"]
        assert connectivity["status"] == "success"

    @pytest.mark.asyncio
    async def test_ai_connectivity_test_reports_real_call_failure(
        self,
        client: AsyncClient,
        monkeypatch,
    ):
        async def fake_connectivity(target: str):
            raise RuntimeError("provider timeout")

        monkeypatch.setattr("app.routers.system._run_ai_connectivity_target", fake_connectivity)

        response = await client.post(
            "/api/v1/ai/connectivity-test",
            json={"target": "semantic_search"},
        )
        assert response.status_code == 200
        data = response.json()
        assert data["ok"] is False
        assert data["status"] == "error"
        assert data["target"] == "semantic_search"
        assert "provider timeout" in data["error"]

    @pytest.mark.asyncio
    async def test_platform_parse_test_records_run(
        self,
        client: AsyncClient,
        monkeypatch,
    ):
        async def fake_parse_test(platform: str, url: str):
            assert platform == "zhihu"
            assert url == "https://www.zhihu.com/question/1/answer/2"
            return {
                "platform": platform,
                "url": url,
                "detected_platform": "zhihu",
                "title": "解析测试内容",
                "content_type": "answer",
                "layout_type": "article",
                "author_name": "tester",
                "author_id": "tester-id",
                "author_avatar_url": None,
                "author_url": None,
                "cover_url": None,
                "media_urls": [],
                "media_count": 0,
                "body_length": 12,
                "published_at": None,
                "stats": {"like": 3},
                "source_tags": [],
                "context_data_keys": [],
                "rich_payload_keys": [],
                "archive_metadata_keys": [],
            }

        monkeypatch.setattr("app.routers.system._run_platform_parse_test", fake_parse_test)

        response = await client.post(
            "/api/v1/platform-health/parse-test",
            json={
                "platform": "zhihu",
                "url": "https://www.zhihu.com/question/1/answer/2",
            },
        )
        assert response.status_code == 200
        data = response.json()
        assert data["ok"] is True
        assert data["run_id"]
        assert data["title"] == "解析测试内容"
        assert data["author_name"] == "tester"
        assert data["stats"] == {"like": 3}

        diagnostics = await client.get("/api/v1/background-tasks/diagnostics")
        latest = next(
            run
            for run in diagnostics.json()["recent_task_runs"]
            if run["run_id"] == data["run_id"]
        )
        assert latest["task"] == "platform_parse_test"
        assert latest["status"] == "success"
        assert latest["platform"] == "zhihu"
        assert latest["result"]["title"] == "解析测试内容"

    @pytest.mark.asyncio
    async def test_platform_parse_test_rejects_platform_mismatch(
        self,
        client: AsyncClient,
        monkeypatch,
    ):
        async def fake_parse_test(platform: str, url: str):
            raise ValueError("url is detected as bilibili, not zhihu")

        monkeypatch.setattr("app.routers.system._run_platform_parse_test", fake_parse_test)

        response = await client.post(
            "/api/v1/platform-health/parse-test",
            json={
                "platform": "zhihu",
                "url": "https://www.bilibili.com/video/BV1xx411c7mD",
            },
        )
        assert response.status_code == 400
        assert "bilibili" in response.json()["detail"]
