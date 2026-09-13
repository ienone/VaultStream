"""Weibo web identity and page offsets must not lose favorites on failure."""
import json
from unittest.mock import AsyncMock

import httpx
import pytest

from app.adapters.favorites.weibo_fetcher import WeiboFavoritesFetcher
from app.adapters.favorites.errors import FavoritesFetchError
from app.services.config_service import ConfigService
from app.services.browser_auth_service import BrowserAuthService


@pytest.mark.parametrize('case', ['pages', 'expired', 'redirect', 'malformed', 'account_changed'])
async def test_weibo_identity_and_pagination(monkeypatch, case):
    cfg = ConfigService()
    await cfg.set_value('weibo_cookie', 'SUB=fixture-only')
    monkeypatch.setattr(ConfigService, 'get_http_proxy', AsyncMock(return_value=None))
    original = httpx.AsyncClient
    pages = []
    def response(request):
        assert request.headers['cookie'] == 'SUB=fixture-only'
        if request.url.path == '/api/config':
            return httpx.Response(200, json={'ok': 1, 'data': {'login': case != 'expired', 'uid': '8' if case == 'account_changed' else '7'}})
        if case == 'redirect':
            return httpx.Response(302, headers={'location': 'https://passport.weibo.com/'})
        if case == 'malformed':
            return httpx.Response(200, json={'ok': 1, 'data': {}})
        page = int(request.url.params['page'])
        pages.append(page)
        return httpx.Response(200, json={'ok': 1, 'data': [
            {'id': n, 'text': f'微博正文{n}', 'user': {'screen_name': '作者'}}
            for n in {1: [101, 102, 103], 2: [104, 105], 3: []}[page]]})
    monkeypatch.setattr(httpx, 'AsyncClient', lambda **kwargs: original(**kwargs, transport=httpx.MockTransport(response)))
    try:
        fetcher = WeiboFavoritesFetcher()
        if case == 'pages':
            first, cursor = await fetcher.fetch_favorites(max_items=2)
            rest, end = await fetcher.fetch_favorites(max_items=10, cursor=cursor)
            assert [item.item_id for item in first + rest] == [str(n) for n in range(101, 106)]
            assert end is None and pages == [1, 1, 2, 3]
            assert await BrowserAuthService()._check_weibo_status('SUB=fixture-only')
        else:
            cursor = json.dumps({'uid': '7', 'page': 1, 'offset': 0})
            with pytest.raises(FavoritesFetchError) as error:
                await fetcher.fetch_favorites(cursor=cursor)
            assert error.value.code == {'expired': 'auth_required', 'redirect': 'auth_required',
                'malformed': 'parse_failed', 'account_changed': 'invalid_cursor'}[case]
            if case == 'expired':
                assert not await BrowserAuthService()._check_weibo_status('SUB=fixture-only')
    finally:
        await cfg.delete_value('weibo_cookie')
