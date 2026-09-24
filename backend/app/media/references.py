"""解析与发现入库共用成功归档媒体的引用替换。"""
import html
import re
from typing import Any


def rewrite_media_urls(text: str | None, mapping: dict[str, str]) -> str | None:
    if not text or not mapping:
        return text
    replacements = {candidate: target for source, target in mapping.items()
                    for candidate in (source, html.escape(source, quote=False)) if source}
    pattern = "|".join(re.escape(url) for url in sorted(replacements, key=len, reverse=True))
    # 地址必须完整匹配，不能把 /photo 当作 /photo-large 或 /photo?sig=... 的前缀替换。
    return re.sub(r"(?:" + pattern + r''')(?=$|[\s<>"')\]])''',
                  lambda match: replacements[match[0]], text)


def apply_archive_media(record: Any, archive: dict[str, Any]) -> None:
    stored_images = [item for item in archive.get("images") or []
                     if isinstance(item, dict) and item.get("stored_key")]
    stored_videos = [item for item in archive.get("videos") or []
                     if isinstance(item, dict) and item.get("stored_key")]
    stored = stored_images + stored_videos
    mapping = {item["url"]: f"local://{item['stored_key']}" for item in stored
               if item.get("url") and item.get("stored_key")}
    if not mapping:
        return
    record.body = rewrite_media_urls(getattr(record, "body", None), mapping)
    for field in ("cover_url", "author_avatar_url"):
        value = getattr(record, field, None)
        if value in mapping:
            setattr(record, field, mapping[value])
    urls = [mapping.get(url, url) for url in (getattr(record, "media_urls", None) or [])]
    for item in stored:
        if item.get("is_avatar") or item.get("type") not in (None, "image", "gallery", "cover", "video"):
            continue
        if item.get("url") in mapping:
            urls.append(mapping[item["url"]])
    record.media_urls = list(dict.fromkeys(urls))
    if not getattr(record, "cover_url", None):
        record.cover_url = next((mapping[item["url"]] for item in stored_images
                                 if item.get("url") in mapping and not item.get("is_avatar")
                                 and item.get("type") in (None, "image", "gallery", "cover")), None)
    payload = getattr(record, "rich_payload", None)
    if isinstance(payload, dict):
        for block in payload.get("blocks") or []:
            data = block.get("data") if isinstance(block, dict) else None
            if isinstance(data, dict):
                for field in ("cover_url", "author_avatar_url"):
                    if data.get(field) in mapping:
                        data[field] = mapping[data[field]]
    if archive.get("dominant_color"):
        record.cover_color = archive["dominant_color"]
