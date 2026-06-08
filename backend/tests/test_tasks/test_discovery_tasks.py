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
from app.services.config_service import ArchiveMediaConfig
from app.tasks.discovery_cleanup import DiscoveryCleanupTask
from app.tasks.discovery_sync import DiscoverySyncTask
from app.utils.url_utils import normalize_url_for_dedup


@pytest.fixture(autouse=True)
def mock_event_bus():
    with patch("app.core.events.event_bus.publish", new_callable=AsyncMock) as mock:
        yield mock


@pytest.fixture(autouse=True)
def disable_background_embedding(monkeypatch):
    monkeypatch.setattr(
        "app.tasks.discovery_sync.PostIngestService.schedule_embedding_index",
        lambda self, content_id, *, source="post_ingest": None,
    )


def _patch_archive_config(
    monkeypatch,
    *,
    enabled: bool = True,
    images_enabled: bool = True,
    image_webp_quality: int = 80,
    image_max_count: int | None = None,
):
    async def _config(self):
        return ArchiveMediaConfig(
            enabled=enabled,
            images_enabled=enabled and images_enabled,
            videos_enabled=enabled,
            image_webp_quality=image_webp_quality,
            image_max_count=image_max_count,
            video_max_count=None,
            video_max_bytes=None,
        )

    monkeypatch.setattr(
        "app.tasks.discovery_sync.ConfigService.get_archive_media_config",
        _config,
    )


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
        "app.services.patrol_service.PatrolService.score_pending",
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
    assert synced[0].status == ContentStatus.PARSE_SUCCESS


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
        "app.services.patrol_service.PatrolService.score_pending",
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
    existing_id = existing.id

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

    result = await db_session.execute(select(Content).where(Content.id == existing_id))
    updated = result.scalar_one()
    assert updated.cover_url == "https://img.example.com/explicit-cover.jpg"


@pytest.mark.asyncio
async def test_sync_existing_parse_success_skips_post_ingest_when_no_enabled_work(db_session):
    url = "https://example.com/rediscover-no-work"
    canonical = normalize_url_for_dedup(url)
    existing = Content(
        platform=Platform.UNIVERSAL,
        url=url,
        canonical_url=canonical,
        title="Existing Parsed No Work",
        status=ContentStatus.PARSE_SUCCESS,
        summary=None,
        rich_payload={},
    )
    db_session.add(existing)
    await db_session.flush()

    source = DiscoverySource(
        kind=DiscoverySourceKind.RSS,
        name="Rediscover No Work",
        enabled=True,
        config={"url": "https://example.com/feed-no-work.xml"},
    )
    db_session.add(source)
    await db_session.flush()

    async def _setting_side_effect(key, default=None):
        if key == "enable_auto_summary":
            return False
        return default

    task = DiscoverySyncTask()

    with patch(
        "app.tasks.discovery_sync.RSSDiscoveryScraper.fetch",
        new_callable=AsyncMock,
        return_value=([DiscoveryItem(url=url, title="Duplicate")], None),
    ), patch(
        "app.tasks.discovery_sync.get_setting_value",
        new_callable=AsyncMock,
        side_effect=_setting_side_effect,
    ), patch(
        "app.tasks.discovery_sync.EmbeddingService.has_current_content_index",
        new_callable=AsyncMock,
        return_value=True,
    ), patch("app.tasks.discovery_sync.PostIngestService") as post_ingest_cls:
        await task._sync_single_source(db_session, source)

    post_ingest_cls.assert_not_called()


@pytest.mark.asyncio
async def test_sync_existing_parse_success_runs_only_missing_embedding(db_session):
    url = "https://example.com/rediscover-missing-embedding"
    canonical = normalize_url_for_dedup(url)
    existing = Content(
        platform=Platform.UNIVERSAL,
        url=url,
        canonical_url=canonical,
        title="Existing Missing Embedding",
        status=ContentStatus.PARSE_SUCCESS,
        summary=None,
        rich_payload={},
    )
    db_session.add(existing)
    await db_session.flush()
    existing_id = existing.id

    source = DiscoverySource(
        kind=DiscoverySourceKind.RSS,
        name="Rediscover Missing Embedding",
        enabled=True,
        config={"url": "https://example.com/feed-missing-embedding.xml"},
    )
    db_session.add(source)
    await db_session.flush()

    async def _setting_side_effect(key, default=None):
        if key == "enable_auto_summary":
            return False
        return default

    task = DiscoverySyncTask()

    with patch(
        "app.tasks.discovery_sync.RSSDiscoveryScraper.fetch",
        new_callable=AsyncMock,
        return_value=([DiscoveryItem(url=url, title="Duplicate")], None),
    ), patch(
        "app.tasks.discovery_sync.get_setting_value",
        new_callable=AsyncMock,
        side_effect=_setting_side_effect,
    ), patch(
        "app.tasks.discovery_sync.EmbeddingService.has_current_content_index",
        new_callable=AsyncMock,
        return_value=False,
    ), patch("app.tasks.discovery_sync.PostIngestService") as post_ingest_cls:
        pipeline = post_ingest_cls.return_value
        pipeline.run_for_content = AsyncMock()
        pipeline.score_discovery = AsyncMock()

        await task._sync_single_source(db_session, source)

    pipeline.run_for_content.assert_awaited_once()
    args, kwargs = pipeline.run_for_content.await_args
    assert args[1].id == existing_id
    assert kwargs["summary"] is False
    assert kwargs["embedding"] is True
    assert kwargs["distribution"] is False
    pipeline.score_discovery.assert_not_awaited()


@pytest.mark.asyncio
async def test_sync_existing_parse_success_runs_only_enabled_missing_summary(db_session):
    url = "https://example.com/rediscover-missing-summary"
    canonical = normalize_url_for_dedup(url)
    existing = Content(
        platform=Platform.UNIVERSAL,
        url=url,
        canonical_url=canonical,
        title="Existing Missing Summary",
        status=ContentStatus.PARSE_SUCCESS,
        summary=None,
        rich_payload={},
    )
    db_session.add(existing)
    await db_session.flush()
    existing_id = existing.id

    source = DiscoverySource(
        kind=DiscoverySourceKind.RSS,
        name="Rediscover Missing Summary",
        enabled=True,
        config={"url": "https://example.com/feed-missing-summary.xml"},
    )
    db_session.add(source)
    await db_session.flush()

    async def _setting_side_effect(key, default=None):
        if key == "enable_auto_summary":
            return True
        return default

    task = DiscoverySyncTask()

    with patch(
        "app.tasks.discovery_sync.RSSDiscoveryScraper.fetch",
        new_callable=AsyncMock,
        return_value=([DiscoveryItem(url=url, title="Duplicate")], None),
    ), patch(
        "app.tasks.discovery_sync.get_setting_value",
        new_callable=AsyncMock,
        side_effect=_setting_side_effect,
    ), patch(
        "app.tasks.discovery_sync.EmbeddingService.has_current_content_index",
        new_callable=AsyncMock,
        return_value=True,
    ), patch("app.tasks.discovery_sync.PostIngestService") as post_ingest_cls:
        pipeline = post_ingest_cls.return_value
        pipeline.run_for_content = AsyncMock()
        pipeline.score_discovery = AsyncMock()

        await task._sync_single_source(db_session, source)

    pipeline.run_for_content.assert_awaited_once()
    args, kwargs = pipeline.run_for_content.await_args
    assert args[1].id == existing_id
    assert kwargs["summary"] is True
    assert kwargs["embedding"] is False
    assert kwargs["distribution"] is False
    pipeline.score_discovery.assert_not_awaited()


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
async def test_archive_discovery_media_rewrites_body_to_local_urls(db_session, monkeypatch):
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
    _patch_archive_config(monkeypatch)

    with patch(
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
async def test_cleanup_deletes_expired(db_session, monkeypatch):
    """Expired IGNORED content should be hard-deleted."""
    monkeypatch.setattr(
        "app.tasks.discovery_cleanup.get_setting_value",
        AsyncMock(return_value="hard_delete"),
    )
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
async def test_cleanup_marks_visible_as_expired(db_session, monkeypatch):
    """VISIBLE content past expire_at should be marked EXPIRED."""
    monkeypatch.setattr(
        "app.tasks.discovery_cleanup.get_setting_value",
        AsyncMock(return_value="hard_delete"),
    )
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


@pytest.mark.asyncio
async def test_cleanup_expire_only_preserves_expired_candidates(db_session, monkeypatch):
    """expire_only should mark visible candidates expired without deleting them."""
    monkeypatch.setattr(
        "app.tasks.discovery_cleanup.get_setting_value",
        AsyncMock(return_value="expire_only"),
    )
    content = Content(
        platform=Platform.UNIVERSAL,
        url="https://example.com/cleanup-expire-only",
        canonical_url="https://example.com/cleanup-expire-only",
        title="Expire Only",
        status=ContentStatus.UNPROCESSED,
        discovery_state=DiscoveryState.VISIBLE,
        expire_at=utcnow() - timedelta(hours=1),
    )
    db_session.add(content)
    await db_session.commit()
    content_id = content.id

    task = DiscoveryCleanupTask()
    changed = await task._cleanup_expired()

    assert changed == 0
    db_session.expire_all()
    from sqlalchemy import select

    result = await db_session.execute(select(Content).where(Content.id == content_id))
    updated = result.scalar_one_or_none()
    assert updated is not None
    assert updated.discovery_state == DiscoveryState.EXPIRED


@pytest.mark.asyncio
async def test_cleanup_archive_soft_hides_expired_candidates(db_session, monkeypatch):
    """archive should set deleted_at/context metadata instead of hard-deleting."""
    monkeypatch.setattr(
        "app.tasks.discovery_cleanup.get_setting_value",
        AsyncMock(return_value="archive"),
    )
    content = Content(
        platform=Platform.UNIVERSAL,
        url="https://example.com/cleanup-archive",
        canonical_url="https://example.com/cleanup-archive",
        title="Archive Expired",
        status=ContentStatus.UNPROCESSED,
        discovery_state=DiscoveryState.IGNORED,
        expire_at=utcnow() - timedelta(hours=1),
        context_data={"existing": True},
    )
    db_session.add(content)
    await db_session.commit()
    content_id = content.id

    task = DiscoveryCleanupTask()
    changed = await task._cleanup_expired()

    assert changed >= 1
    db_session.expire_all()
    from sqlalchemy import select

    result = await db_session.execute(select(Content).where(Content.id == content_id))
    updated = result.scalar_one_or_none()
    assert updated is not None
    assert updated.deleted_at is not None
    assert updated.context_data["inbox_archived"] is True
