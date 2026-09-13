"""Failed feeds must not become successful empty syncs or advance cursors."""

import httpx
import pytest

from app.models import BackgroundTaskRun, DiscoverySource, DiscoverySourceKind
from app.tasks.discovery_sync import DiscoverySyncTask


@pytest.mark.parametrize('case', ['http_error', 'invalid_feed', 'empty_feed'])
async def test_rss_failure_receipt_and_cursor(db_session, monkeypatch, case):
    real_client = httpx.AsyncClient
    def respond(request):
        if case == 'http_error':
            return httpx.Response(503, text='private-response-detail')
        if case == 'invalid_feed':
            return httpx.Response(200, text='<html><body>Sign in</body></html>')
        return httpx.Response(200, content=b'<rss version="2.0"><channel><title>Empty</title><link>https://example.test</link><description>Empty feed</description></channel></rss>')
    monkeypatch.setattr(httpx, 'AsyncClient', lambda **kwargs: real_client(
        **kwargs, transport=httpx.MockTransport(respond)))
    source = DiscoverySource(name=f'RSS {case}', kind=DiscoverySourceKind.RSS,
                             enabled=True, config={'url': 'https://example.test/feed?token=private-test-token'},
                             last_cursor='preserved-cursor')
    db_session.add(source)
    await db_session.commit()
    task = DiscoverySyncTask()
    run = await task.create_run(source, trigger='manual')
    await task._sync_single_source(db_session, source, run_id=run['run_id'], trigger='manual')
    await db_session.refresh(source)
    receipt = await db_session.get(BackgroundTaskRun, run['run_id'])
    assert source.last_cursor == 'preserved-cursor'
    assert receipt.status == ('success' if case == 'empty_feed' else 'error')
    assert bool(source.last_error) == (case != 'empty_feed')
    assert 'private-test-token' not in (source.last_error or '')
    assert 'private-response-detail' not in (receipt.error or '')
