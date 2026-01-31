"""
适配器工厂
"""
from typing import Optional
from app.adapters.base import PlatformAdapter
from app.adapters.bilibili import BilibiliAdapter
from app.adapters.twitter_fx import TwitterFxAdapter
from app.adapters.xiaohongshu import XiaohongshuAdapter
from app.adapters.weibo import WeiboAdapter
from app.adapters.zhihu import ZhihuAdapter
from app.adapters.universal_adapter import UniversalAdapter
from app.models import Platform


class AdapterFactory:
    """适配器工厂"""
    
    @staticmethod
    def create(platform: Platform, **kwargs) -> PlatformAdapter:
        """创建适配器实例"""
        if platform == Platform.BILIBILI:
            return BilibiliAdapter(**kwargs)
        elif platform == Platform.TWITTER:
            return TwitterFxAdapter(**kwargs)
        elif platform == Platform.XIAOHONGSHU:
            return XiaohongshuAdapter(**kwargs)
        elif platform == Platform.WEIBO:
            return WeiboAdapter(**kwargs)
        elif platform == Platform.ZHIHU:
            return ZhihuAdapter(**kwargs)
        elif platform == Platform.UNIVERSAL:
            return UniversalAdapter(**kwargs)
        # 未来可以在这里添加其他平台
        raise ValueError(f"不支持的平台: {platform}")
    
    @staticmethod
    def detect_platform(url: str) -> Optional[Platform]:
        """从URL检测平台"""
        if 'bilibili.com' in url or 'b23.tv' in url:
            return Platform.BILIBILI
        elif 'twitter.com' in url or 'x.com' in url or 't.co' in url:
            return Platform.TWITTER
        elif 'xiaohongshu.com' in url or 'xhslink.com' in url:
            return Platform.XIAOHONGSHU
        elif 'weibo.com' in url or 'weibo.cn' in url or 'mapp.api.weibo.cn' in url:
            return Platform.WEIBO
        elif 'zhihu.com' in url:
            return Platform.ZHIHU
        # 默认返回通用平台适配器
        return Platform.UNIVERSAL
