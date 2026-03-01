from typing import Optional, Dict, Type, Any
from app.models import Platform
from .base import PlatformAdapter, ParsedContent
from .bilibili import BilibiliAdapter
from .weibo import WeiboAdapter
from .twitter import TwitterAdapter
from .xiaohongshu import XiaohongshuAdapter
from .zhihu import ZhihuAdapter
from .universal_adapter import UniversalAdapter

class AdapterFactory:
    _adapters: Dict[Platform, Type[PlatformAdapter]] = {
        Platform.BILIBILI: BilibiliAdapter,
        Platform.WEIBO: WeiboAdapter,
        Platform.TWITTER: TwitterAdapter,
        Platform.XIAOHONGSHU: XiaohongshuAdapter,
        Platform.ZHIHU: ZhihuAdapter,
    }

    @staticmethod
    def detect_platform(url: str) -> Platform:
        url = url.lower()
        if "bilibili.com" in url or "b23.tv" in url:
            return Platform.BILIBILI
        if "weibo.com" in url or "weibo.cn" in url:
            return Platform.WEIBO
        if "twitter.com" in url or "x.com" in url:
            return Platform.TWITTER
        if "xiaohongshu.com" in url or "xhslink.com" in url:
            return Platform.XIAOHONGSHU
        if "zhihu.com" in url:
            return Platform.ZHIHU
        return Platform.OTHER

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
    "UniversalAdapter",
    "AdapterFactory",
]
