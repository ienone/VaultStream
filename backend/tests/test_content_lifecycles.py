import hashlib
from datetime import timedelta
from uuid import uuid4

import pytest
from sqlalchemy import func, select

from app.adapters.storage import LocalStorageBackend
from app.adapters.storage.manager import StorageObjectTooLargeError
from app.core.time_utils import utcnow
from app.models import Content, ContentStatus, DiscoveryState, Platform
from app.services.content_service import CaptureFileInput, ContentService
from app.services.search_service import UnifiedSearchService


async def _chunks(data):
    yield data


async def test_capture_batch_validation_leaves_no_files_and_preserves_shared_object(db_session, tmp_path):
    storage = LocalStorageBackend(str(tmp_path))
    shared_key = 'sha256:' + hashlib.sha256(b'old').hexdigest()
    await storage.put_bytes(key=shared_key, data=b'old', content_type='text/plain')
    before = {p.relative_to(tmp_path) for p in tmp_path.rglob('*') if p.is_file()}
    for first in (b'new', b'old'):
        with pytest.raises(StorageObjectTooLargeError):
            await ContentService(db_session).create_files_capture(
                [CaptureFileInput(chunks=_chunks(data), filename='sample.txt', mime_type='text/plain')
                 for data in (first, b'oversize')],
                storage=storage, max_bytes=3,
            )
        assert {p.relative_to(tmp_path) for p in tmp_path.rglob('*') if p.is_file()} == before
        assert await storage.get_bytes(shared_key) == b'old'


async def test_capture_publish_failure_rolls_back_rows_and_only_new_objects(db_session, tmp_path, monkeypatch):
    storage = LocalStorageBackend(str(tmp_path))
    shared_key = 'sha256:' + hashlib.sha256(b'old').hexdigest()
    await storage.put_bytes(key=shared_key, data=b'old', content_type='text/plain')
    before = await db_session.scalar(select(func.count()).select_from(Content))
    publish = storage.publish_staged
    calls = 0

    async def fail_third(stored, path):
        nonlocal calls
        calls += 1
        if calls == 3:
            raise OSError('disk unavailable')
        return await publish(stored, path)

    monkeypatch.setattr(storage, 'publish_staged', fail_third)
    with pytest.raises(OSError):
        await ContentService(db_session).create_files_capture(
            [CaptureFileInput(chunks=_chunks(data), filename='sample.txt', mime_type='text/plain')
             for data in (b'old', b'new', b'end')],
            storage=storage, max_bytes=3,
        )
    assert await db_session.scalar(select(func.count()).select_from(Content)) == before
    assert [p.read_bytes() for p in tmp_path.rglob('*') if p.is_file()] == [b'old']


async def test_exact_search_applies_scope_before_candidate_limit(db_session):
    needle = uuid4().hex
    now = utcnow()
    items = []
    for index in range(52):
        item = Content(
            platform=Platform.UNIVERSAL,
            url=f'https://example.test/{needle}/{index}',
            canonical_url=f'{needle}/{index}', title='内容',
            status=ContentStatus.PARSE_SUCCESS,
            discovery_state=None if index == 0 else DiscoveryState.VISIBLE,
            tags=[needle],
            rich_payload={'chunks': [{'segment_type': 'chapter', 'media_asset_id': 7,
                                      'start_seconds': 0, 'title': needle}]},
            created_at=now, updated_at=now + timedelta(seconds=index),
        )
        items.append(item)
    db_session.add_all(items)
    await db_session.commit()
    service = UnifiedSearchService(db_session)
    for lookup in (service._exact_topic_contents, service._exact_timepoint_contents):
        result = await lookup(query=needle, content_scope='library', platforms=['universal'],
                              date_from=now - timedelta(days=1), date_to=now + timedelta(days=1), limit=50)
        assert [item.id for item in result] == [items[0].id]
