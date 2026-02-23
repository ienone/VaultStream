"""
Pytest Fixtures for Backend Tests
"""
import os
import pytest
import asyncio
from typing import AsyncGenerator, Dict, List
from httpx import AsyncClient, ASGITransport

# Set test database path in environment before importing app/settings
TEST_DB_PATH = os.path.abspath("data/test_vaultstream.db")
os.environ["SQLITE_DB_PATH"] = TEST_DB_PATH

from app.main import app
from app.core.config import settings
from app.core.database import init_db
from app.models import Base, Content
from sqlalchemy.ext.asyncio import create_async_engine, AsyncSession
from sqlalchemy.orm import sessionmaker
from sqlalchemy import select, text

DB_URL = f"sqlite+aiosqlite:///{TEST_DB_PATH}"

# Ensure data directory exists
os.makedirs("data", exist_ok=True)

engine = create_async_engine(DB_URL, echo=False)
TestingSessionLocal = sessionmaker(
    bind=engine,
    class_=AsyncSession,
    expire_on_commit=False,
    autoflush=False,
)

# Ensure we start fresh globally
if os.path.exists(TEST_DB_PATH):
    try:
        os.remove(TEST_DB_PATH)
    except OSError:
        pass

@pytest.fixture(scope="session", autouse=True)
async def setup_test_db():
    """Create a clean database for the test session."""
    async with engine.begin() as conn:
        await conn.run_sync(Base.metadata.create_all)
    
    yield

@pytest.fixture(scope="session")
def event_loop():
    """Create an instance of the default event loop for each test case."""
    loop = asyncio.get_event_loop_policy().new_event_loop()
    yield loop
    loop.close()

@pytest.fixture(scope="function")
async def db_session() -> AsyncGenerator[AsyncSession, None]:
    """Provide a transactional database session."""
    async with TestingSessionLocal() as session:
        yield session
        # No rollback here because we want to test against the persistent real DB state
        # as per the specific requirement to "use real data".
        # In a normal test suite, we would rollback here.

@pytest.fixture(scope="function")
async def client() -> AsyncGenerator[AsyncClient, None]:
    """Provide an authenticated AsyncClient."""
    transport = ASGITransport(app=app)
    headers = {"X-API-Token": settings.api_token.get_secret_value() if settings.api_token else ""}
    async with AsyncClient(transport=transport, base_url="http://test", headers=headers) as c:
        yield c

@pytest.fixture(scope="function")
async def get_platform_urls(db_session: AsyncSession):
    """
    Query database for real test URLs by platform
    
    Usage:
        urls = await get_platform_urls("bilibili", limit=3)
        # Returns: {"video": "https://...", "article": "https://..."}
    """
    async def _query(platform: str, limit: int = 5) -> Dict[str, str]:
        """Fetch URLs grouped by content_type"""
        stmt = (
            select(Content.url, Content.content_type)
            .where(Content.platform == platform)
            .distinct(Content.content_type)
            .limit(limit)
        )
        result = await db_session.execute(stmt)
        rows = result.all()
        
        # Return first URL for each content_type
        url_map = {}
        for row in rows:
            if row.content_type not in url_map:
                url_map[row.content_type] = row.url
        
        return url_map
    
    return _query