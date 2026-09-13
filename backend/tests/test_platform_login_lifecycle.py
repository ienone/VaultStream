"""Login cancellation must not restore credentials after an explicit logout."""

import asyncio
from unittest.mock import AsyncMock

import httpx
import pytest

from app.services.browser_auth_service import BrowserAuthService
from app.services.config_service import ConfigService
from app.services.platform_auth.drivers import QrLoginChallenge, QrLoginPollResult, QrLoginState


class LoginBoundary:
    poll_interval = 0
    timeout = 10

    def __init__(self):
        self.polling = asyncio.Event()
        self.release = asyncio.Event()
        self.closed = False

    async def open(self):
        pass

    async def create_challenge(self):
        return QrLoginChallenge('fixture-login-challenge', 'fixture')

    async def poll(self):
        self.polling.set()
        await self.release.wait()
        return QrLoginPollResult(QrLoginState.SUCCESS, 'fixture', 'SESSDATA=fixture-only')

    async def close(self):
        self.closed = True


@pytest.mark.parametrize('action', ['logout', 'replace', 'complete'])
async def test_persisted_login_lifecycle(action):
    config = ConfigService()
    await config.delete_value('bilibili_cookie')
    drivers = []

    def factory():
        driver = LoginBoundary()
        drivers.append(driver)
        return driver

    service = BrowserAuthService(config_service=config, driver_factories={'bilibili': factory})
    status = await service.start_auth_session('bilibili')
    session = service.sessions[status.session_id]
    await asyncio.wait_for(drivers[0].polling.wait(), 2)
    if action == 'logout':
        await service.logout_platform('bilibili')
        drivers[0].release.set()
        assert session.task.done()
        assert session.session_id not in service.sessions
    elif action == 'replace':
        newer = await service.start_auth_session('bilibili')
        assert session.task.done()
        assert session.session_id not in service.sessions
        await service.cancel_session(newer.session_id)
    else:
        drivers[0].release.set()
        await asyncio.wait_for(session.task, 2)
        assert session.status == 'success'

    assert drivers[0].closed
    assert session.cookie_str is None
    # A fresh service with an independent cache reads the durable result.
    restarted_config = ConfigService(cache={})
    stored = await restarted_config.get_platform_cookie_string('bilibili', fresh=True)
    assert bool(stored) == (action == 'complete')
    await service.logout_platform('bilibili')


@pytest.mark.parametrize('intervening', ['logout', 'relogin', 'none'])
async def test_cookie_refresh_cannot_restore_logout_or_replace_new_login(intervening):
    config = ConfigService()
    await config.set_value('zhihu_cookie', 'z_c0=fixture-old')
    old = await config.get_platform_cookie_string('zhihu', fresh=True)
    if intervening == 'logout':
        await config.delete_value('zhihu_cookie')
    elif intervening == 'relogin':
        await config.set_value('zhihu_cookie', 'z_c0=fixture-new-login')
    changed = await config.replace_value_if_unchanged('zhihu_cookie', old, 'z_c0=fixture-refreshed')
    assert changed == (intervening == 'none')
    expected = {'logout': None, 'relogin': 'z_c0=fixture-new-login', 'none': 'z_c0=fixture-refreshed'}
    assert await ConfigService().get_value_fresh('zhihu_cookie') == expected[intervening]
    await config.delete_value('zhihu_cookie')


@pytest.mark.parametrize('platform', ['zhihu', 'xiaohongshu'])
@pytest.mark.parametrize('relogin_during_request', [False, True])
async def test_favorites_response_rotation_uses_current_persisted_login(monkeypatch, platform, relogin_during_request):
    from app.adapters.base import PlatformAdapter
    from app.adapters.favorites.zhihu_fetcher import ZhihuFavoritesFetcher
    from app.adapters.favorites.xiaohongshu_fetcher import XiaohongshuFavoritesFetcher

    config = ConfigService()
    key = f'{platform}_cookie'
    original = 'z_c0=fixture-old' if platform == 'zhihu' else 'a1=fixture; web_session=fixture-old'
    await config.set_value(key, original)
    real_client = httpx.AsyncClient

    async def respond(request):
        assert 'fixture-old' in request.headers['cookie']
        if relogin_during_request:
            await config.set_value(key, 'session=fixture-new-login')
        return httpx.Response(200, json={'success': True, 'data': {}},
                              headers={'set-cookie': 'refresh_marker=fixture-rotated; Path=/; Secure'})

    monkeypatch.setattr(httpx, 'AsyncClient', lambda **kwargs: real_client(
        **kwargs, transport=httpx.MockTransport(respond)))
    monkeypatch.setattr(ConfigService, 'get_http_proxy', AsyncMock(return_value=None))
    monkeypatch.setattr('app.adapters.favorites.zhihu_fetcher.truncated_gaussian_delay', lambda **kwargs: 0)
    monkeypatch.setattr('app.adapters.favorites.xiaohongshu_fetcher.truncated_gaussian_delay', lambda **kwargs: 0)
    cookies = PlatformAdapter.parse_cookie_str(original)
    if platform == 'zhihu':
        await ZhihuFavoritesFetcher()._api_get('https://www.zhihu.com/api/v4/me', cookies)
    else:
        fetcher = XiaohongshuFavoritesFetcher()
        monkeypatch.setattr(fetcher._xhs_client, 'sign_headers_get', lambda **kwargs: {})
        await fetcher._request_signed_get('/api/sns/web/v2/user/me', cookies=cookies)
    saved = await ConfigService(cache={}).get_value_fresh(key)
    if relogin_during_request:
        assert saved == 'session=fixture-new-login'
    else:
        assert PlatformAdapter.parse_cookie_str(saved) == {**PlatformAdapter.parse_cookie_str(original), 'refresh_marker': 'fixture-rotated'}
    await config.delete_value(key)


async def test_fresh_missing_credential_invalidates_older_reader_cache():
    reader, writer = ConfigService(), ConfigService()
    await writer.set_value('weibo_cookie', 'SUB=fixture-before-logout')
    assert await reader.get_value('weibo_cookie') == 'SUB=fixture-before-logout'
    await writer.delete_value('weibo_cookie')
    assert await reader.get_value_fresh('weibo_cookie') is None
    assert await reader.get_value('weibo_cookie') is None
