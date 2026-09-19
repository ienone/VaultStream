from unittest.mock import AsyncMock
import pytest
from app.adapters.favorites.base import FavoriteItem
from app.services.config_service import ConfigService
from app.tasks.favorites_sync import FavoritesSyncTask

@pytest.mark.parametrize('failed', [False, True])
async def test_cursor_clears_at_end_but_does_not_skip_failed_imports(monkeypatch, failed):
    cfg = ConfigService()
    await cfg.set_favorites_sync_cursor('xiaohongshu', 'current-page')
    class Fetcher:
        def platform_name(self): return 'xiaohongshu'
        async def check_auth(self): return True
        async def fetch_favorites(self, **kwargs):
            assert kwargs['cursor'] == 'current-page'
            return ([FavoriteItem(url='https://www.xiaohongshu.com/explore/fixture')] if failed else []), ('next-page' if failed else None)
    task = FavoritesSyncTask()
    monkeypatch.setattr(task, 'default_rate_for', lambda platform: 1e9)
    if failed:
        monkeypatch.setattr('app.services.content_service.ContentService.create_share', AsyncMock(side_effect=RuntimeError('fixture unavailable')))
    result = await task._sync_platform(Fetcher())
    cursor = await cfg.get_value_fresh('favorites_sync_cursor_xiaohongshu')
    assert cursor == ('current-page' if failed else None)
    assert result['next_cursor'] == cursor
    assert result['failed'] == int(failed)


@pytest.mark.parametrize('next_cursor', ['', 'current-page', None])
async def test_xhs_broken_pagination_preserves_saved_cursor(monkeypatch, next_cursor):
    from app.adapters.favorites.xiaohongshu_fetcher import XiaohongshuFavoritesFetcher

    cfg = ConfigService()
    await cfg.set_favorites_sync_cursor('xiaohongshu', 'current-page')
    fetcher = XiaohongshuFavoritesFetcher()
    monkeypatch.setattr(fetcher, '_get_cookies', AsyncMock(return_value={'a1': 'fixture', 'web_session': 'fixture'}))
    monkeypatch.setattr(fetcher, '_get_self_user_id', AsyncMock(return_value='fixture-user'))
    monkeypatch.setattr(fetcher, '_request_signed_get', AsyncMock(return_value={
        'success': True, 'data': {'notes': [], 'has_more': True, 'cursor': next_cursor},
    }))
    result = await FavoritesSyncTask()._sync_platform(fetcher)
    assert result['status'] == 'failed'
    assert result['error_code'] == 'invalid_pagination'
    assert await cfg.get_value_fresh('favorites_sync_cursor_xiaohongshu') == 'current-page'


@pytest.mark.parametrize('data', [
    {}, {'notes': [], 'has_more': 'false'},
    {'notes': [{'note_id': 'a'}, {'note_id': 'b'}], 'has_more': True, 'cursor': 'later'},
])
async def test_xhs_missing_or_truncated_page_does_not_advance(monkeypatch, data):
    from app.adapters.favorites.xiaohongshu_fetcher import XiaohongshuFavoritesFetcher
    from app.adapters.favorites.errors import FavoritesFetchError
    fetcher = XiaohongshuFavoritesFetcher()
    monkeypatch.setattr(fetcher, '_get_cookies', AsyncMock(return_value={'a1': 'fixture', 'web_session': 'fixture'}))
    monkeypatch.setattr(fetcher, '_get_self_user_id', AsyncMock(return_value='fixture-user'))
    monkeypatch.setattr(fetcher, '_request_signed_get', AsyncMock(return_value={'success': True, 'data': data}))
    with pytest.raises(FavoritesFetchError, match='小红书'):
        await fetcher.fetch_favorites(max_items=1, cursor='current-page')


@pytest.mark.parametrize('strategy', ['skip', 'merge'])
async def test_committed_content_with_failed_parse_handoff_can_resume(db_session, monkeypatch, strategy):
    from uuid import uuid4
    from sqlalchemy import select
    from app.models import Content, ContentSource, ContentStatus

    url = f'https://www.bilibili.com/video/BV{uuid4().hex[:10]}/'
    item = FavoriteItem(url=url, platform='bilibili', collection_id='fixture-folder')
    enqueue = AsyncMock(side_effect=[False, True])
    monkeypatch.setattr('app.services.content_service.task_queue.enqueue', enqueue)
    task = FavoritesSyncTask()
    kwargs = dict(platform='bilibili', items=[item], source_name='bilibili_favorites', duplicate_strategy=strategy)
    failed = await task.import_items(db_session, **kwargs)
    assert failed['failed'] == 1
    resumed = await task.import_items(db_session, **kwargs)
    assert resumed['failed'] == 0 and resumed['imported'] == 1
    assert enqueue.await_count == 2
    content = await db_session.get(Content, resumed['items'][0]['content_id'])
    sources = (await db_session.execute(select(ContentSource).where(ContentSource.content_id == content.id))).scalars().all()
    assert len(sources) == 1
    content.status = ContentStatus.PARSE_SUCCESS
    await db_session.commit()
    await db_session.refresh(content)
    version = content.updated_at
    repeated = await task.import_items(db_session, **kwargs)
    assert repeated['duplicate_skipped'] == 1
    await db_session.refresh(content)
    assert content.updated_at == version
    sources = (await db_session.execute(select(ContentSource).where(ContentSource.content_id == content.id))).scalars().all()
    assert len(sources) == 1
    enqueue.assert_awaited()
    assert enqueue.await_count == 2


async def test_item_retry_preserves_collection_and_repeated_success(client, db_session, monkeypatch):
    from uuid import uuid4
    from sqlalchemy import select
    from app.models import Content, ContentSource, ContentStatus
    cfg = ConfigService()
    previous = await cfg.get_value_fresh('favorites_sync_platforms')
    await cfg.set_value('favorites_sync_platforms', ['bilibili'])
    monkeypatch.setattr('app.services.content_service.task_queue.enqueue', AsyncMock(return_value=True))
    body = {'platform':'bilibili','url':f'https://www.bilibili.com/video/BV{uuid4().hex[:10]}/',
            'collection_id':'fixture-collection','collection_title':'Fixture collection'}
    try:
        first = await client.post('/api/v1/favorites-sync/items/retry', json=body)
        assert first.status_code == 200, first.text
        content_id = first.json()['content_id']
        content = await db_session.get(Content, content_id)
        content.status = ContentStatus.PARSE_SUCCESS
        await db_session.commit()
        second = await client.post('/api/v1/favorites-sync/items/retry', json=body)
        assert second.status_code == 200, second.text
        assert second.json()['content_id'] == content_id
        sources = (await db_session.execute(select(ContentSource).where(ContentSource.content_id == content_id))).scalars().all()
        assert len(sources) == 1
        assert sources[0].client_context['collection_id'] == 'fixture-collection'
        assert sources[0].client_context['collection_title'] == 'Fixture collection'
        assert sources[0].source == 'favorites_sync:bilibili'
    finally:
        if previous is None:
            await cfg.delete_value('favorites_sync_platforms')
        else:
            await cfg.set_value('favorites_sync_platforms', previous)
