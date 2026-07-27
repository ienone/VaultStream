import asyncio

import pytest

from app.services.browser_auth_service import AuthSession, BrowserAuthService
from app.services.platform_auth import (
    QrLoginChallenge,
    QrLoginDriver,
    QrLoginPollResult,
    QrLoginState,
)


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

    async def get_platform_cookie_string(self, platform: str, **_kwargs):
        return self.values.get(f"{platform}_cookie")


class _FakeDriver(QrLoginDriver):
    poll_interval = 0
    timeout = 1

    def __init__(self, results: list[QrLoginPollResult]) -> None:
        self.results = results
        self.closed = False

    async def open(self) -> None:
        return None

    async def create_challenge(self) -> QrLoginChallenge:
        return QrLoginChallenge("https://example.com/login", "请扫码")

    async def poll(self) -> QrLoginPollResult:
        return self.results.pop(0)

    async def close(self) -> None:
        self.closed = True


class _WaitingDriver(_FakeDriver):
    poll_interval = 60

    def __init__(self) -> None:
        super().__init__([])


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
async def test_logout_bilibili_clears_all_credential_fields():
    config = _FakeConfigService(
        {
            "bilibili_cookie": "SESSDATA=secret",
            "bilibili_bili_jct": "csrf",
            "bilibili_buvid3": "device",
        }
    )
    service = BrowserAuthService(config_service=config)

    await service.logout_platform("bilibili")

    assert config.deleted == [
        "bilibili_cookie",
        "bilibili_bili_jct",
        "bilibili_buvid3",
    ]
    assert config.values == {}


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


@pytest.mark.asyncio
async def test_qr_driver_flow_publishes_success_and_persists_cookie():
    config = _FakeConfigService()
    driver = _FakeDriver(
        [
            QrLoginPollResult(QrLoginState.SCANNED, "已扫码"),
            QrLoginPollResult(QrLoginState.SUCCESS, "登录成功", "SESSDATA=ok"),
        ]
    )
    service = BrowserAuthService(
        config_service=config,
        driver_factories={"bilibili": lambda: driver},
    )

    initial = await service.start_auth_session("bilibili")
    await service.sessions[initial.session_id].task
    final = await service.get_session_status(initial.session_id)

    assert final.status == "success"
    assert config.values["bilibili_cookie"] == "SESSDATA=ok"
    assert driver.closed is True


@pytest.mark.asyncio
async def test_qr_driver_flow_maps_expiry_to_timeout_without_persisting():
    config = _FakeConfigService()
    driver = _FakeDriver(
        [QrLoginPollResult(QrLoginState.EXPIRED, "二维码已过期")]
    )
    service = BrowserAuthService(
        config_service=config,
        driver_factories={"bilibili": lambda: driver},
    )

    initial = await service.start_auth_session("bilibili")
    await service.sessions[initial.session_id].task
    final = await service.get_session_status(initial.session_id)

    assert final.status == "timeout"
    assert final.message == "二维码已过期"
    assert config.set_calls == []
    assert driver.closed is True


@pytest.mark.asyncio
async def test_cancel_session_waits_for_driver_cleanup():
    driver = _WaitingDriver()
    service = BrowserAuthService(
        config_service=_FakeConfigService(),
        driver_factories={"bilibili": lambda: driver},
    )
    initial = await service.start_auth_session("bilibili")
    await asyncio.sleep(0)

    await service.cancel_session(initial.session_id)

    assert initial.session_id not in service.sessions
    assert driver.closed is True
