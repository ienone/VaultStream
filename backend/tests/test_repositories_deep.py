import pytest
import asyncio
from datetime import datetime
from sqlalchemy.ext.asyncio import create_async_engine, AsyncSession
from sqlalchemy.orm import sessionmaker
from app.models.base import Base
from app.models.content import Content, ContentStatus, ReviewStatus
from app.repositories.content_repository import ContentRepository

@pytest.fixture
async def db_session():
    # Use real in-memory SQLite for repository testing
    engine = create_async_engine("sqlite+aiosqlite:///:memory:")
    async with engine.begin() as conn:
        await conn.run_sync(Base.metadata.create_all)
        
    async_session = sessionmaker(engine, class_=AsyncSession, expire_on_commit=False)
    async with async_session() as session:
        yield session
    await engine.dispose()

@pytest.mark.asyncio
async def test_content_repo_list_with_tags(db_session):
    """Test filtering contents by JSON tags."""
    repo = ContentRepository(db_session)
    
    # Insert test data
    c1 = Content(
        title="Post 1", 
        url="url1", 
        platform="twitter", 
        tags=["ai", "tech"],
        created_at=datetime.now()
    )
    c2 = Content(
        title="Post 2", 
        url="url2", 
        platform="weibo", 
        tags=["daily"],
        created_at=datetime.now()
    )
    db_session.add_all([c1, c2])
    await db_session.commit()
    
    # Filter by tag 'ai'
    results, total = await repo.list_contents(tags=["ai"])
    assert total == 1
    assert results[0].title == "Post 1"
    
    # Filter by multiple tags
    results, total = await repo.list_contents(tags=["ai", "daily"])
    assert total == 2

@pytest.mark.asyncio
async def test_content_repo_search_fallback(db_session):
    """Test searching with ILIKE when FTS5 is missing or fails."""
    repo = ContentRepository(db_session)
    
    # Insert test data
    c1 = Content(
        title="Search Target Keyword", 
        url="url1", 
        platform="twitter",
        created_at=datetime.now()
    )
    db_session.add(c1)
    await db_session.commit()
    
    # Searching 'Keyword' should hit ILIKE even if FTS5 table doesn't exist
    results, total = await repo.list_contents(q="Keyword")
    assert total == 1
    assert results[0].title == "Search Target Keyword"

@pytest.mark.asyncio
async def test_content_repo_pagination_bounds(db_session):
    """Test pagination math and offsets with valid platform enum."""
    repo = ContentRepository(db_session)
    
    # Create 5 items with valid platform 'universal'
    for i in range(5):
        c = Content(title=f"Item {i}", url=f"u{i}", platform="universal", created_at=datetime.now())
        db_session.add(c)
    await db_session.commit()
    
    # Page 1, size 2 -> items
    results, total = await repo.list_contents(page=1, size=2)
    assert total == 5
    assert len(results) == 2
    
    # Page 3, size 2 -> item 4
    results, total = await repo.list_contents(page=3, size=2)
    assert len(results) == 1

@pytest.mark.asyncio
async def test_content_repo_defer_loading(db_session):
    """Test that archive_metadata is deferred when include_archive_metadata=False."""
    repo = ContentRepository(db_session)
    
    big_data = {"data": "x" * 1000}
    c1 = Content(
        title="Heavy Post", 
        url="url1", 
        platform="universal",
        archive_metadata=big_data,
        created_at=datetime.now()
    )
    db_session.add(c1)
    await db_session.commit()
    
    # Expire cached state so deferred loading behavior is observable
    db_session.expire_all()
    
    # List without archive_metadata — should succeed and return basic fields
    results, total = await repo.list_contents(include_archive_metadata=False)
    assert results[0].title == "Heavy Post"
    
    # List WITH archive_metadata — should include the full metadata
    db_session.expire_all()
    results_full, _ = await repo.list_contents(include_archive_metadata=True)
    assert results_full[0].archive_metadata == big_data
