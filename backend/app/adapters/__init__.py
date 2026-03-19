from typing import Optional, Dict, Type, Any
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
        lowered = url.lower()
        parsed = urlparse(lowered)
        path = (parsed.path or "").lower()

        if "bilibili.com" in lowered or "b23.tv" in lowered:
            return Platform.BILIBILI
        if "weibo.com" in lowered or "weibo.cn" in lowered:
            return Platform.WEIBO
        if "twitter.com" in lowered or "x.com" in lowered:
            return Platform.TWITTER
        if "xiaohongshu.com" in lowered or "xhslink.com" in lowered:
            return Platform.XIAOHONGSHU
        if "zhihu.com" in lowered:
            return Platform.ZHIHU
        if "t.me" in lowered or "telegram.org" in lowered:
            return Platform.TELEGRAM
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
        adapter_cls = cls._adapters.get(platform)
        if adapter_cls:
            # 兼容不同适配器的构造函数
            try:
                return adapter_cls(cookies=cookies, **kwargs)
            except TypeError:
                return adapter_cls(cookies=cookies)
        
        # 回退到通用适配器
        return UniversalAdapter(cookies=cookies, **kwargs)

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
]
