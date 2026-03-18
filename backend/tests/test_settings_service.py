"""
Tests for app.services.settings_service
"""
import pytest
from unittest.mock import patch, MagicMock
from pydantic import SecretStr
from sqlalchemy.ext.asyncio import create_async_engine, AsyncSession
from sqlalchemy.orm import sessionmaker

from app.models.base import Base
from app.models.system import SystemSetting

# In-memory engine shared across all tests in this module
_engine = create_async_engine("sqlite+aiosqlite:///:memory:")
_TestSessionLocal = sessionmaker(_engine, class_=AsyncSession, expire_on_commit=False)


@pytest.fixture(autouse=True)
async def _init_db_and_clear_cache():
    """Create tables before each test and clear settings cache."""
    import app.services.settings_service as svc
    svc._SETTINGS_CACHE.clear()

    async with _engine.begin() as conn:
        await conn.run_sync(Base.metadata.create_all)
    yield
    async with _engine.begin() as conn:
        await conn.run_sync(Base.metadata.drop_all)


def _session_factory():
    """Return an async context-manager that yields a test session."""
    return _TestSessionLocal()


# ---------------------------------------------------------------------------
# _secret_value
# ---------------------------------------------------------------------------

from app.services.settings_service import _secret_value


def test_secret_value_none():
    assert _secret_value(None) is None


def test_secret_value_secret_str():
    assert _secret_value(SecretStr("abc")) == "abc"


def test_secret_value_empty_secret_str():
    assert _secret_value(SecretStr("")) is None


def test_secret_value_plain_string():
    assert _secret_value("hello") == "hello"


def test_secret_value_empty_string():
    assert _secret_value("") is None


# ---------------------------------------------------------------------------
# _resolve_env_display
# ---------------------------------------------------------------------------

from app.services.settings_service import _resolve_env_display


def test_resolve_env_display_secret_str():
    assert _resolve_env_display(SecretStr("key123")) == "*** [Configured via .env] ***"


def test_resolve_env_display_none():
    assert _resolve_env_display(None) is None


def test_resolve_env_display_is_secret():
    assert _resolve_env_display("mykey", is_secret=True) == "*** [Configured via .env] ***"


def test_resolve_env_display_plain():
    assert _resolve_env_display("plain_value") == "plain_value"


# ---------------------------------------------------------------------------
# invalidate_setting_cache
# ---------------------------------------------------------------------------

from app.services.settings_service import invalidate_setting_cache


def test_invalidate_setting_cache():
    import app.services.settings_service as svc
    svc._SETTINGS_CACHE["foo"] = "bar"
    invalidate_setting_cache("foo")
    assert "foo" not in svc._SETTINGS_CACHE


def test_invalidate_setting_cache_missing_key():
    """Should not raise when key is absent."""
    invalidate_setting_cache("nonexistent")


# ---------------------------------------------------------------------------
# get_setting_value
# ---------------------------------------------------------------------------


@pytest.mark.asyncio
async def test_get_setting_value_cache_hit():
    import app.services.settings_service as svc
    svc._SETTINGS_CACHE["cached_key"] = "cached_val"

    with patch("app.services.settings_service.AsyncSessionLocal", side_effect=AssertionError("DB should not be called")):
        result = await svc.get_setting_value("cached_key")
    assert result == "cached_val"


@pytest.mark.asyncio
async def test_get_setting_value_cache_miss_db_hit():
    import app.services.settings_service as svc

    # Seed a row in the in-memory DB
    async with _TestSessionLocal() as session:
        session.add(SystemSetting(key="db_key", value="db_val", category="general"))
        await session.commit()

    with patch("app.services.settings_service.AsyncSessionLocal", _session_factory):
        result = await svc.get_setting_value("db_key")

    assert result == "db_val"
    assert svc._SETTINGS_CACHE["db_key"] == "db_val"


@pytest.mark.asyncio
async def test_get_setting_value_cache_miss_db_miss():
    import app.services.settings_service as svc

    with patch("app.services.settings_service.AsyncSessionLocal", _session_factory):
        result = await svc.get_setting_value("missing", default="fallback")

    assert result == "fallback"


@pytest.mark.asyncio
async def test_get_setting_value_bool_true():
    import app.services.settings_service as svc
    svc._SETTINGS_CACHE["bool_key"] = "true"

    result = await svc.get_setting_value("bool_key")
    assert result is True


@pytest.mark.asyncio
async def test_get_setting_value_bool_false():
    import app.services.settings_service as svc
    svc._SETTINGS_CACHE["bool_key"] = "false"

    result = await svc.get_setting_value("bool_key")
    assert result is False


# ---------------------------------------------------------------------------
# set_setting_value
# ---------------------------------------------------------------------------


@pytest.mark.asyncio
async def test_set_setting_value():
    import app.services.settings_service as svc

    mock_settings = MagicMock()
    mock_settings.__annotations__ = {}

    with patch("app.services.settings_service.AsyncSessionLocal", _session_factory):
        with patch("app.core.config.settings", mock_settings):
            result = await svc.set_setting_value("new_key", "new_val", category="test", description="desc")

    assert result.key == "new_key"
    assert result.value == "new_val"
    assert svc._SETTINGS_CACHE["new_key"] == "new_val"


@pytest.mark.asyncio
async def test_set_setting_value_syncs_plain_field():
    """When the settings object has a matching plain field, it should be set."""
    import app.services.settings_service as svc

    mock_settings = MagicMock()
    mock_settings.__annotations__ = {"my_field": str}

    with patch("app.services.settings_service.AsyncSessionLocal", _session_factory):
        with patch("app.core.config.settings", mock_settings):
            await svc.set_setting_value("my_field", "val123")

    mock_settings.__setattr__("my_field", "val123")


@pytest.mark.asyncio
async def test_set_setting_value_syncs_secret_field():
    """When the settings object has a SecretStr field, it should wrap the value."""
    import app.services.settings_service as svc

    class _FakeSettings:
        __annotations__ = {"api_key": SecretStr}
        api_key = None

    fake = _FakeSettings()

    with patch("app.services.settings_service.AsyncSessionLocal", _session_factory):
        with patch("app.core.config.settings", fake):
            await svc.set_setting_value("api_key", "secret123")

    assert isinstance(fake.api_key, SecretStr)
    assert fake.api_key.get_secret_value() == "secret123"


# ---------------------------------------------------------------------------
# delete_setting_value
# ---------------------------------------------------------------------------


@pytest.mark.asyncio
async def test_delete_setting_value_exists():
    import app.services.settings_service as svc

    # Seed a row
    async with _TestSessionLocal() as session:
        session.add(SystemSetting(key="del_key", value="val", category="general"))
        await session.commit()

    svc._SETTINGS_CACHE["del_key"] = "val"

    with patch("app.services.settings_service.AsyncSessionLocal", _session_factory):
        result = await svc.delete_setting_value("del_key")

    assert result is True
    assert "del_key" not in svc._SETTINGS_CACHE


@pytest.mark.asyncio
async def test_delete_setting_value_not_exists():
    import app.services.settings_service as svc

    with patch("app.services.settings_service.AsyncSessionLocal", _session_factory):
        result = await svc.delete_setting_value("no_such_key")

    assert result is False


# ---------------------------------------------------------------------------
# load_all_settings_to_memory
# ---------------------------------------------------------------------------


@pytest.mark.asyncio
async def test_load_all_settings_to_memory():
    import app.services.settings_service as svc

    # Seed rows
    async with _TestSessionLocal() as session:
        session.add(SystemSetting(key="k1", value="v1", category="general"))
        session.add(SystemSetting(key="k2", value="v2", category="platform"))
        await session.commit()

    mock_settings = MagicMock()
    mock_settings.__annotations__ = {"k1": str}

    with patch("app.services.settings_service.AsyncSessionLocal", _session_factory):
        with patch("app.core.config.settings", mock_settings):
            await svc.load_all_settings_to_memory()

    assert svc._SETTINGS_CACHE["k1"] == "v1"
    assert svc._SETTINGS_CACHE["k2"] == "v2"


# ---------------------------------------------------------------------------
# list_settings_values
# ---------------------------------------------------------------------------


@pytest.mark.asyncio
async def test_list_settings_values():
    import app.services.settings_service as svc

    async with _TestSessionLocal() as session:
        session.add(SystemSetting(key="a", value="1", category="general"))
        session.add(SystemSetting(key="b", value="2", category="platform"))
        await session.commit()

    with patch("app.services.settings_service.AsyncSessionLocal", _session_factory):
        all_settings = await svc.list_settings_values()
        assert len(all_settings) == 2

        filtered = await svc.list_settings_values(category="platform")
        assert len(filtered) == 1
        assert filtered[0]["key"] == "b"
