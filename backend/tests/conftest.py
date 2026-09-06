"""Small regressions use the real SQLite engine and ASGI app, with no workers."""
import os
import tempfile
from pathlib import Path

import pytest
from httpx import ASGITransport, AsyncClient
from loguru import logger

# Set paths before importing the app; never point regression writes at user data.
_runtime_parent = Path(__file__).resolve().parents[1] / '.test-runtime'
_runtime_parent.mkdir(exist_ok=True)
_runtime = tempfile.TemporaryDirectory(prefix='regression-', dir=_runtime_parent)
os.environ.update({
    'SQLITE_DB_PATH': str(Path(_runtime.name) / 'vaultstream.db'),
    'STORAGE_LOCAL_ROOT': str(Path(_runtime.name) / 'storage'),
    'VAULTSTREAM_LOG_DIR': str(Path(_runtime.name) / 'logs'),
    'API_TOKEN': 'regression-control-token',
    'MEDIA_SIGNING_SECRET': 'regression-media-secret',
    'ENABLE_AUTO_SUMMARY': 'false',
    'ENABLE_AUTO_SEMANTIC_INDEXING': 'false',
    'ENABLE_ARCHIVE_MEDIA_PROCESSING': 'false',
})

from app.core.database import ensure_content_embeddings_schema, ensure_content_fts
from app.core.db_adapter import AsyncSessionLocal, engine
from app.main import app
from app.models import Base


@pytest.fixture(scope='session', autouse=True)
async def database():
    async with engine.begin() as connection:
        await connection.run_sync(Base.metadata.create_all)
        await ensure_content_embeddings_schema(connection)
        await ensure_content_fts(connection)
    yield
    await engine.dispose()
    logger.remove()
    _runtime.cleanup()


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
