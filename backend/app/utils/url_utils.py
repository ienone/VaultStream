"""
URL处理工具模块

提供URL规范化、平台特定URL处理等功能
"""
import re
from urllib.parse import urlparse, urlunparse, parse_qsl, urlencode


# 需要移除的追踪参数key集合
_TRACKING_QUERY_KEYS = {
    "gclid",
    "fbclid",
    "spm_id_from",
    "from_source",
    "vd_source",
}

_URL_PATTERN = re.compile(
    r"https?://[^\s<>\"')\]]+",
    re.IGNORECASE,
)
_BILIBILI_ID_PATTERN = re.compile(
    r"(?P<id>BV[0-9A-Za-z]{10}|av\d+|cv\d+)",
    re.IGNORECASE,
)
_SCHEMELESS_URL_PATTERN = re.compile(
    r"^(?:www\.)?(?:[a-z0-9-]+\.)+[a-z]{2,}(?:[/?#][^\s<>\"')\]]*)?$",
    re.IGNORECASE,
)
_TRAILING_URL_PUNCTUATION = ",.;:!?)]}，。；：！？）】》」』、"


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


def normalize_url_for_dedup(url: str) -> str:
    """
    用于跨源去重的 URL 规范化。

    在 canonicalize_url 基础上额外执行：
    - 去除 www. 前缀
    - 去除尾部斜杠
    - scheme 统一为 https

    Args:
        url: 待规范化的 URL

    Returns:
        去重用的规范化 URL
    """
    val = canonicalize_url(url)
    if not val:
        return val

    parsed = urlparse(val)

    host = parsed.netloc
    if host.startswith("www."):
        host = host[4:]

    path = parsed.path.rstrip("/")

    normalized = parsed._replace(scheme="https", netloc=host, path=path)
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


def _strip_trailing_url_punctuation(url: str) -> str:
    """移除提取 URL 时常见的尾随标点。"""
    cleaned = url or ""
    while cleaned and cleaned[-1] in _TRAILING_URL_PUNCTUATION:
        cleaned = cleaned[:-1]
    return cleaned


def extract_urls_from_text(text: str) -> list[str]:
    """从混合文本中提取所有 HTTP/HTTPS URL。"""
    if not text:
        return []

    results: list[str] = []
    for match in _URL_PATTERN.findall(text):
        cleaned = _strip_trailing_url_punctuation(match)
        if cleaned:
            results.append(cleaned)
    return results


def extract_primary_url_candidate(text: str) -> str:
    """从分享文案中提取首个 URL 或已知平台 ID。"""
    val = (text or "").strip()
    if not val:
        return val

    urls = extract_urls_from_text(val)
    if urls:
        return urls[0]

    bilibili_id_match = _BILIBILI_ID_PATTERN.search(val)
    if bilibili_id_match:
        return bilibili_id_match.group("id")

    return val


def is_url_like_input(text: str) -> bool:
    """判断输入是否像 URL 或已知平台分享 ID。"""
    val = (text or "").strip()
    if not val:
        return False
    if _URL_PATTERN.fullmatch(val):
        return True
    if _SCHEMELESS_URL_PATTERN.fullmatch(val):
        return True
    if _BILIBILI_ID_PATTERN.fullmatch(val):
        return True
    return False


def normalize_share_url_input(text: str) -> str:
    """将分享输入规整为可检测/可持久化的真实 URL。"""
    candidate = extract_primary_url_candidate(text)
    if not is_url_like_input(candidate):
        return (text or "").strip()
    return canonicalize_url(normalize_bilibili_url(candidate))
