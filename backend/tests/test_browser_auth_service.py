import pytest

from app.services.browser_auth_service import AuthSession, BrowserAuthService


class _FakeConfigService:
    def __init__(self, values: dict[str, object] | None = None) -> None:
        self.values = values or {}
        self.set_calls: list[dict[str, object]] = []
        self.deleted: list[str] = []

    async def get_value(self, key: str, default=None):
        return self.values.get(key, default)

    async def set_value(self, key: str, value, *, category: str = "general", description=None):
        self.values[key] = value
        self.set_calls.append(
            {
                "key": key,
                "value": value,
                "category": category,
                "description": description,
            }
        )

    async def delete_value(self, key: str) -> bool:
        self.deleted.append(key)
        return self.values.pop(key, None) is not None


@pytest.mark.asyncio
async def test_check_platform_status_reads_cookie_from_config():
    config = _FakeConfigService({"xiaohongshu_cookie": "a1=abc; web_session=ok"})
    service = BrowserAuthService(config_service=config)
    observed: dict[str, str] = {}

    async def _fake_check(cookie_str: str) -> bool:
        observed["cookie"] = cookie_str
        return True

    service._check_xiaohongshu_status = _fake_check

    assert await service.check_platform_status("xiaohongshu") is True
    assert observed["cookie"] == "a1=abc; web_session=ok"


@pytest.mark.asyncio
async def test_check_platform_status_returns_false_when_cookie_missing():
    service = BrowserAuthService(config_service=_FakeConfigService())

    assert await service.check_platform_status("xiaohongshu") is False


@pytest.mark.asyncio
async def test_logout_platform_deletes_cookie_from_config():
    config = _FakeConfigService({"zhihu_cookie": "z_c0=abc"})
    service = BrowserAuthService(config_service=config)

    await service.logout_platform("zhihu")

    assert config.deleted == ["zhihu_cookie"]
    assert "zhihu_cookie" not in config.values


@pytest.mark.asyncio
async def test_persist_cookie_writes_platform_cookie_to_config():
    config = _FakeConfigService()
    service = BrowserAuthService(config_service=config)
    session = AuthSession("weibo")
    session.cookie_str = "SUB=secret"

    await service._persist_cookie(session)

    assert config.values["weibo_cookie"] == "SUB=secret"
    assert config.set_calls == [
        {
            "key": "weibo_cookie",
            "value": "SUB=secret",
            "category": "platform",
            "description": "weibo 自动化登录 Cookie",
        }
    ]
