"""
Tests for discovery sync and cleanup background tasks.
"""
from datetime import timedelta
from unittest.mock import AsyncMock, patch

import pytest

from app.adapters.discovery.base import DiscoveryItem
from app.core.time_utils import utcnow
from app.models import (
    Content,
    ContentStatus,
    DiscoverySource,
    DiscoverySourceKind,
    DiscoveryState,
    Platform,
)
from app.tasks.discovery_cleanup import DiscoveryCleanupTask
from app.tasks.discovery_sync import DiscoverySyncTask
from app.utils.url_utils import normalize_url_for_dedup


@pytest.fixture(autouse=True)
def mock_event_bus():
    with patch("app.core.events.event_bus.publish", new_callable=AsyncMock) as mock:
        yield mock


# ---------------------------------------------------------------------------
# DiscoverySyncTask tests
# ---------------------------------------------------------------------------

@pytest.mark.asyncio
async def test_sync_creates_content_from_rss(db_session):
    """Sync should create Content records with INGESTED state from RSS items."""
    source = DiscoverySource(
        kind=DiscoverySourceKind.RSS,
        name="Test RSS",
        enabled=True,
        config={"url": "https://example.com/feed.xml"},
        sync_interval_minutes=60,
    )
    db_session.add(source)
    await db_session.flush()

    fake_items = [
        DiscoveryItem(
            url="https://example.com/post-1",
            title="Post 1",
            content="Body 1",
            author="Alice",
            published_at=utcnow(),
            source_tags=["tech"],
        ),
        DiscoveryItem(
            url="https://example.com/post-2",
            title="Post 2",
            content="Body 2",
        ),
    ]

    task = DiscoverySyncTask()

    with patch(
        "app.tasks.discovery_sync.RSSDiscoveryScraper.fetch",
        new_callable=AsyncMock,
        return_value=(fake_items, "cursor-abc"),
    ), patch(
        "app.tasks.discovery_sync.PatrolService.score_pending",
        new_callable=AsyncMock,
        return_value=0,
    ), patch(
        "app.tasks.discovery_sync.get_setting_value",
        new_callable=AsyncMock,
        return_value=7,
    ):
        await task._sync_single_source(db_session, source)

    from sqlalchemy import select

    result = await db_session.execute(
        select(Content).where(Content.discovery_state == DiscoveryState.INGESTED)
    )
    contents = result.scalars().all()

    synced = [c for c in contents if c.title in ("Post 1", "Post 2")]
    assert len(synced) == 2
    assert synced[0].platform == Platform.UNIVERSAL
    assert synced[0].status == ContentStatus.UNPROCESSED


@pytest.mark.asyncio
async def test_sync_prefers_explicit_cover_url_over_first_media_url(db_session):
    """显式 cover_url 应优先于正文首图兜底。"""
    source = DiscoverySource(
        kind=DiscoverySourceKind.RSS,
        name="Cover Priority Test",
        enabled=True,
        config={"url": "https://example.com/feed.xml"},
    )
    db_session.add(source)
    await db_session.flush()

    fake_items = [
        DiscoveryItem(
            url="https://example.com/post-cover",
            title="Post Cover",
            cover_url="https://img.example.com/thumb.jpg",
            media_urls=["https://img.example.com/body.jpg"],
        )
    ]

    task = DiscoverySyncTask()

    with patch(
        "app.tasks.discovery_sync.RSSDiscoveryScraper.fetch",
        new_callable=AsyncMock,
        return_value=(fake_items, None),
    ), patch(
        "app.tasks.discovery_sync.PatrolService.score_pending",
        new_callable=AsyncMock,
        return_value=0,
    ), patch(
        "app.tasks.discovery_sync.get_setting_value",
        new_callable=AsyncMock,
        return_value=7,
    ):
        await task._sync_single_source(db_session, source)

    from sqlalchemy import select

    result = await db_session.execute(
        select(Content).where(
            Content.canonical_url == normalize_url_for_dedup("https://example.com/post-cover")
        )
    )
    content = result.scalar_one()
    assert content.cover_url == "https://img.example.com/thumb.jpg"
    assert content.media_urls == ["https://img.example.com/body.jpg"]


@pytest.mark.asyncio
async def test_sync_updates_cursor(db_session):
    """After sync, source.last_cursor should be updated."""
    source = DiscoverySource(
        kind=DiscoverySourceKind.RSS,
        name="Cursor Test",
        enabled=True,
        config={"url": "https://example.com/feed.xml"},
    )
    db_session.add(source)
    await db_session.flush()

    task = DiscoverySyncTask()

    with patch(
        "app.tasks.discovery_sync.RSSDiscoveryScraper.fetch",
        new_callable=AsyncMock,
        return_value=([], "new-cursor-123"),
    ), patch(
        "app.tasks.discovery_sync.get_setting_value",
        new_callable=AsyncMock,
        return_value=7,
    ):
        await task._sync_single_source(db_session, source)

    assert source.last_cursor == "new-cursor-123"
    assert source.last_sync_at is not None
    assert source.last_error is None


@pytest.mark.asyncio
async def test_sync_dedup_skips_existing(db_session):
    """If canonical_url already exists, the item should be skipped."""
    url = "https://example.com/dup-post"
    canonical = normalize_url_for_dedup(url)

    existing = Content(
        platform=Platform.UNIVERSAL,
        url=url,
        canonical_url=canonical,
        title="Existing",
        status=ContentStatus.UNPROCESSED,
    )
    db_session.add(existing)
    await db_session.flush()

    source = DiscoverySource(
        kind=DiscoverySourceKind.RSS,
        name="Dedup Test",
        enabled=True,
        config={"url": "https://example.com/feed.xml"},
    )
    db_session.add(source)
    await db_session.flush()

    fake_items = [
        DiscoveryItem(url=url, title="Duplicate"),
    ]

    task = DiscoverySyncTask()

    with patch(
        "app.tasks.discovery_sync.RSSDiscoveryScraper.fetch",
        new_callable=AsyncMock,
        return_value=(fake_items, None),
    ), patch(
        "app.tasks.discovery_sync.get_setting_value",
        new_callable=AsyncMock,
        return_value=7,
    ):
        await task._sync_single_source(db_session, source)

    from sqlalchemy import select, func

    count_result = await db_session.execute(
        select(func.count()).select_from(Content).where(Content.canonical_url == canonical)
    )
    assert count_result.scalar() == 1


@pytest.mark.asyncio
async def test_sync_dedup_backfills_missing_cover_from_explicit_rss_cover(db_session):
    """已有条目仅有首图兜底封面时，应被显式 RSS 封面覆盖修正。"""
    url = "https://example.com/rss-backfill"
    canonical = normalize_url_for_dedup(url)

    existing = Content(
        platform=Platform.UNIVERSAL,
        url=url,
        canonical_url=canonical,
        title="Existing",
        status=ContentStatus.UNPROCESSED,
        cover_url="https://img.example.com/placeholder.png",
        media_urls=["https://img.example.com/placeholder.png"],
    )
    db_session.add(existing)
    await db_session.flush()

    source = DiscoverySource(
        kind=DiscoverySourceKind.RSS,
        name="Dedup Cover Backfill Test",
        enabled=True,
        config={"url": "https://example.com/feed.xml"},
    )
    db_session.add(source)
    await db_session.flush()

    fake_items = [
        DiscoveryItem(
            url=url,
            title="Existing",
            cover_url="https://img.example.com/explicit-cover.jpg",
            media_urls=["https://img.example.com/body.jpg"],
        )
    ]

    task = DiscoverySyncTask()

    with patch(
        "app.tasks.discovery_sync.RSSDiscoveryScraper.fetch",
        new_callable=AsyncMock,
        return_value=(fake_items, None),
    ), patch(
        "app.tasks.discovery_sync.get_setting_value",
        new_callable=AsyncMock,
        return_value=7,
    ):
        await task._sync_single_source(db_session, source)

    db_session.expire_all()
    from sqlalchemy import select

    result = await db_session.execute(select(Content).where(Content.id == existing.id))
    updated = result.scalar_one()
    assert updated.cover_url == "https://img.example.com/explicit-cover.jpg"


@pytest.mark.asyncio
async def test_sync_dedup_handles_multiple_existing_rows(db_session):
    """Dedup should remain stable even if canonical_url has multiple rows."""
    url = "https://example.com/dup-multi"
    canonical = normalize_url_for_dedup(url)

    existing_universal = Content(
        platform=Platform.UNIVERSAL,
        url=url,
        canonical_url=canonical,
        title="Existing Universal",
        status=ContentStatus.UNPROCESSED,
    )
    existing_twitter = Content(
        platform=Platform.TWITTER,
        url=url,
        canonical_url=canonical,
        title="Existing Twitter",
        status=ContentStatus.UNPROCESSED,
    )
    db_session.add(existing_universal)
    db_session.add(existing_twitter)
    await db_session.flush()

    source = DiscoverySource(
        kind=DiscoverySourceKind.RSS,
        name="Dedup Multi Test",
        enabled=True,
        config={"url": "https://example.com/feed.xml"},
    )
    db_session.add(source)
    await db_session.flush()

    fake_items = [
        DiscoveryItem(url=url, title="Duplicate Multi"),
    ]

    task = DiscoverySyncTask()

    with patch(
        "app.tasks.discovery_sync.RSSDiscoveryScraper.fetch",
        new_callable=AsyncMock,
        return_value=(fake_items, None),
    ), patch(
        "app.tasks.discovery_sync.get_setting_value",
        new_callable=AsyncMock,
        return_value=7,
    ):
        await task._sync_single_source(db_session, source)

    from sqlalchemy import select, func

    count_result = await db_session.execute(
        select(func.count()).select_from(Content).where(Content.canonical_url == canonical)
    )
    assert count_result.scalar() == 2
    assert source.last_error is None


@pytest.mark.asyncio
async def test_sync_records_error(db_session):
    """If scraper raises, source.last_error should be set."""
    source = DiscoverySource(
        kind=DiscoverySourceKind.RSS,
        name="Error Test",
        enabled=True,
        config={"url": "https://example.com/feed.xml"},
    )
    db_session.add(source)
    await db_session.flush()

    task = DiscoverySyncTask()

    with patch(
        "app.tasks.discovery_sync.RSSDiscoveryScraper.fetch",
        new_callable=AsyncMock,
        side_effect=RuntimeError("Connection timeout"),
    ):
        await task._sync_single_source(db_session, source)

    assert source.last_error is not None
    assert "Connection timeout" in source.last_error
    assert source.last_sync_at is not None


@pytest.mark.asyncio
async def test_archive_discovery_media_rewrites_body_to_local_urls(db_session):
    """Discovery media archiving should rewrite body markdown image URLs to local://."""
    content = Content(
        platform=Platform.UNIVERSAL,
        url="https://example.com/post-localize",
        canonical_url="https://example.com/post-localize",
        title="Localize Body",
        body="![img](https://img.example.com/a.jpg)",
        media_urls=["https://img.example.com/a.jpg"],
        cover_url="https://img.example.com/a.jpg",
        status=ContentStatus.PARSE_SUCCESS,
        discovery_state=DiscoveryState.INGESTED,
    )
    db_session.add(content)
    await db_session.commit()
    await db_session.refresh(content)

    task = DiscoverySyncTask()

    async def _setting_side_effect(key, default=None):
        if key == "enable_archive_media_processing":
            return True
        if key == "archive_image_webp_quality":
            return 80
        if key == "archive_image_max_count":
            return None
        return default

    async def _store_images_side_effect(*, archive, storage, namespace, quality, max_images):
        archive["stored_images"] = [
            {
                "orig_url": "https://img.example.com/a.jpg",
                "key": "vaultstream/blobs/sha256/aa/bb/aabb.webp",
                "type": "image",
            }
        ]

    mock_storage = AsyncMock()
    mock_storage.ensure_bucket = AsyncMock()

    with patch(
        "app.tasks.discovery_sync.get_setting_value",
        new_callable=AsyncMock,
        side_effect=_setting_side_effect,
    ), patch(
        "app.tasks.discovery_sync.get_storage_backend",
        return_value=mock_storage,
    ), patch(
        "app.tasks.discovery_sync.store_archive_images_as_webp",
        new_callable=AsyncMock,
        side_effect=_store_images_side_effect,
    ):
        await task._archive_discovery_media(db_session, [content.id])

    await db_session.refresh(content)
    expected_local = "local://vaultstream/blobs/sha256/aa/bb/aabb.webp"
    assert content.media_urls == [expected_local]
    assert content.cover_url == expected_local
    assert expected_local in (content.body or "")


# ---------------------------------------------------------------------------
# DiscoveryCleanupTask tests
# ---------------------------------------------------------------------------

@pytest.mark.asyncio
async def test_cleanup_deletes_expired(db_session):
    """Expired IGNORED content should be hard-deleted."""
    content = Content(
        platform=Platform.UNIVERSAL,
        url="https://example.com/cleanup-1",
        canonical_url="https://example.com/cleanup-1",
        title="To Delete",
        status=ContentStatus.UNPROCESSED,
        discovery_state=DiscoveryState.IGNORED,
        expire_at=utcnow() - timedelta(hours=1),
    )
    db_session.add(content)
    await db_session.commit()
    content_id = content.id

    task = DiscoveryCleanupTask()
    await task._cleanup_expired()

    from sqlalchemy import select

    result = await db_session.execute(select(Content).where(Content.id == content_id))
    assert result.scalar_one_or_none() is None


@pytest.mark.asyncio
async def test_cleanup_marks_visible_as_expired(db_session):
    """VISIBLE content past expire_at should be marked EXPIRED."""
    content = Content(
        platform=Platform.UNIVERSAL,
        url="https://example.com/cleanup-2",
        canonical_url="https://example.com/cleanup-2",
        title="Visible Expired",
        status=ContentStatus.UNPROCESSED,
        discovery_state=DiscoveryState.VISIBLE,
        expire_at=utcnow() - timedelta(hours=1),
    )
    db_session.add(content)
    await db_session.commit()
    content_id = content.id

    task = DiscoveryCleanupTask()
    await task._cleanup_expired()

    db_session.expire_all()
    from sqlalchemy import select

    result = await db_session.execute(select(Content).where(Content.id == content_id))
    updated = result.scalar_one_or_none()
    # The update marks VISIBLE→EXPIRED, then delete catches EXPIRED items — so it's deleted.
    assert updated is None


@pytest.mark.asyncio
async def test_cleanup_preserves_promoted(db_session):
    """PROMOTED content should NOT be deleted even if expire_at has passed."""
    content = Content(
        platform=Platform.UNIVERSAL,
        url="https://example.com/cleanup-3",
        canonical_url="https://example.com/cleanup-3",
        title="Promoted Keep",
        status=ContentStatus.UNPROCESSED,
        discovery_state=DiscoveryState.PROMOTED,
        expire_at=utcnow() - timedelta(hours=1),
    )
    db_session.add(content)
    await db_session.commit()
    content_id = content.id

    task = DiscoveryCleanupTask()
    await task._cleanup_expired()

    db_session.expire_all()
    from sqlalchemy import select

    result = await db_session.execute(select(Content).where(Content.id == content_id))
    assert result.scalar_one_or_none() is not None
