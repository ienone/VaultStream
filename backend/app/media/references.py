"""解析与发现入库共用成功归档媒体的引用替换。"""
import html
import re
from urllib.parse import urlsplit


def rewrite_media_urls(text: str | None, mapping: dict[str, str]) -> str | None:
    if not text or not mapping:
        return text
    replacements = {candidate: target for source, target in mapping.items()
                    for candidate in (source, html.escape(source, quote=False)) if source}
    pattern = "|".join(re.escape(url) for url in sorted(replacements, key=len, reverse=True))
    # 地址必须完整匹配，不能把 /photo 当作 /photo-large 或 /photo?sig=... 的前缀替换。
    return re.sub(r"(?:" + pattern + r''')(?=$|[\s<>"')\]])''',
                  lambda match: replacements[match[0]], text)


def xiaohongshu_image_identity(url: str) -> str | None:
    """Signed webpic URLs retain the platform image ID before the transform."""
    parts = urlsplit(url)
    if parts.scheme not in {"http", "https"} or not re.fullmatch(
        r"sns-webpic-[a-z0-9-]+\.xhscdn\.com", parts.hostname or "",
    ):
        return None
    image_id = parts.path.rsplit("/", 1)[-1].split("!", 1)[0]
    return image_id if re.fullmatch(r"[a-z0-9]{20,}", image_id) else None
