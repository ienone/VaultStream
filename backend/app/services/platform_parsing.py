"""Shared construction helpers for platform parsing adapters."""

from __future__ import annotations

from contextlib import asynccontextmanager
from typing import AsyncIterator

from app.adapters import AdapterFactory, PlatformAdapter, managed_adapter
from app.core.config import settings
from app.models import Platform
from app.services.config_service import ConfigService


async def create_configured_adapter(platform: Platform) -> PlatformAdapter:
    """Create an adapter with the same persisted credentials used in production.

    Browser-assisted login stores a complete ``<platform>_cookie`` value in the
    settings table.  Older Bilibili installations may still provide the three
    split environment variables, so those remain an environment-only fallback.
    """

    raw_cookie = await ConfigService().get_platform_cookie_string(
        platform.value,
        fresh=True,
    )
    cookies = PlatformAdapter.parse_cookie_str(raw_cookie) if raw_cookie else {}

    if platform == Platform.BILIBILI and not cookies:
        for key, setting_name in (
            ("SESSDATA", "bilibili_sessdata"),
            ("bili_jct", "bilibili_bili_jct"),
            ("buvid3", "bilibili_buvid3"),
        ):
            secret = getattr(settings, setting_name, None)
            if secret:
                cookies[key] = secret.get_secret_value()

    adapter_kwargs = {}
    if platform == Platform.ZHIHU and raw_cookie:
        adapter_kwargs["raw_cookie_str"] = raw_cookie

    return AdapterFactory.create(
        platform,
        cookies=cookies,
        **adapter_kwargs,
    )


@asynccontextmanager
async def open_configured_adapter(
    platform: Platform,
) -> AsyncIterator[PlatformAdapter]:
    """Open a configured adapter and always close its resources."""

    adapter = await create_configured_adapter(platform)
    async with managed_adapter(adapter) as active_adapter:
        yield active_adapter
