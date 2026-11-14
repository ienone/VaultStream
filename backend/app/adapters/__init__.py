import inspect
from contextlib import asynccontextmanager
from typing import AsyncIterator, Optional, Dict, Type, Any
from urllib.parse import urlparse
from app.models import Platform
from .base import PlatformAdapter, ParsedContent
from .bilibili import BilibiliAdapter
from .weibo import WeiboAdapter
from .twitter import TwitterAdapter
from .xiaohongshu import XiaohongshuAdapter
from .zhihu import ZhihuAdapter
from .telegram import TelegramAdapter
from .rss import RssAdapter
from .universal_adapter import UniversalAdapter

_PLATFORM_HOSTS = {
    Platform.BILIBILI: ("bilibili.com", "b23.tv"),
    Platform.WEIBO: ("weibo.com", "weibo.cn"),
    Platform.TWITTER: ("twitter.com", "x.com"),
    Platform.XIAOHONGSHU: ("xiaohongshu.com", "xhslink.com"),
    Platform.ZHIHU: ("zhihu.com",),
    Platform.TELEGRAM: ("t.me", "telegram.org"),
}


class AdapterFactory:
    _adapters: Dict[Platform, Type[PlatformAdapter]] = {
        Platform.BILIBILI: BilibiliAdapter,
        Platform.WEIBO: WeiboAdapter,
        Platform.TWITTER: TwitterAdapter,
        Platform.XIAOHONGSHU: XiaohongshuAdapter,
        Platform.ZHIHU: ZhihuAdapter,
        Platform.TELEGRAM: TelegramAdapter,
        Platform.RSS: RssAdapter,
    }

    @staticmethod
    def detect_platform(url: str) -> Platform:
        parsed = urlparse(url)
        host = (parsed.hostname or "").lower().rstrip(".")
        path = parsed.path.lower()
        for platform, domains in _PLATFORM_HOSTS.items():
            if any(host == domain or host.endswith("." + domain) for domain in domains):
                return platform
        if (
            path.endswith((".xml", ".rss", ".atom"))
            or path in ("/feed", "/rss", "/atom")
            or "/feed/" in path
            or "/rss/" in path
            or "/atom/" in path
        ):
            return Platform.RSS
        return Platform.UNIVERSAL

    @classmethod
    def create(cls, platform: Platform, cookies: Optional[Dict[str, str]] = None, **kwargs: Any) -> PlatformAdapter:
        adapter_cls = cls._adapters.get(platform, UniversalAdapter)
        return adapter_cls(cookies=cookies, **kwargs)


async def close_adapter(adapter: Any) -> None:
    close = getattr(adapter, "close", None)
    if close is None:
        return
    result = close()
    if inspect.isawaitable(result):
        await result


@asynccontextmanager
async def managed_adapter(adapter: PlatformAdapter) -> AsyncIterator[PlatformAdapter]:
    try:
        yield adapter
    finally:
        await close_adapter(adapter)


@asynccontextmanager
async def open_adapter(
    platform: Platform,
    cookies: Optional[Dict[str, str]] = None,
    **kwargs: Any,
) -> AsyncIterator[PlatformAdapter]:
    adapter = AdapterFactory.create(platform, cookies=cookies, **kwargs)
    async with managed_adapter(adapter) as active_adapter:
        yield active_adapter

__all__ = [
    "PlatformAdapter",
    "ParsedContent",
    "BilibiliAdapter",
    "WeiboAdapter",
    "TwitterAdapter",
    "XiaohongshuAdapter",
    "ZhihuAdapter",
    "TelegramAdapter",
    "RssAdapter",
    "UniversalAdapter",
    "AdapterFactory",
    "close_adapter",
    "managed_adapter",
    "open_adapter",
]
