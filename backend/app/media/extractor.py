"""
媒体URL提取模块

从内容元数据中提取图片、视频等媒体URL
"""
from typing import List, Dict, Any, Literal


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


def extract_media_urls(
    archive_metadata: Dict[str, Any],
    cover_url: str = None,
    prefer_stored: bool = False
) -> List[Dict[str, Any]]:
    """
    从内容元数据中提取媒体URL
    
    优先级策略：
    1. 如果 prefer_stored=False（默认）：
       - 优先使用原始 CDN URL（archive.images[].url）
       - 如果原始URL不存在，使用存储URL（archive.images[].stored_url 或 stored_images[].url）
    2. 如果 prefer_stored=True：
       - 优先使用存储URL
       - 降级使用原始URL
    3. 如果都没有，使用 cover_url
    
    Args:
        archive_metadata: 内容的 archive_metadata 字段
        cover_url: 封面图URL（兜底）
        prefer_stored: 是否优先使用存储的URL（默认False，优先原始URL）
    
    Returns:
        媒体项列表，格式: [{"type": "photo|video", "url": "..."}]
    
    Examples:
        >>> metadata = {
        ...     "archive": {
        ...         "images": [
        ...             {"url": "https://cdn.com/1.jpg", "stored_url": "http://local/1.webp"},
        ...             {"stored_url": "http://local/2.webp"}  # 原始URL已失效
        ...         ]
        ...     }
        ... }
        >>> extract_media_urls(metadata)
        [
            {"type": "photo", "url": "https://cdn.com/1.jpg"},
            {"type": "photo", "url": "http://local/2.webp"}
        ]
    """
    # 兼容两种归档结构：
    # 1) archive_metadata["archive"]（多数解析器）
    # 2) archive_metadata["processed_archive"]（部分 V2 解析器）
    archive: Dict[str, Any] = {}
    if isinstance(archive_metadata, dict):
        if isinstance(archive_metadata.get('archive'), dict):
            archive = archive_metadata.get('archive') or {}
        elif isinstance(archive_metadata.get('processed_archive'), dict):
            archive = archive_metadata.get('processed_archive') or {}

    media_items = []
    
    # 处理图片
    images = archive.get('images', [])
    for img in images:
        if _is_avatar_like(img):
            continue

        url = None
        
        if prefer_stored:
            # 优先使用存储URL
            url = img.get('stored_url') or img.get('url')
        else:
            # 优先使用原始URL
            url = img.get('url') or img.get('stored_url')
        
        if url:
            item = {
                'type': 'photo',
                'url': url
            }
            if img.get('stored_key'):
                item['stored_key'] = img.get('stored_key')
            media_items.append(item)
    
    # 如果 images 为空或没有找到URL，尝试从 stored_images 获取
    if not media_items:
        stored_images = archive.get('stored_images', [])
        for img in stored_images:
            if _is_avatar_like(img):
                continue

            url = img.get('url')
            if url:
                item = {
                    'type': 'photo',
                    'url': url
                }
                if img.get('key'):
                    item['stored_key'] = img.get('key')
                media_items.append(item)
    
    # 处理视频
    videos = archive.get('videos', [])
    for vid in videos:
        url = None
        
        if prefer_stored:
            url = vid.get('stored_url') or vid.get('url')
        else:
            url = vid.get('url') or vid.get('stored_url')
        
        if url:
            item = {
                'type': 'video',
                'url': url
            }
            if vid.get('stored_key'):
                item['stored_key'] = vid.get('stored_key')
            media_items.append(item)
    
    # 如果 videos 为空或没有找到URL，尝试从 stored_videos 获取
    if not any(item['type'] == 'video' for item in media_items):
        stored_videos = archive.get('stored_videos', [])
        for vid in stored_videos:
            url = vid.get('url')
            if url:
                item = {
                    'type': 'video',
                    'url': url
                }
                if vid.get('key'):
                    item['stored_key'] = vid.get('key')
                media_items.append(item)
    
    # 兜底：使用封面图
    if not media_items and cover_url:
        if isinstance(cover_url, str) and cover_url.strip():
            media_items.append({
                'type': 'photo',
                'url': cover_url.strip()
            })

    # 兜底兼容：若无 archive 结构但 metadata 里有旧字段 media/pics，也尽量提取。
    if not media_items and isinstance(archive_metadata, dict):
        legacy_media = archive_metadata.get('media') or archive_metadata.get('pics') or []
        if isinstance(legacy_media, list):
            for media in legacy_media:
                if isinstance(media, dict):
                    url = media.get('url') or media.get('thumbnail_url')
                else:
                    url = media if isinstance(media, str) else None
                if url:
                    media_items.append({'type': 'photo', 'url': url})
    
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
