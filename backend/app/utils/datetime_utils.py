"""
时间处理工具模块

提供数据库写入前的 datetime 规范化功能
"""
from datetime import datetime, timezone


def normalize_datetime_for_db(dt: datetime | None) -> datetime | None:
    """
    将 datetime 规范化为 UTC 且去除 tzinfo（返回 naive UTC datetime），或返回 None

    原因：模型中使用的 `utcnow()` 返回的是无时区（naive）的 UTC 时间，为避免
    将带时区的 datetime 直接写入导致 asyncpg 抛出类型不匹配错误，
    我们在写入 DB 前将带时区 datetime 转为 UTC 并去除 tzinfo
    """
    if dt is None:
        return None
    if not isinstance(dt, datetime):
        return dt
    if dt.tzinfo is None:
        return dt
    return dt.astimezone(timezone.utc).replace(tzinfo=None)
