"""Utilities for presenting sensitive values safely in API responses."""

from __future__ import annotations

from typing import Any

from pydantic import SecretStr


ENV_CONFIGURED_PLACEHOLDER = "*** [Configured via .env] ***"
DB_CONFIGURED_PLACEHOLDER = "*** [Configured] ***"


# Keep this focused on keys stored in system_settings.
SENSITIVE_SETTING_KEYS = {
    "api_token",
    "napcat_access_token",
    "bilibili_sessdata",
    "bilibili_bili_jct",
    "bilibili_buvid3",
    "xiaohongshu_cookie",
    "zhihu_cookie",
    "weibo_cookie",
    "text_llm_api_key",
    "vision_llm_api_key",
    "embedding_api_key",
}


def extract_secret_value(value: Any) -> str | None:
    """Extract raw secret text from SecretStr/plain string values."""
    if value is None:
        return None
    if isinstance(value, SecretStr):
        raw = value.get_secret_value()
        return raw if raw else None

    text = str(value)
    if not text:
        return None
    return text


def is_sensitive_setting_key(key: str) -> bool:
    return key in SENSITIVE_SETTING_KEYS


def as_configured_placeholder(value: Any, *, source: str = "db") -> str | None:
    """Return a configured marker if value exists, otherwise None."""
    if not extract_secret_value(value):
        return None
    if source == "env":
        return ENV_CONFIGURED_PLACEHOLDER
    return DB_CONFIGURED_PLACEHOLDER


def mask_token_partial(token: str | None, *, head: int = 6, tail: int = 4) -> str | None:
    """Mask token while keeping small head/tail fragments for identification."""
    if not token:
        return None

    normalized = token.strip()
    if not normalized:
        return None

    if len(normalized) <= head + tail:
        return "*" * len(normalized)
    return f"{normalized[:head]}***{normalized[-tail:]}"
