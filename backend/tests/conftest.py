"""Small regressions use the real SQLite engine and ASGI app, with no workers."""
import os
from pathlib import Path

import pytest
from httpx import ASGITransport, AsyncClient
from loguru import logger
from sqlalchemy import delete, text

# Set paths before importing the app; never point regression writes at user data.
_runtime = Path(__file__).resolve().parents[1] / '.test-runtime'
_runtime.mkdir(exist_ok=True)
os.environ.update({
    'SQLITE_DB_PATH': os.environ.get('VAULTSTREAM_TEST_DB', str(_runtime / 'regression.db')),
    'STORAGE_LOCAL_ROOT': str(_runtime / 'storage'),
    'VAULTSTREAM_LOG_DIR': str(_runtime / 'logs'),
    'API_TOKEN': 'regression-control-token',
    'MEDIA_SIGNING_SECRET': 'regression-media-secret',
    'ENABLE_AUTO_SUMMARY': 'false',
    'ENABLE_AUTO_SEMANTIC_INDEXING': 'false',
    'ENABLE_ARCHIVE_MEDIA_PROCESSING': 'false',
})

from app.core.database import init_db
from app.core.db_adapter import AsyncSessionLocal, engine
from app.main import app
from app.models import Base


@pytest.fixture(scope='session', autouse=True)
async def database():
    await init_db()
    # Reuse one test database, clearing previous test rows rather than creating
    # another timestamped SQLite file for every invocation.
    async with engine.begin() as connection:
        for table in reversed(Base.metadata.sorted_tables):
            await connection.execute(delete(table))
        await connection.execute(text('DELETE FROM realtime_events'))
    yield
    await engine.dispose()
    logger.remove()


@pytest.fixture
async def db_session():
    async with AsyncSessionLocal() as session:
        yield session


@pytest.fixture
async def client():
    # ASGITransport does not enter lifespan, so sync/push workers stay stopped.
    async with AsyncClient(
        transport=ASGITransport(app=app), base_url='http://test',
        headers={'X-API-Token': 'regression-control-token'},
    ) as http:
        yield http
