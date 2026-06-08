import asyncio
from datetime import datetime, timezone

import pytest
from httpx import AsyncClient

from app.adapters.discovery.base import DiscoveryItem
from app.main import app
from app.models import DiscoverySource, DiscoverySourceKind
from app.services.background_task_state import (
    record_task_run_started,
    record_task_run_success,
)


class _FakeDiscoverySyncTask:
    async def create_run(self, source, *, trigger: str) -> dict:
        source_kind = source.kind.value if hasattr(source.kind, "value") else str(source.kind)
        return await record_task_run_started(
            "discovery_sync",
            run_id="api-test-discovery-run",
            source_id=source.id,
            source_name=source.name,
            source_kind=source_kind,
            trigger=trigger,
        )

    async def sync_source_by_id(
        self,
        source_id: int,
        *,
        run_id: str | None = None,
        trigger: str = "manual",
        force: bool = False,
    ) -> None:
        await record_task_run_success(
            "discovery_sync",
            run_id or "api-test-discovery-run",
            source_id=source_id,
            trigger=trigger,
            ingested_count=0,
        )


class _FakeDiscoveryScraper:
    async def fetch(self, last_cursor=None):
        return (
            [
                DiscoveryItem(
                    url="https://example.test/post-1",
                    title="发现源候选 A",
                    author="tester",
                    published_at=datetime(2026, 6, 6, tzinfo=timezone.utc),
                    source_tags=["tech"],
                    media_urls=["https://example.test/a.png"],
                ),
                DiscoveryItem(
                    url="https://example.test/post-2",
                    title="发现源候选 B",
                ),
            ],
            "cursor-2",
        )


class TestDiscoverySourcesAPI:
    @pytest.mark.asyncio
    async def test_create_source_rejects_unimplemented_kind(self, client: AsyncClient):
        response = await client.post(
            "/api/v1/discovery/sources",
            json={
                "kind": "github",
                "name": "GitHub roadmap source",
                "enabled": True,
                "config": {"url": "https://github.com/trending"},
                "sync_interval_minutes": 60,
            },
        )

        assert response.status_code == 400
        data = response.json()
        assert data["error_code"] == "source_kind_not_supported"
        assert data["supported_kinds"] == ["rss", "telegram_channel"]

    @pytest.mark.asyncio
    async def test_create_source_allows_supported_rss_kind(self, client: AsyncClient):
        response = await client.post(
            "/api/v1/discovery/sources",
            json={
                "kind": "rss",
                "name": "API test RSS source",
                "enabled": True,
                "config": {"url": "https://example.com/feed.xml"},
                "sync_interval_minutes": 60,
            },
        )

        assert response.status_code == 201
        data = response.json()
        assert data["kind"] == "rss"
        assert data["name"] == "API test RSS source"
        assert data["config"]["url"] == "https://example.com/feed.xml"

    @pytest.mark.asyncio
    async def test_manual_sync_returns_run_id_and_diagnostics_lists_run(
        self,
        client: AsyncClient,
    ):
        create_response = await client.post(
            "/api/v1/discovery/sources",
            json={
                "kind": "rss",
                "name": "API test sync RSS source",
                "enabled": True,
                "config": {"url": "https://example.com/sync-feed.xml"},
                "sync_interval_minutes": 60,
            },
        )
        assert create_response.status_code == 201
        source_id = create_response.json()["id"]

        previous = getattr(app.state, "discovery_sync_task", None)
        app.state.discovery_sync_task = _FakeDiscoverySyncTask()
        try:
            sync_response = await client.post(f"/api/v1/discovery/sources/{source_id}/sync")
            assert sync_response.status_code == 202
            assert sync_response.json()["run_id"] == "api-test-discovery-run"
            assert sync_response.json()["source_id"] == source_id

            await asyncio.sleep(0)

            diagnostics = await client.get("/api/v1/background-tasks/diagnostics")
            assert diagnostics.status_code == 200
            runs = diagnostics.json()["recent_task_runs"]
            latest = next(
                run for run in runs if run["run_id"] == "api-test-discovery-run"
            )
            assert latest["task"] == "discovery_sync"
            assert latest["status"] == "success"
            assert latest["source_id"] == source_id
            assert latest["trigger"] == "manual"
        finally:
            if previous is None:
                app.state._state.pop("discovery_sync_task", None)
            else:
                app.state.discovery_sync_task = previous

    @pytest.mark.asyncio
    async def test_manual_sync_rejects_disabled_source_without_force(
        self,
        client: AsyncClient,
    ):
        create_response = await client.post(
            "/api/v1/discovery/sources",
            json={
                "kind": "rss",
                "name": "API test disabled sync RSS source",
                "enabled": False,
                "config": {"url": "https://example.com/disabled-feed.xml"},
                "sync_interval_minutes": 60,
            },
        )
        assert create_response.status_code == 201
        source_id = create_response.json()["id"]

        previous = getattr(app.state, "discovery_sync_task", None)
        app.state.discovery_sync_task = _FakeDiscoverySyncTask()
        try:
            blocked = await client.post(f"/api/v1/discovery/sources/{source_id}/sync")
            assert blocked.status_code == 409
            data = blocked.json()
            assert data["error_code"] == "discovery_source_disabled"
            assert data["policy"]["allowed"] is False

            forced = await client.post(
                f"/api/v1/discovery/sources/{source_id}/sync?force=true"
            )
            assert forced.status_code == 202
            assert forced.json()["run_id"] == "api-test-discovery-run"
        finally:
            if previous is None:
                app.state._state.pop("discovery_sync_task", None)
            else:
                app.state.discovery_sync_task = previous

    @pytest.mark.asyncio
    async def test_quality_test_records_run(
        self,
        client: AsyncClient,
        db_session,
        monkeypatch,
    ):
        source = DiscoverySource(
            kind=DiscoverySourceKind.RSS,
            name="quality-test-rss",
            enabled=True,
            config={"url": "https://example.test/feed.xml"},
            sync_interval_minutes=60,
        )
        db_session.add(source)
        await db_session.commit()
        await db_session.refresh(source)

        def _fake_scraper(self, tested_source):
            assert tested_source.id == source.id
            return _FakeDiscoveryScraper()

        monkeypatch.setattr(
            "app.tasks.discovery_sync.DiscoverySyncTask._get_scraper",
            _fake_scraper,
        )

        response = await client.post(f"/api/v1/discovery/sources/{source.id}/test")
        assert response.status_code == 200
        data = response.json()
        assert data["ok"] is True
        assert data["status"] == "ok"
        assert data["item_count"] == 2
        assert data["sample_count"] == 2
        assert data["samples"][0]["title"] == "发现源候选 A"
        assert data["cursor_available"] is True

        diagnostics = await client.get("/api/v1/background-tasks/diagnostics")
        latest = next(
            run
            for run in diagnostics.json()["recent_task_runs"]
            if run["run_id"] == data["run_id"]
        )
        assert latest["task"] == "discovery_source_test"
        assert latest["status"] == "success"
        assert latest["source_id"] == source.id
        assert latest["result"]["item_count"] == 2
