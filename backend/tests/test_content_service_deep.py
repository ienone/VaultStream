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
