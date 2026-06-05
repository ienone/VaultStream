from __future__ import annotations

from typing import Any, Optional

from pydantic import SecretStr

from app.core.db_adapter import AsyncSessionLocal
from app.models import SystemSetting
from app.services.config_service import ConfigService
from app.utils.sensitive_display import (
    ENV_CONFIGURED_PLACEHOLDER,
    extract_secret_value,
)


_SETTINGS_CACHE: dict[str, Any] = {}


def _service() -> ConfigService:
    return ConfigService(session_factory=AsyncSessionLocal, cache=_SETTINGS_CACHE)


def _secret_value(value: Any) -> str | None:
    """Backwards-compatible secret extraction helper for tests and legacy callers."""
    return extract_secret_value(value)


def _resolve_env_display(value: Any, is_secret: bool = False) -> str | None:
    """Return a safe display value for env-backed settings."""
    text = _secret_value(value)
    if text is None:
        return None
    if is_secret or isinstance(value, SecretStr):
        return ENV_CONFIGURED_PLACEHOLDER
    return text


async def get_setting_value(key: str, default: Any = None) -> Any:
    return await _service().get_value(key, default)


async def get_setting_value_fresh(key: str, default: Any = None) -> Any:
    return await _service().get_value_fresh(key, default)


async def set_setting_value(
    key: str,
    value: Any,
    category: str = "general",
    description: Optional[str] = None,
) -> SystemSetting:
    return await _service().set_value(
        key,
        value,
        category=category,
        description=description,
    )


async def load_all_settings_to_memory() -> None:
    await _service().load_all_to_memory()


async def delete_setting_value(key: str) -> bool:
    return await _service().delete_value(key)


async def list_settings_values(category: Optional[str] = None) -> list[dict[str, Any]]:
    return await _service().list_values(category)


def invalidate_setting_cache(key: str) -> None:
    _service().invalidate(key)
