"""
Discovery API Tests
"""
import pytest
from httpx import AsyncClient
from sqlalchemy.ext.asyncio import AsyncSession

from app.models import Content, DiscoveryState, Platform, ContentStatus
from app.core.time_utils import utcnow


class TestDiscoveryAPI:
    """Test suite for discovery endpoints"""

    # ── Items ──────────────────────────────────────────────────────

    @pytest.mark.asyncio
    async def test_list_discovery_items_empty(self, client: AsyncClient):
        """GET /discovery/items returns empty list when no discovery items exist"""
        response = await client.get("/api/v1/discovery/items")
        assert response.status_code == 200
        data = response.json()
        assert "items" in data
        assert "total" in data
        assert isinstance(data["items"], list)

    @pytest.mark.asyncio
    async def test_promote_item(self, client: AsyncClient, db_session: AsyncSession):
        """PATCH /discovery/items/{id} — promote sets state and promoted_at"""
        item = Content(
            platform=Platform.UNIVERSAL,
            url="https://example.com/discover-promote",
            status=ContentStatus.PARSE_SUCCESS,
            discovery_state=DiscoveryState.VISIBLE,
            source_type="rss",
            title="Promote Test",
        )
        db_session.add(item)
        await db_session.commit()
        await db_session.refresh(item)

        response = await client.patch(
            f"/api/v1/discovery/items/{item.id}",
            json={"state": "promoted"},
        )
        assert response.status_code == 200
        data = response.json()
        assert data["discovery_state"] == DiscoveryState.PROMOTED.value

    @pytest.mark.asyncio
    async def test_promote_non_discovery_item_returns_404(self, client: AsyncClient, db_session: AsyncSession):
        """PATCH should not mutate main-library items (discovery_state is null)."""
        item = Content(
            platform=Platform.UNIVERSAL,
            url="https://example.com/main-lib-only",
            status=ContentStatus.PARSE_SUCCESS,
            source_type="user_submit",
            title="Main Library",
        )
        db_session.add(item)
        await db_session.commit()
        await db_session.refresh(item)

        response = await client.patch(
            f"/api/v1/discovery/items/{item.id}",
            json={"state": "promoted"},
        )
        assert response.status_code == 404

    @pytest.mark.asyncio
    async def test_bulk_action(self, client: AsyncClient, db_session: AsyncSession):
        """POST /discovery/items/bulk-action — bulk ignore"""
        items = []
        for i in range(3):
            c = Content(
                platform=Platform.UNIVERSAL,
                url=f"https://example.com/bulk-{i}",
                status=ContentStatus.PARSE_SUCCESS,
                discovery_state=DiscoveryState.VISIBLE,
                source_type="hackernews",
                title=f"Bulk {i}",
            )
            db_session.add(c)
            items.append(c)
        await db_session.commit()
        for c in items:
            await db_session.refresh(c)

        ids = [c.id for c in items]
        response = await client.post(
            "/api/v1/discovery/items/bulk-action",
            json={"ids": ids, "action": "ignore"},
        )
        assert response.status_code == 200
        assert response.json()["updated"] == 3

    @pytest.mark.asyncio
    async def test_bulk_action_only_updates_discovery_items(self, client: AsyncClient, db_session: AsyncSession):
        """Bulk action must ignore non-discovery records."""
        discovery_item = Content(
            platform=Platform.UNIVERSAL,
            url="https://example.com/bulk-discovery",
            status=ContentStatus.PARSE_SUCCESS,
            discovery_state=DiscoveryState.VISIBLE,
            source_type="rss",
            title="Discovery Item",
        )
        main_item = Content(
            platform=Platform.UNIVERSAL,
            url="https://example.com/bulk-main",
            status=ContentStatus.PARSE_SUCCESS,
            discovery_state=None,
            source_type="user_submit",
            title="Main Item",
        )
        db_session.add(discovery_item)
        db_session.add(main_item)
        await db_session.commit()
        await db_session.refresh(discovery_item)
        await db_session.refresh(main_item)

        response = await client.post(
            "/api/v1/discovery/items/bulk-action",
            json={"ids": [discovery_item.id, main_item.id], "action": "ignore"},
        )
        assert response.status_code == 200
        assert response.json()["updated"] == 1

        await db_session.refresh(discovery_item)
        await db_session.refresh(main_item)
        assert discovery_item.discovery_state == DiscoveryState.IGNORED
        assert main_item.discovery_state is None

    @pytest.mark.asyncio
    async def test_list_discovery_items_tag_filter(self, client: AsyncClient, db_session: AsyncSession):
        """tag query param should filter by JSON tag arrays."""
        matched = Content(
            platform=Platform.UNIVERSAL,
            url="https://example.com/tag-matched",
            status=ContentStatus.PARSE_SUCCESS,
            discovery_state=DiscoveryState.VISIBLE,
            source_type="rss",
            title="Tag Filter Matched",
            ai_tags=["ai", "ml"],
        )
        unmatched = Content(
            platform=Platform.UNIVERSAL,
            url="https://example.com/tag-unmatched",
            status=ContentStatus.PARSE_SUCCESS,
            discovery_state=DiscoveryState.VISIBLE,
            source_type="rss",
            title="Tag Filter Unmatched",
            ai_tags=["database"],
        )
        db_session.add(matched)
        db_session.add(unmatched)
        await db_session.commit()

        response = await client.get(
            "/api/v1/discovery/items",
            params={"tag": "ai", "q": "Tag Filter"},
        )
        assert response.status_code == 200

        items = response.json()["items"]
        titles = [item["title"] for item in items]
        assert "Tag Filter Matched" in titles
        assert "Tag Filter Unmatched" not in titles

    # ── Sources ────────────────────────────────────────────────────

    @pytest.mark.asyncio
    async def test_create_and_list_sources(self, client: AsyncClient):
        """POST then GET /discovery/sources"""
        payload = {
            "kind": "rss",
            "name": "Test RSS Feed",
            "enabled": True,
            "config": {"url": "https://example.com/feed.xml"},
            "sync_interval_minutes": 30,
        }
        create_resp = await client.post("/api/v1/discovery/sources", json=payload)
        assert create_resp.status_code == 201
        created = create_resp.json()
        assert created["name"] == "Test RSS Feed"
        assert created["kind"] == "rss"

        list_resp = await client.get("/api/v1/discovery/sources")
        assert list_resp.status_code == 200
        sources = list_resp.json()
        assert any(s["id"] == created["id"] for s in sources)

    @pytest.mark.asyncio
    async def test_create_source_invalid_kind_returns_422(self, client: AsyncClient):
        """Invalid source kind must be rejected at request validation level."""
        payload = {
            "kind": "invalid_kind",
            "name": "Bad Source",
            "enabled": True,
            "config": {"url": "https://example.com/feed.xml"},
            "sync_interval_minutes": 30,
        }
        create_resp = await client.post("/api/v1/discovery/sources", json=payload)
        assert create_resp.status_code == 422

    @pytest.mark.asyncio
    async def test_get_source_detail(self, client: AsyncClient):
        """GET /discovery/sources/{id}"""
        create_resp = await client.post(
            "/api/v1/discovery/sources",
            json={"kind": "hackernews", "name": "HN Source"},
        )
        sid = create_resp.json()["id"]

        detail_resp = await client.get(f"/api/v1/discovery/sources/{sid}")
        assert detail_resp.status_code == 200
        assert detail_resp.json()["name"] == "HN Source"

    @pytest.mark.asyncio
    async def test_update_source(self, client: AsyncClient):
        """PUT /discovery/sources/{id}"""
        create_resp = await client.post(
            "/api/v1/discovery/sources",
            json={"kind": "reddit", "name": "Reddit Source"},
        )
        sid = create_resp.json()["id"]

        update_resp = await client.put(
            f"/api/v1/discovery/sources/{sid}",
            json={"name": "Updated Reddit", "sync_interval_minutes": 120},
        )
        assert update_resp.status_code == 200
        assert update_resp.json()["name"] == "Updated Reddit"
        assert update_resp.json()["sync_interval_minutes"] == 120

    @pytest.mark.asyncio
    async def test_delete_source(self, client: AsyncClient):
        """DELETE /discovery/sources/{id}"""
        create_resp = await client.post(
            "/api/v1/discovery/sources",
            json={"kind": "github", "name": "GitHub Source"},
        )
        sid = create_resp.json()["id"]

        del_resp = await client.delete(f"/api/v1/discovery/sources/{sid}")
        assert del_resp.status_code == 200
        assert del_resp.json()["success"] is True

        get_resp = await client.get(f"/api/v1/discovery/sources/{sid}")
        assert get_resp.status_code == 404

    # ── Settings ───────────────────────────────────────────────────

    @pytest.mark.asyncio
    async def test_get_discovery_settings(self, client: AsyncClient):
        """GET /discovery/settings returns defaults"""
        response = await client.get("/api/v1/discovery/settings")
        assert response.status_code == 200
        data = response.json()
        assert "interest_profile" in data
        assert "score_threshold" in data
        assert "retention_days" in data

    @pytest.mark.asyncio
    async def test_update_discovery_settings(self, client: AsyncClient):
        """PATCH /discovery/settings"""
        response = await client.patch(
            "/api/v1/discovery/settings",
            json={"score_threshold": 8.0, "retention_days": 14},
        )
        assert response.status_code == 200
        data = response.json()
        assert data["score_threshold"] == 8.0
        assert data["retention_days"] == 14

    # ── Stats ──────────────────────────────────────────────────────

    @pytest.mark.asyncio
    async def test_discovery_stats(self, client: AsyncClient, db_session: AsyncSession):
        """GET /discovery/stats"""
        item = Content(
            platform=Platform.UNIVERSAL,
            url="https://example.com/stats-visible",
            status=ContentStatus.PARSE_SUCCESS,
            discovery_state=DiscoveryState.VISIBLE,
            source_type="rss",
            title="Stats Item",
            discovered_at=utcnow(),
        )
        db_session.add(item)
        await db_session.commit()

        response = await client.get("/api/v1/discovery/stats")
        assert response.status_code == 200
        data = response.json()
        assert "total" in data
        assert "by_state" in data
        assert "by_source" in data
        assert "visible" in data["by_state"]
        assert "DiscoveryState.VISIBLE" not in data["by_state"]
        assert "rss" in data["by_source"]
