"""
URL处理工具模块

提供URL规范化、平台特定URL处理等功能
"""
from datetime import datetime, timezone
from urllib.parse import urlparse, urlunparse, parse_qsl, urlencode


# 需要移除的追踪参数key集合
_TRACKING_QUERY_KEYS = {
    "gclid",
    "fbclid",
    "spm_id_from",
    "from_source",
    "vd_source",
}


def normalize_datetime_for_db(dt: datetime | None) -> datetime | None:
    """
    将 datetime 规范化为 UTC 且去除 tzinfo（返回 naive UTC datetime），或返回 None
    
    原因：模型中使用的 `utcnow()` 返回的是无时区（naive）的 UTC 时间，为避免
    将带时区的 datetime 直接写入导致 asyncpg 抛出类型不匹配错误，
    我们在写入 DB 前将带时区 datetime 转为 UTC 并去除 tzinfo
    
    Args:
        dt: 待规范化的datetime对象，可以为None
        
    Returns:
        规范化后的naive UTC datetime，或None
        
    Examples:
        >>> from datetime import datetime, timezone
        >>> dt = datetime(2024, 1, 1, 12, 0, 0, tzinfo=timezone.utc)
        >>> result = normalize_datetime_for_db(dt)
        >>> result.tzinfo is None
        True
    """
    if dt is None:
        return None
    if not isinstance(dt, datetime):
        return dt
    if dt.tzinfo is None:
        return dt
    return dt.astimezone(timezone.utc).replace(tzinfo=None)


def canonicalize_url(url: str) -> str:
    """
    通用 URL 规范化处理
    
    执行以下规范化操作：
    - 去首尾空白
    - 若缺少 scheme，默认补 https
    - host 小写
    - 移除 fragment（#片段）
    - 移除常见追踪参数（utm_* + 若干常见 key）
    
    注意：平台短链解析由 adapter.clean_url 负责
    
    Args:
        url: 待规范化的URL字符串
        
    Returns:
        规范化后的URL字符串
        
    Examples:
        >>> canonicalize_url("example.com/path?utm_source=test")
        'https://example.com/path'
    """
    val = (url or "").strip()
    if not val:
        return val

    # 如果没有协议头，默认添加https
    if not val.startswith(("http://", "https://")):
        val = "https://" + val

    parsed = urlparse(val)
    # 域名转小写
    host = (parsed.netloc or "").lower()

    # 过滤查询参数：移除utm_*和追踪参数
    query_pairs = parse_qsl(parsed.query, keep_blank_values=True)
    filtered = []
    for k, v in query_pairs:
        lk = k.lower()
        # 移除utm_开头的参数
        if lk.startswith("utm_"):
            continue
        # 移除已知的追踪参数
        if lk in _TRACKING_QUERY_KEYS:
            continue
        filtered.append((k, v))

    new_query = urlencode(filtered, doseq=True)
    # 重构URL：使用规范化的host和query，移除fragment
    normalized = parsed._replace(netloc=host, query=new_query, fragment="")
    return urlunparse(normalized)


def normalize_bilibili_url(url_or_id: str) -> str:
    """
    规范化 B 站 URL，支持 BV/av/cv 号
    
    可以处理以下格式：
    - 完整URL: https://www.bilibili.com/video/BVxxx
    - BV号: BV1xx411c7Xg
    - av号: av12345678
    - cv号: cv12345678
    
    Args:
        url_or_id: B站URL或ID字符串
        
    Returns:
        规范化后的完整B站URL
        
    Examples:
        >>> normalize_bilibili_url("BV1xx411c7Xg")
        'https://www.bilibili.com/video/BV1xx411c7Xg'
        >>> normalize_bilibili_url("cv12345")
        'https://www.bilibili.com/read/cv12345'
    """
    val = url_or_id.strip()
    # 如果已经是完整URL，直接返回
    if val.startswith(('http://', 'https://')):
        return val
    
    # 处理BV/av/cv号
    val_lower = val.lower()
    if val_lower.startswith('bv'):
        return f"https://www.bilibili.com/video/{val}"
    elif val_lower.startswith('av'):
        return f"https://www.bilibili.com/video/{val}"
    elif val_lower.startswith('cv'):
        return f"https://www.bilibili.com/read/{val}"
    
    return val
