"""
Pytest Fixtures for Backend Tests
"""
import os
import shutil
import sys
import uuid
from pathlib import Path
import pytest
import asyncio
from typing import AsyncGenerator, Dict, List
from httpx import AsyncClient, ASGITransport
from loguru import logger

# Keep test runtime output in an ignored, isolated backend directory. The suite
# is launched from the repository root, so cwd-relative paths would otherwise
# recreate root-level data/ and logs/ directories.
TEST_RUNTIME_PARENT = Path(__file__).resolve().parents[1] / ".test-runtime"
TEST_RUNTIME_PARENT.mkdir(parents=True, exist_ok=True)
TEST_RUNTIME_DIR = str(TEST_RUNTIME_PARENT / f"session-{uuid.uuid4().hex}")
Path(TEST_RUNTIME_DIR).mkdir(parents=True, exist_ok=False)

# Pytest may load this file as top-level ``conftest`` while older tests import
# ``tests.conftest``. Alias both names so those imports do not execute this
# module twice and silently create a second empty test database.
sys.modules.setdefault("tests.conftest", sys.modules[__name__])

TEST_DB_PATH = os.path.join(TEST_RUNTIME_DIR, "test_vaultstream.db")
os.environ["SQLITE_DB_PATH"] = TEST_DB_PATH
os.environ["STORAGE_LOCAL_ROOT"] = os.path.join(TEST_RUNTIME_DIR, "storage")
os.environ["VAULTSTREAM_LOG_DIR"] = os.path.join(TEST_RUNTIME_DIR, "logs")
os.environ["VAULTSTREAM_TEST_RUNTIME_DIR"] = TEST_RUNTIME_DIR

# Ensure the test database path is clean before app modules create engines.
if os.path.exists(TEST_DB_PATH):
    try:
        os.remove(TEST_DB_PATH)
    except OSError:
        pass

from app.main import app
from app.core.config import settings
from app.core.database import ensure_content_embeddings_schema, ensure_content_fts, get_db
from app.core.db_adapter import engine as app_engine
from app.core.schema_gate import ensure_schema_metadata
from app.models import Base, Content
from sqlalchemy.ext.asyncio import create_async_engine, AsyncSession
from sqlalchemy.orm import sessionmaker
from sqlalchemy import select, text
from sqlalchemy.pool import NullPool

DB_URL = f"sqlite+aiosqlite:///{TEST_DB_PATH}"

engine = create_async_engine(
    DB_URL,
    echo=False,
    connect_args={"timeout": 30},
    poolclass=NullPool,
)
TestingSessionLocal = sessionmaker(
    bind=engine,
    class_=AsyncSession,
    expire_on_commit=False,
    autoflush=False,
)


async def _ensure_test_schema() -> None:
    """Ensure the shared file-backed test DB still has the application schema."""
    async with engine.begin() as conn:
        existing = await conn.execute(
            text(
                """
                SELECT name
                FROM sqlite_master
                WHERE type = 'table'
                  AND name IN (
                    'contents',
                    'system_settings',
                    'bot_configs',
                    'content_queue_items'
                  )
                """
            )
        )
        table_names = {row[0] for row in existing.fetchall()}
        if {
            "contents",
            "system_settings",
            "bot_configs",
            "content_queue_items",
        } - table_names:
            await conn.run_sync(Base.metadata.create_all)

        await ensure_content_embeddings_schema(conn)
        await ensure_content_fts(conn)
        await ensure_schema_metadata(conn)


async def override_get_db():
    await _ensure_test_schema()
    async with TestingSessionLocal() as session:
        yield session

@pytest.fixture(scope="session", autouse=True)
async def setup_test_db():
    """Create a clean database for the test session."""
    await _ensure_test_schema()

    app.dependency_overrides[get_db] = override_get_db
    
    yield

    app.dependency_overrides.pop(get_db, None)
    await engine.dispose()
    await app_engine.dispose()
    logger.remove()
    shutil.rmtree(TEST_RUNTIME_DIR, ignore_errors=True)
    os.environ.pop("VAULTSTREAM_TEST_RUNTIME_DIR", None)
    try:
        TEST_RUNTIME_PARENT.rmdir()
    except OSError:
        pass

@pytest.fixture(scope="session")
def event_loop():
    """Create an instance of the default event loop for each test case."""
    loop = asyncio.get_event_loop_policy().new_event_loop()
    yield loop
    loop.close()

@pytest.fixture(scope="function")
def tmp_path():
    """Provide a writable temporary path under the repository test runtime."""
    path = Path(TEST_RUNTIME_DIR) / f"tmp-{uuid.uuid4().hex}"
    path.mkdir(parents=True, exist_ok=False)
    try:
        yield path
    finally:
        shutil.rmtree(path, ignore_errors=True)

@pytest.fixture(scope="function")
async def db_session() -> AsyncGenerator[AsyncSession, None]:
    """Provide a transactional database session."""
    await _ensure_test_schema()
    async with TestingSessionLocal() as session:
        yield session
        # No rollback here because we want to test against the persistent real DB state
        # as per the specific requirement to "use real data".
        # In a normal test suite, we would rollback here.


@pytest.fixture(scope="function", autouse=True)
async def cleanup_app_db_engine():
    yield
    await engine.dispose()
    await app_engine.dispose()


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
