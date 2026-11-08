"""Shared construction helpers for platform parsing adapters."""

from __future__ import annotations

from contextlib import asynccontextmanager
from typing import AsyncIterator

from app.adapters import AdapterFactory, PlatformAdapter, managed_adapter, close_adapter
from app.adapters.base import ParsedContent
from app.adapters.errors import PageExtractionRequired
from app.core.config import settings
from app.models import Platform
from app.services.config_service import ConfigService


async def create_configured_adapter(
    platform: Platform, *, include_video_media: bool = True,
) -> PlatformAdapter:
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
    if platform == Platform.BILIBILI:
        adapter_kwargs["include_video_media"] = include_video_media
    if platform == Platform.ZHIHU and raw_cookie:
        adapter_kwargs["raw_cookie_str"] = raw_cookie

    adapter = AdapterFactory.create(platform, cookies=cookies, **adapter_kwargs)
    return ConfiguredParser(adapter, platform, cookies) if platform != Platform.UNIVERSAL else adapter


class ConfiguredParser(PlatformAdapter):
    """原生解析优先；明确的结构变化才交给网页正文提取。"""

    def __init__(self, adapter: PlatformAdapter, platform: Platform, cookies: dict):
        self.adapter = adapter
        self.platform = platform
        self.cookies = cookies

    async def detect_content_type(self, url: str):
        return await self.adapter.detect_content_type(url)

    async def clean_url(self, url: str):
        return await self.adapter.clean_url(url)

    async def parse(self, url: str) -> ParsedContent:
        try:
            return await self.adapter.parse(url)
        except PageExtractionRequired as error:
            from app.adapters.universal_adapter import UniversalAdapter
            from app.adapters.utils.tiered_fetcher import FetchResult, fetch_rendered_page

            fetched = (FetchResult(url=url, content=error.html, html=error.html,
                                   content_type="html", source="browser")
                       if error.html else await fetch_rendered_page(url, cookies=self.cookies))
            reader = UniversalAdapter(cookies=self.cookies)
            reader.llm_config = await ConfigService().get_text_llm_config()
            parsed = await reader._do_parse(url, fetched=fetched)
            parsed.platform = self.platform.value
            parsed.content_id = error.content_id
            # A rendered page establishes readable text, not native statistics
            # or structured media. Keep its article layout and explicit origin.
            parsed.stats = {}
            parsed.archive_metadata["extraction"] = {
                "mode": "webpage_fallback", "native_content_type": error.content_type,
                "reason": str(error),
            }
            return parsed

    def map_stats_to_content(self, content, parsed: ParsedContent) -> None:
        self.adapter.map_stats_to_content(content, parsed)

    async def close(self) -> None:
        await close_adapter(self.adapter)


@asynccontextmanager
async def open_configured_adapter(
    platform: Platform, *, include_video_media: bool = True,
) -> AsyncIterator[PlatformAdapter]:
    """Open a configured adapter and always close its resources."""

    adapter = await create_configured_adapter(platform, include_video_media=include_video_media)
    async with managed_adapter(adapter) as active_adapter:
        yield active_adapter
