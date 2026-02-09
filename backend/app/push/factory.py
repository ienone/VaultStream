"""
推送服务工厂。

根据平台选择推送服务实现。
"""
from .base import BasePushService
from .telegram import TelegramPushService
from .napcat import NapcatPushService

# 全局单例缓存
_push_service_cache: dict[str, BasePushService] = {}

def get_push_service(platform: str = "telegram") -> BasePushService:
    """
    获取推送服务实例。

    Args:
        platform: 平台名称 (例如 "telegram", "qq")

    Returns:
        推送服务实例

    Raises:
        ValueError: 不支持的平台
    """
    platform = platform.lower()

    if platform in _push_service_cache:
        return _push_service_cache[platform]

    if platform == "telegram":
        service = TelegramPushService()
    elif platform == "qq":
        service = NapcatPushService()
    else:
        raise ValueError(f"Unsupported push platform: {platform}")

    _push_service_cache[platform] = service
    return service

async def close_all_push_services() -> None:
    """关闭所有推送服务连接。"""
    for service in _push_service_cache.values():
        await service.close()
    _push_service_cache.clear()
