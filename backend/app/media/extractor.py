"""
媒体URL提取模块

从内容元数据中提取图片、视频等媒体URL
"""
from typing import List, Dict, Any, Literal
from urllib.parse import unquote, urlsplit, urlunsplit


MediaType = Literal["photo", "video"]


def _is_avatar_like(item: Dict[str, Any]) -> bool:
    """Return True when the media item is an avatar/profile image."""
    item_type = str(item.get("type") or "").strip().lower()
    if item_type in {"avatar", "profile_avatar", "author_avatar"}:
        return True
    if bool(item.get("is_avatar")):
        return True

    url = str(item.get("url") or item.get("stored_url") or "").lower()
    if "/avatar" in url or "avatar_" in url or "profile_image" in url:
        return True
    return False


def _normalize_media_identity(url: Any) -> str:
    """Normalize a media URL for stable avatar comparisons."""
    if not isinstance(url, str):
        return ""

    candidate = unquote(url.strip())
    if not candidate:
        return ""

    if candidate.startswith("local://"):
        return candidate.rstrip("/")

    try:
        parts = urlsplit(candidate)
    except ValueError:
        return candidate.rstrip("/")

    if parts.scheme or parts.netloc:
        path = parts.path.rstrip("/") or "/"
        return urlunsplit((parts.scheme.lower(), parts.netloc.lower(), path, "", ""))

    return candidate.rstrip("/")


def is_avatar_media_url(url: Any, author_avatar_url: str | None = None) -> bool:
    """Return True when the URL is the author avatar or an avatar-like fallback."""
    identity = _normalize_media_identity(url)
    if not identity:
        return False

    avatar_identity = _normalize_media_identity(author_avatar_url)
    if avatar_identity:
        return identity == avatar_identity

    return _is_avatar_like({"url": url})


def sanitize_media_urls(
    media_urls: Any,
    *,
    author_avatar_url: str | None = None,
) -> List[str]:
    """Drop empty/duplicate media URLs and filter out author avatars."""
    if not isinstance(media_urls, list):
        return []

    sanitized: List[str] = []
    seen: set[str] = set()
    for item in media_urls:
        if not isinstance(item, str):
            continue

        url = item.strip()
        if not url or url in seen:
            continue

        if is_avatar_media_url(url, author_avatar_url=author_avatar_url):
            continue

        seen.add(url)
        sanitized.append(url)

    return sanitized


def extract_media_urls(
    archive_metadata: Dict[str, Any],
    cover_url: str = None,
    prefer_stored: bool = False
) -> List[Dict[str, Any]]:
    """从归档条目选取来源或本地地址，过滤头像；空结果使用封面。"""
    archive = archive_metadata.get("archive") if isinstance(archive_metadata, dict) else None
    archive = archive if isinstance(archive, dict) else {}
    media_items = []
    for collection, kind in (("images", "photo"), ("videos", "video")):
        for item in archive.get(collection) or []:
            if not isinstance(item, dict) or (kind == "photo" and _is_avatar_like(item)):
                continue
            stored_url = item.get("stored_url")
            if item.get("stored_key"):
                stored_url = f"local://{item['stored_key']}"
            source_url = item.get("url")
            url = (stored_url or source_url) if prefer_stored else (source_url or stored_url)
            if url:
                result = {"type": kind, "url": url}
                if item.get("stored_key"):
                    result["stored_key"] = item["stored_key"]
                media_items.append(result)
    if not media_items and isinstance(cover_url, str) and cover_url.strip():
        media_items.append({"type": "photo", "url": cover_url.strip()})
    return media_items


def pick_preview_thumbnail(
    archive_metadata: Dict[str, Any],
    cover_url: str = None,
) -> str | None:
    """返回用于列表预览的首图 URL。"""
    items = extract_media_urls(archive_metadata or {}, cover_url=cover_url)
    if not items:
        return cover_url
    first = items[0]
    if isinstance(first, dict):
        return first.get("url") or cover_url
    return cover_url
