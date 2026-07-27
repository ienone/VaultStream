import httpx
import pytest

import app.services.platform_auth.drivers as drivers_module
from app.services.platform_auth import (
    BilibiliQrLoginDriver,
    QrLoginState,
    XiaohongshuQrLoginDriver,
    ZhihuQrLoginDriver,
)


@pytest.mark.asyncio
@pytest.mark.parametrize(
    ("code", "expected"),
    [
        (86101, QrLoginState.WAITING),
        (86090, QrLoginState.SCANNED),
        (86038, QrLoginState.EXPIRED),
    ],
)
async def test_bilibili_poll_maps_qr_status_codes(code, expected):
    async def handler(request: httpx.Request) -> httpx.Response:
        return httpx.Response(
            200,
            request=request,
            json={"code": 0, "data": {"code": code}},
        )

    driver = BilibiliQrLoginDriver()
    driver._client = httpx.AsyncClient(transport=httpx.MockTransport(handler))
    driver._qrcode_key = "qr-key"
    try:
        result = await driver.poll()
    finally:
        await driver.close()

    assert result.state == expected


@pytest.mark.asyncio
async def test_bilibili_poll_collects_cookie_on_success():
    async def handler(request: httpx.Request) -> httpx.Response:
        return httpx.Response(
            200,
            request=request,
            headers={
                "set-cookie": "SESSDATA=secret; Domain=.bilibili.com; Path=/"
            },
            json={"code": 0, "data": {"code": 0}},
        )

    driver = BilibiliQrLoginDriver()
    driver._client = httpx.AsyncClient(transport=httpx.MockTransport(handler))
    driver._qrcode_key = "qr-key"
    try:
        result = await driver.poll()
    finally:
        await driver.close()

    assert result.state == QrLoginState.SUCCESS
    assert result.cookie_str == "SESSDATA=secret"


class _ImmediateBrowserManager:
    ua = "test-agent"
    auth_viewport = {"width": 1280, "height": 800}

    def __init__(self, browser=None):
        self.browser = browser

    def get_browser(self):
        return self.browser

    async def submit_coro(self, coro):
        return await coro


class _FakeContext:
    def __init__(self, cookies, page=None):
        self.cookie_items = cookies
        self.page = page
        self.closed = False

    async def new_page(self):
        return self.page

    async def cookies(self):
        return self.cookie_items

    async def close(self):
        self.closed = True


class _FakePage:
    def __init__(self, content=""):
        self.page_content = content

    async def content(self):
        return self.page_content


@pytest.mark.asyncio
async def test_xiaohongshu_browser_poll_exports_settled_cookie_jar():
    context = _FakeContext(
        [
            {"name": "a1", "value": "a1-value", "domain": ".xiaohongshu.com"},
            {"name": "webId", "value": "web-id", "domain": ".xiaohongshu.com"},
            {
                "name": "web_session",
                "value": "real-session",
                "domain": ".xiaohongshu.com",
            },
            {
                "name": "unrelated",
                "value": "ignored",
                "domain": ".example.com",
            },
        ]
    )
    driver = XiaohongshuQrLoginDriver(_ImmediateBrowserManager())
    driver._context = context
    driver._page = _FakePage()
    driver._initial_web_session = "guest-session"

    result = await driver.poll()

    assert result.state == QrLoginState.SUCCESS
    assert "web_session=real-session" in result.cookie_str
    assert "unrelated=ignored" not in result.cookie_str


@pytest.mark.asyncio
async def test_xiaohongshu_browser_poll_maps_page_state():
    context = _FakeContext([])
    driver = XiaohongshuQrLoginDriver(_ImmediateBrowserManager())
    driver._context = context
    driver._page = _FakePage()
    driver._browser_qr_status = 1

    result = await driver.poll()

    assert result.state == QrLoginState.SCANNED

    driver._page.page_content = "请通过验证"
    result = await driver.poll()
    assert result.state == QrLoginState.NEEDS_CAPTCHA


@pytest.mark.asyncio
async def test_xiaohongshu_browser_response_tracks_confirmation():
    class Response:
        url = (
            "https://edith.xiaohongshu.com/api/sns/web/v1/login/qrcode/status"
        )
        ok = True
        status = 200

        async def json(self):
            return {"success": True, "data": {"login_info": {}}}

    driver = XiaohongshuQrLoginDriver(_ImmediateBrowserManager())

    await driver._handle_browser_response(Response())

    assert driver._browser_confirmed is True


@pytest.mark.asyncio
async def test_zhihu_open_adds_browser_id_to_later_requests(monkeypatch):
    requests: list[httpx.Request] = []

    async def handler(request: httpx.Request) -> httpx.Response:
        requests.append(request)
        if request.url.path == "/udid":
            return httpx.Response(200, request=request, text="browser-id")
        if request.url.path.endswith("/login/qrcode"):
            return httpx.Response(
                200,
                request=request,
                json={"token": "qr-token", "link": "zhihu://qr"},
            )
        return httpx.Response(
            200,
            request=request,
            headers={"set-cookie": "_xsrf=xsrf-value; Path=/"},
            json={},
        )

    client = httpx.AsyncClient(transport=httpx.MockTransport(handler))
    monkeypatch.setattr(drivers_module.httpx, "AsyncClient", lambda **_: client)
    driver = ZhihuQrLoginDriver()
    try:
        await driver.open()
        await driver.create_challenge()
    finally:
        await driver.close()

    qr_request = requests[-1]
    assert qr_request.headers["x-du-bid"] == "browser-id"
    assert qr_request.headers["x-xsrftoken"] == "xsrf-value"
    assert any(request.url.path.endswith("/oauth/captcha/v2") for request in requests)


@pytest.mark.asyncio
async def test_zhihu_poll_maps_http_40352_to_human_verification():
    async def handler(request: httpx.Request) -> httpx.Response:
        return httpx.Response(
            403,
            request=request,
            json={
                "error": {
                    "code": 40352,
                    "redirect": "https://www.zhihu.com/account/unhuman?session=safe",
                }
            },
        )

    driver = ZhihuQrLoginDriver()
    driver._client = httpx.AsyncClient(transport=httpx.MockTransport(handler))
    driver._token = "secret-token"
    try:
        result = await driver.poll()
    finally:
        await driver.close()

    assert result.state == QrLoginState.NEEDS_CAPTCHA
    assert result.captcha_url == "https://www.zhihu.com/account/unhuman?session=safe"


@pytest.mark.asyncio
async def test_zhihu_http_error_does_not_expose_qr_token():
    async def handler(request: httpx.Request) -> httpx.Response:
        return httpx.Response(403, request=request, json={"error": {"code": 1}})

    driver = ZhihuQrLoginDriver()
    driver._client = httpx.AsyncClient(transport=httpx.MockTransport(handler))
    driver._token = "secret-token"
    try:
        with pytest.raises(RuntimeError) as exc_info:
            await driver.poll()
    finally:
        await driver.close()

    message = str(exc_info.value)
    assert "HTTP 403" in message
    assert "secret-token" not in message
