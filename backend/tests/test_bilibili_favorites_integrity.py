"""Cross-folder resume and shared imports must preserve all favorite items."""
import json
from unittest.mock import AsyncMock

import httpx

from app.adapters.favorites.bilibili_fetcher import BilibiliFavoritesFetcher
from app.services.config_service import ConfigService


def video(number):
    return {'id': number, 'type': 2, 'title': f'Video {number}', 'cover': '',
            'upper': {'name': 'Fixture'}, 'fav_time': 1700000000,
            'bvid': f'BV{number:010d}'}


async def test_resume_mid_page_and_cross_folder_without_loss(monkeypatch):
    cfg = ConfigService()
    await cfg.set_value('bilibili_cookie', 'SESSDATA=fixture-only')
    monkeypatch.setattr(ConfigService, 'get_http_proxy', AsyncMock(return_value=None))
    real_client = httpx.AsyncClient
    def respond(request):
        assert request.headers['cookie'] == 'SESSDATA=fixture-only'
        path = request.url.path
        if path.endswith('/nav'):
            data = {'isLogin': True, 'mid': 7}
        elif path.endswith('/list-all'):
            data = {'count': 2, 'list': [{'id': 10, 'title': 'First'}, {'id': 11, 'title': 'Second'}]}
        else:
            assert request.url.params['ps'] == '20'
            folder, page = int(request.url.params['media_id']), int(request.url.params['pn'])
            numbers = {(10, 1): range(1, 21), (10, 2): range(21, 24), (11, 1): range(24, 27)}[(folder, page)]
            data = {'medias': [video(n) for n in numbers], 'has_more': (folder, page) == (10, 1)}
        return httpx.Response(200, json={'code': 0, 'data': data})
    monkeypatch.setattr(httpx, 'AsyncClient', lambda **kwargs: real_client(**kwargs, transport=httpx.MockTransport(respond)))
    first, cursor = await BilibiliFavoritesFetcher().fetch_favorites(max_items=21)
    assert json.loads(cursor) == {'mid': 7, 'folder_id': 10, 'page': 2, 'offset': 1}
    rest, end = await BilibiliFavoritesFetcher().fetch_favorites(max_items=21, cursor=cursor)
    assert [item.item_id for item in first + rest] == [str(n) for n in range(1, 27)]
    assert rest[-1].collection_id == '11'
    assert rest[-1].collection_title == 'Second'
    assert end is None
    await cfg.delete_value('bilibili_cookie')


async def test_shared_import_keeps_collection_sources_and_unavailable_receipt(db_session, monkeypatch):
    from sqlalchemy import select
    from app.adapters.favorites.base import FavoriteItem
    from app.models import ContentSource
    from app.tasks.favorites_sync import FavoritesSyncTask

    monkeypatch.setattr('app.services.content_service.task_queue.enqueue', AsyncMock(return_value=True))
    items = [FavoriteItem(url='https://www.bilibili.com/video/BV1000000001/',
                          item_id='1', collection_id=folder, collection_title=folder)
             for folder in ['10', '11']]
    items.append(FavoriteItem(url='', item_id='2', collection_id='11', skip_reason='视频已不可用'))
    result = await FavoritesSyncTask().import_items(
        db_session, platform='bilibili', items=items, source_name='bilibili_favorites',
    )
    assert result['imported'] == 2
    assert result['skipped'] == 1
    assert result['failed'] == 0
    succeeded = [item for item in result['items'] if item['status'] == 'success']
    assert succeeded[0]['content_id'] == succeeded[1]['content_id']
    sources = (await db_session.execute(select(ContentSource).where(
        ContentSource.content_id == succeeded[0]['content_id'],
    ))).scalars().all()
    assert {source.client_context['collection_id'] for source in sources} == {'10', '11'}
