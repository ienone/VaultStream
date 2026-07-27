import httpx
import pytest

from app.services.platform_auth import BilibiliQrLoginDriver, QrLoginState


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
