"""
时间工具函数
"""
from datetime import datetime, timezone


def utcnow() -> datetime:
    """返回 UTC 时间的当前时间戳（无时区信息）"""
    return datetime.now(timezone.utc).replace(tzinfo=None)
