"""
API 响应基础模型 & 自定义类型

确保所有 naive datetime（假定为 UTC）序列化时带 'Z' 后缀，
避免 Dart DateTime.parse() 将其误判为本地时间。
"""
from datetime import datetime
from typing import Annotated, Optional

from pydantic import PlainSerializer


def _serialize_datetime_utc(dt: datetime) -> str:
    """将 naive datetime 序列化为带 Z 后缀的 ISO 字符串。"""
    if dt.tzinfo is None:
        return dt.isoformat() + "Z"
    return dt.isoformat()


def _serialize_datetime_utc_optional(dt: Optional[datetime]) -> Optional[str]:
    """可选版本：None 直通，非 None 则追加 Z。"""
    if dt is None:
        return None
    return _serialize_datetime_utc(dt)


UtcDatetime = Annotated[
    datetime,
    PlainSerializer(_serialize_datetime_utc, return_type=str, when_used="json"),
]

OptionalUtcDatetime = Annotated[
    Optional[datetime],
    PlainSerializer(_serialize_datetime_utc_optional, return_type=Optional[str], when_used="json"),
]
