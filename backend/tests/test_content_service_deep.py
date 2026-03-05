import pytest
import asyncio
from unittest.mock import AsyncMock, patch, MagicMock
from sqlalchemy.exc import IntegrityError
from sqlalchemy import select
from app.services.content_service import ContentService
from app.models.content import Content, ContentStatus, Platform
from app.models.base import Base
from app.core.events import EventBus
from sqlalchemy.ext.asyncio import create_async_engine, AsyncSession
from sqlalchemy.orm import sessionmaker

# Set up a shared engine for multi-session testing
engine = create_async_engine("sqlite+aiosqlite:///:memory:")
AsyncSessionLocal = sessionmaker(engine, class_=AsyncSession, expire_on_commit=False)

@pytest.fixture(autouse=True)
async def init_db():
    async with engine.begin() as conn:
        await conn.run_sync(Base.metadata.create_all)
    yield
    async with engine.begin() as conn:
        await conn.run_sync(Base.metadata.drop_all)

@pytest.fixture
async def db_session():
    async with AsyncSessionLocal() as session:
        # Patch EventBus to avoid missing table errors during service calls
        with patch("app.core.events.AsyncSessionLocal", return_value=session):
            await EventBus._ensure_event_table()
        yield session

@pytest.mark.asyncio
async def test_create_share_real_concurrent_conflict(db_session):
    """
    Test REAL concurrent conflict using two sessions.
    This avoids Mock side effects and tests the actual database-triggered logic.
    """
    url = "https://www.bilibili.com/video/BV1conflict"
    platform = "bilibili"
    
    # 1. Session A: Create and commit a record
    async with AsyncSessionLocal() as session_a:
        c1 = Content(platform=platform, url=url, canonical_url=url, tags=["tag_from_a"])
        session_a.add(c1)
        await session_a.commit()

    # 2. Session B: Run service.create_share which should hit the conflict and merge
    # We use our main db_session fixture as Session B
    service = ContentService(db_session)
    
    with patch("app.services.content_service.task_queue", AsyncMock()):
        with patch("app.services.content_service.event_bus", AsyncMock()):
            with patch("app.adapters.AdapterFactory.detect_platform", return_value=platform):
                mock_adapter = MagicMock()
                mock_adapter.clean_url = AsyncMock(return_value=url)
                with patch("app.adapters.AdapterFactory.create", return_value=mock_adapter):
                    
                    # This call will: 
                    # - Find nothing (due to read committed isolation / sqlite quirk) OR
                    # - Try to insert and fail with REAL IntegrityError
                    result = await service.create_share(url, tags=["tag_from_b"])
                    
                    # Verify result contains merged tags
                    assert "tag_from_a" in result.tags
                    assert "tag_from_b" in result.tags

@pytest.mark.asyncio
async def test_update_content_reset_trigger_reparse(db_session):
    service = ContentService(db_session)
    c = Content(platform="zhihu", url="u1", canonical_url="u1", status=ContentStatus.PARSE_SUCCESS)
    db_session.add(c)
    await db_session.commit()
    await db_session.refresh(c)

    with patch("app.services.content_service.task_queue.enqueue", AsyncMock()) as mock_enqueue:
        await service.update_content(c.id, {"status": ContentStatus.UNPROCESSED})
        mock_enqueue.assert_called_once()

@pytest.mark.asyncio
async def test_create_share_incremental_tags(db_session):
    service = ContentService(db_session)
    url = "https://www.zhihu.com/question/123"
    await service.create_share(url, tags=["ai"])
    content = await service.create_share(url, tags=["tech"])
    assert set(content.tags) == {"ai", "tech"}


# ─── New tests for improved coverage ───────────────────────────────────────────


@pytest.mark.asyncio
async def test_create_share_unsupported_platform(db_session):
    """ValueError for unsupported URL"""
    service = ContentService(db_session)
    with patch("app.adapters.AdapterFactory.detect_platform", return_value=None):
        with pytest.raises(ValueError, match="Unsupported platform URL"):
            await service.create_share("https://unknown-site.com/page")


@pytest.mark.asyncio
async def test_create_share_updates_layout_override(db_session):
    """Existing content gets layout_type_override updated"""
    from app.models.base import LayoutType
    service = ContentService(db_session)
    url = "https://www.bilibili.com/video/BVlayout"
    platform = "bilibili"

    # Create initial content without layout override
    c = Content(platform=platform, url=url, canonical_url=url, tags=[])
    db_session.add(c)
    await db_session.commit()

    with patch("app.services.content_service.task_queue", AsyncMock()):
        with patch("app.services.content_service.event_bus", AsyncMock()):
            with patch("app.adapters.AdapterFactory.detect_platform", return_value=platform):
                mock_adapter = MagicMock()
                mock_adapter.clean_url = AsyncMock(return_value=url)
                with patch("app.adapters.AdapterFactory.create", return_value=mock_adapter):
                    result = await service.create_share(url, layout_type_override=LayoutType.ARTICLE.value)
                    assert result.layout_type_override == LayoutType.ARTICLE.value


@pytest.mark.asyncio
async def test_create_share_reenqueue_parse_failed(db_session):
    """PARSE_FAILED content gets re-enqueued"""
    service = ContentService(db_session)
    url = "https://www.bilibili.com/video/BVfailed"
    platform = "bilibili"

    c = Content(platform=platform, url=url, canonical_url=url, tags=[], status=ContentStatus.PARSE_FAILED)
    db_session.add(c)
    await db_session.commit()

    with patch("app.services.content_service.task_queue", AsyncMock()) as mock_tq:
        with patch("app.services.content_service.event_bus", AsyncMock()):
            with patch("app.adapters.AdapterFactory.detect_platform", return_value=platform):
                mock_adapter = MagicMock()
                mock_adapter.clean_url = AsyncMock(return_value=url)
                with patch("app.adapters.AdapterFactory.create", return_value=mock_adapter):
                    result = await service.create_share(url, tags=["retry"])
                    assert result.status == ContentStatus.PARSE_FAILED
                    mock_tq.enqueue.assert_called_once()


@pytest.mark.asyncio
async def test_update_content_not_found(db_session):
    """ValueError when content_id doesn't exist"""
    service = ContentService(db_session)
    with patch("app.services.content_service.task_queue", AsyncMock()):
        with patch("app.services.content_service.event_bus", AsyncMock()):
            with pytest.raises(ValueError, match="Content not found"):
                await service.update_content(99999, {"title": "nope"})


@pytest.mark.asyncio
async def test_update_content_cover_url_triggers_color_extract(db_session):
    """cover_url change calls extract_cover_color"""
    service = ContentService(db_session)
    c = Content(platform="zhihu", url="u_cover", canonical_url="u_cover")
    db_session.add(c)
    await db_session.commit()
    await db_session.refresh(c)

    with patch("app.services.content_service.task_queue", AsyncMock()):
        with patch("app.services.content_service.event_bus", AsyncMock()):
            with patch("app.media.color.extract_cover_color", AsyncMock(return_value="#FF0000")) as mock_color:
                result = await service.update_content(c.id, {"cover_url": "https://img.example.com/cover.jpg"})
                mock_color.assert_called_once_with("https://img.example.com/cover.jpg")
                assert result.cover_color == "#FF0000"
                assert result.cover_url == "https://img.example.com/cover.jpg"


@pytest.mark.asyncio
async def test_update_content_generic_field(db_session):
    """setattr path for generic fields like title"""
    service = ContentService(db_session)
    c = Content(platform="zhihu", url="u_gen", canonical_url="u_gen")
    db_session.add(c)
    await db_session.commit()
    await db_session.refresh(c)

    with patch("app.services.content_service.task_queue", AsyncMock()):
        with patch("app.services.content_service.event_bus", AsyncMock()):
            result = await service.update_content(c.id, {"title": "New Title", "body": "New Body"})
            assert result.title == "New Title"
            assert result.body == "New Body"


def test_extract_local_key():
    """_extract_local_key helper"""
    assert ContentService._extract_local_key("local://media/img.png") == "media/img.png"
    assert ContentService._extract_local_key("https://example.com/img.png") is None
    assert ContentService._extract_local_key(None) is None
    assert ContentService._extract_local_key("") is None


def test_collect_local_keys_from_json():
    """Recursive JSON scanning for local:// URLs"""
    keys: set[str] = set()
    ContentService._collect_local_keys_from_json("local://a/b.png", keys)
    assert "a/b.png" in keys

    keys.clear()
    ContentService._collect_local_keys_from_json({"img": "local://c/d.jpg", "other": "https://x.com"}, keys)
    assert keys == {"c/d.jpg"}

    keys.clear()
    ContentService._collect_local_keys_from_json(["local://e/f.mp4", "not-local"], keys)
    assert keys == {"e/f.mp4"}

    keys.clear()
    nested = {"a": [{"b": "local://nested/file.png"}]}
    ContentService._collect_local_keys_from_json(nested, keys)
    assert keys == {"nested/file.png"}

    # Non-string, non-dict, non-list value (e.g. int) should be a no-op
    keys.clear()
    ContentService._collect_local_keys_from_json(12345, keys)
    assert keys == set()

    # None value
    keys.clear()
    ContentService._collect_local_keys_from_json(None, keys)
    assert keys == set()


def test_collect_local_media_keys():
    """All field coverage for local media key collection"""
    c = Content(
        platform="zhihu",
        url="u_media",
        canonical_url="u_media",
        cover_url="local://covers/c1.jpg",
        author_avatar_url="local://avatars/a1.jpg",
        media_urls=["local://media/m1.mp4", "https://cdn.example.com/m2.mp4"],
        context_data={"thumb": "local://ctx/t1.png"},
        rich_payload=["local://rich/r1.jpg"],
        archive_metadata={"file": "local://arch/a1.zip"},
        body="See local://body/b1.png for details",
    )
    keys = ContentService._collect_local_media_keys(c)
    expected = {"covers/c1.jpg", "avatars/a1.jpg", "media/m1.mp4", "ctx/t1.png", "rich/r1.jpg", "arch/a1.zip", "body/b1.png"}
    assert set(keys) == expected


@pytest.mark.asyncio
async def test_delete_content_with_media(db_session):
    """Delete content + local media files"""
    service = ContentService(db_session)
    c = Content(
        platform="zhihu",
        url="u_del",
        canonical_url="u_del",
        cover_url="local://covers/del.jpg",
        media_urls=[],
    )
    db_session.add(c)
    await db_session.commit()
    await db_session.refresh(c)
    content_id = c.id

    mock_storage = AsyncMock()
    with patch("app.services.content_service.event_bus", AsyncMock()):
        with patch("app.adapters.storage.get_storage_backend", return_value=mock_storage):
            result = await service.delete_content(content_id)
            assert result["status"] == "deleted"
            assert result["content_id"] == content_id
            mock_storage.delete.assert_called_once_with(key="covers/del.jpg")


@pytest.mark.asyncio
async def test_delete_content_not_found(db_session):
    """ValueError when content_id doesn't exist"""
    service = ContentService(db_session)
    with pytest.raises(ValueError, match="Content not found"):
        await service.delete_content(99999)


@pytest.mark.asyncio
async def test_review_card_approve(db_session):
    """Approve sets APPROVED and triggers distribution"""
    from app.models.base import ReviewStatus
    service = ContentService(db_session)
    c = Content(platform="zhihu", url="u_approve", canonical_url="u_approve")
    db_session.add(c)
    await db_session.commit()
    await db_session.refresh(c)

    with patch("app.services.distribution.enqueue_content_background", new_callable=AsyncMock) as mock_dist:
        result = await service.review_card(c.id, "approve", reviewed_by="admin")
        assert result["review_status"] == ReviewStatus.APPROVED.value
        mock_dist.assert_called_once_with(c.id)


@pytest.mark.asyncio
async def test_review_card_reject(db_session):
    """Reject sets REJECTED, no distribution triggered"""
    from app.models.base import ReviewStatus
    service = ContentService(db_session)
    c = Content(platform="zhihu", url="u_reject", canonical_url="u_reject")
    db_session.add(c)
    await db_session.commit()
    await db_session.refresh(c)

    with patch("app.services.distribution.enqueue_content_background", new_callable=AsyncMock) as mock_dist:
        result = await service.review_card(c.id, "reject", note="bad content")
        assert result["review_status"] == ReviewStatus.REJECTED.value
        mock_dist.assert_not_called()


@pytest.mark.asyncio
async def test_review_card_invalid_action(db_session):
    """ValueError for invalid action"""
    service = ContentService(db_session)
    with pytest.raises(ValueError, match="Invalid action"):
        await service.review_card(1, "maybe")


@pytest.mark.asyncio
async def test_batch_review_cards(db_session):
    """Batch approve multiple cards"""
    from app.models.base import ReviewStatus
    service = ContentService(db_session)
    c1 = Content(platform="zhihu", url="u_b1", canonical_url="u_b1")
    c2 = Content(platform="zhihu", url="u_b2", canonical_url="u_b2")
    db_session.add_all([c1, c2])
    await db_session.commit()
    await db_session.refresh(c1)
    await db_session.refresh(c2)

    with patch("app.services.distribution.enqueue_content_background", new_callable=AsyncMock) as mock_dist:
        result = await service.batch_review_cards([c1.id, c2.id], "approve", reviewed_by="admin")
        assert result["updated"] == 2
        assert result["action"] == "approve"
        assert mock_dist.call_count == 2


@pytest.mark.asyncio
async def test_batch_review_cards_no_cards(db_session):
    """ValueError when no cards found"""
    service = ContentService(db_session)
    with pytest.raises(ValueError, match="No cards found"):
        await service.batch_review_cards([99998, 99999], "approve")
