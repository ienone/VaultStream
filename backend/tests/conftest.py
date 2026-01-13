"""
Pytest Fixtures for Backend Tests
"""
import pytest
import asyncio
from typing import AsyncGenerator
from httpx import AsyncClient, ASGITransport
from sqlalchemy.ext.asyncio import create_async_engine, AsyncSession
from sqlalchemy.orm import sessionmaker

from app.main import app
from app.config import settings
from app.database import Base

# Override the database URL for testing if needed
# For now, we use the existing SQLite DB (as per user request to test with real data)
# In a strict unit test environment, we might want a separate test DB.
DB_URL = f"sqlite+aiosqlite:///{settings.sqlite_db_path}"

engine = create_async_engine(DB_URL, echo=False)
TestingSessionLocal = sessionmaker(
    bind=engine,
    class_=AsyncSession,
    expire_on_commit=False,
    autoflush=False,
)

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
