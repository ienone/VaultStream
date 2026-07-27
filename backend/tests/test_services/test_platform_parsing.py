from unittest.mock import AsyncMock

import pytest
from pydantic import SecretStr

from app.models import Platform
from app.services.platform_parsing import create_configured_adapter


@pytest.mark.asyncio
async def test_create_configured_adapter_uses_persisted_bilibili_cookie(monkeypatch):
    get_cookie = AsyncMock(return_value="SESSDATA=db-session; bili_jct=db-csrf")
    monkeypatch.setattr(
        "app.services.platform_parsing.ConfigService.get_platform_cookie_string",
        get_cookie,
    )

    adapter = await create_configured_adapter(Platform.BILIBILI)

    assert adapter.cookies == {"SESSDATA": "db-session", "bili_jct": "db-csrf"}
    get_cookie.assert_awaited_once_with("bilibili", fresh=True)


@pytest.mark.asyncio
async def test_create_configured_adapter_keeps_split_bilibili_env_fallback(monkeypatch):
    monkeypatch.setattr(
        "app.services.platform_parsing.ConfigService.get_platform_cookie_string",
        AsyncMock(return_value=None),
    )
    monkeypatch.setattr("app.services.platform_parsing.settings.bilibili_sessdata", SecretStr("sess123"))
    monkeypatch.setattr("app.services.platform_parsing.settings.bilibili_bili_jct", SecretStr("jct456"))
    monkeypatch.setattr("app.services.platform_parsing.settings.bilibili_buvid3", SecretStr("buv789"))

    adapter = await create_configured_adapter(Platform.BILIBILI)

    assert adapter.cookies == {
        "SESSDATA": "sess123",
        "bili_jct": "jct456",
        "buvid3": "buv789",
    }


@pytest.mark.asyncio
async def test_create_configured_adapter_preserves_raw_zhihu_cookie(monkeypatch):
    raw_cookie = "z_c0=quoted-value; d_c0=device"
    monkeypatch.setattr(
        "app.services.platform_parsing.ConfigService.get_platform_cookie_string",
        AsyncMock(return_value=raw_cookie),
    )

    adapter = await create_configured_adapter(Platform.ZHIHU)

    assert adapter.cookies == {"z_c0": "quoted-value", "d_c0": "device"}
    assert adapter.raw_cookie_str == raw_cookie
