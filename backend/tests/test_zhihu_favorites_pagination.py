import json
from unittest.mock import AsyncMock
from urllib.parse import urlparse, parse_qs
import pytest
from app.adapters.favorites.zhihu_fetcher import ZhihuFavoritesFetcher
from app.adapters.favorites.errors import FavoritesFetchError


async def test_small_batches_resume_inside_pages_and_across_collections(monkeypatch):
    fetcher = ZhihuFavoritesFetcher()
    monkeypatch.setattr(fetcher, '_get_cookies', AsyncMock(return_value={'z_c0': 'test-only'}))
    monkeypatch.setattr(fetcher, '_fetch_user_collections', AsyncMock(return_value=[{'id': 10}, {'id': 20}]))
    datasets = {'10': [101, 102, 103, 104], '20': [201, 202]}
    async def api(url, cookies):
        parsed = urlparse(url); coll = parsed.path.split('/')[-2]
        offset = int(parse_qs(parsed.query)['offset'][0])
        batch = datasets[coll][offset:offset + 2]
        return {'data': [{'content': {'id': i, 'type': 'article'}} for i in batch],
                'paging': {'is_end': offset + len(batch) >= len(datasets[coll])}}
    monkeypatch.setattr(fetcher, '_api_get', api)
    monkeypatch.setattr(fetcher, '_PAGE_SIZE', 2)
    cursor = None; seen = []
    for _ in range(10):
        items, cursor = await fetcher.fetch_favorites(max_items=1, cursor=cursor)
        seen.extend(item.item_id for item in items)
        if cursor is None: break
    assert seen == ['101', '102', '103', '104', '201', '202']
    assert cursor is None
    for invalid in ['[]', '{"collection_id":"10","offset":-1}', '{"collection_id":"999","offset":0}']:
        with pytest.raises(FavoritesFetchError) as exc:
            await fetcher.fetch_favorites(max_items=1, cursor=invalid)
        assert exc.value.code == 'invalid_cursor'
