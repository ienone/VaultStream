"""
推送服务工厂

根据平台类型获取相应的推送服务实例
"""
from typing import Optional

from .base import BasePushService
from .telegram import TelegramPushService


# 全局单例缓存
_push_service_cache: dict[str, BasePushService] = {}


def get_push_service(platform: str = "telegram") -> BasePushService:
    """
    获取推送服务实例
    
    Args:
        platform: 平台名称（如 "telegram", "qq" 等）
        
    Returns:
        对应平台的推送服务实例
        
    Raises:
        ValueError: 不支持的平台类型
        
    Examples:
        >>> service = get_push_service("telegram")
        >>> await service.push(content, target_id)
    """
    platform = platform.lower()
    
    # 从缓存获取
    if platform in _push_service_cache:
        return _push_service_cache[platform]
    
    # 创建新实例
    if platform == "telegram":
        service = TelegramPushService()
        _push_service_cache[platform] = service
        return service
    else:
        raise ValueError(f"不支持的推送平台: {platform}")


async def close_all_push_services():
    """
    关闭所有推送服务连接
    
    在应用关闭时调用,清理资源
    """
    for service in _push_service_cache.values():
        await service.close()
    _push_service_cache.clear()
