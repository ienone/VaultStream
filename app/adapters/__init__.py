"""
适配器工厂
"""
from typing import Optional
from app.adapters.base import PlatformAdapter
from app.adapters.bilibili import BilibiliAdapter
from app.models import Platform


class AdapterFactory:
    """适配器工厂"""
    
    @staticmethod
    def create(platform: Platform, **kwargs) -> PlatformAdapter:
        """创建适配器实例"""
        if platform == Platform.BILIBILI:
            return BilibiliAdapter(**kwargs)
        # 未来可以在这里添加其他平台
        raise ValueError(f"不支持的平台: {platform}")
    
    @staticmethod
    def detect_platform(url: str) -> Optional[Platform]:
        """从URL检测平台"""
        if 'bilibili.com' in url or 'b23.tv' in url:
            return Platform.BILIBILI
        # 未来添加其他平台检测
        return None
