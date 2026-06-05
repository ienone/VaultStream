import pytest

from app.main import app


class FakeFavoritesSyncTask:
    def get_supported_platforms(self) -> list[str]:
        return ["zhihu", "twitter"]

    async def preview_platform_by_name(self, platform: str) -> dict:
        return {
            "platform": platform,
            "status": "success",
            "authenticated": True,
            "max_items": 50,
            "cursor_present": True,
            "fetched": 3,
            "unique": 2,
            "existing": 1,
            "estimated_new": 1,
            "skipped": 1,
            "next_cursor_available": True,
            "items": [
                {
                    "url": f"https://example.test/{platform}/1",
                    "title": "Item 1",
                    "exists": False,
                }
            ],
        }

    async def preview_all_platforms(self) -> dict:
        previews = [
            await self.preview_platform_by_name("zhihu"),
            await self.preview_platform_by_name("twitter"),
        ]
        return {
            "platform": "all",
            "status": "success",
            "fetched": sum(item["fetched"] for item in previews),
            "unique": sum(item["unique"] for item in previews),
            "existing": sum(item["existing"] for item in previews),
            "estimated_new": sum(item["estimated_new"] for item in previews),
            "skipped": sum(item["skipped"] for item in previews),
            "platforms": previews,
        }


@pytest.fixture
def fake_favorites_sync_task():
    previous = getattr(app.state, "favorites_sync_task", None)
    app.state.favorites_sync_task = FakeFavoritesSyncTask()
    yield
    app.state.favorites_sync_task = previous


@pytest.mark.asyncio
async def test_preview_favorites_sync_platform(client, fake_favorites_sync_task):
    response = await client.post(
        "/api/v1/favorites-sync/preview",
        json={"platform": "zhihu"},
    )

    assert response.status_code == 200
    data = response.json()
    assert data["platform"] == "zhihu"
    assert data["fetched"] == 3
    assert data["unique"] == 2
    assert data["existing"] == 1
    assert data["estimated_new"] == 1
    assert data["skipped"] == 1
    assert data["platforms"][0]["cursor_present"] is True
    assert data["platforms"][0]["items"][0]["exists"] is False


@pytest.mark.asyncio
async def test_preview_favorites_sync_all_platforms(client, fake_favorites_sync_task):
    response = await client.post("/api/v1/favorites-sync/preview", json={})

    assert response.status_code == 200
    data = response.json()
    assert data["platform"] == "all"
    assert data["fetched"] == 6
    assert data["estimated_new"] == 2
    assert [item["platform"] for item in data["platforms"]] == ["zhihu", "twitter"]


@pytest.mark.asyncio
async def test_preview_favorites_sync_rejects_unknown_platform(
    client,
    fake_favorites_sync_task,
):
    response = await client.post(
        "/api/v1/favorites-sync/preview",
        json={"platform": "unknown"},
    )

    assert response.status_code == 400
    assert "unsupported_platform" in str(response.json())
