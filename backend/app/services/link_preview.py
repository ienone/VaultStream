"""Build ephemeral link previews using the regular push payload contract."""

import asyncio
import re
from urllib.parse import urlsplit

import httpx

from app.adapters.base import ParsedContent
from app.core.safe_fetch import create_safe_async_transport, safe_client_get
from app.media.extractor import is_avatar_media_url
from app.media.processor import _MAX_ARCHIVE_IMAGE_BYTES, _request_headers_for_url
from app.services.config_service import ConfigService
from app.utils.text_formatters import strip_markdown, truncate_message_body


def build_link_preview_messages(parsed: ParsedContent) -> list[dict]:
    """Preserve article image placement; other galleries use three-image nodes."""
    archive = (parsed.archive_metadata or {}).get("archive") or {}
    photos = []
    for image in archive.get("images", []):
        url = image.get("url") if isinstance(image, dict) else None
        if (url and urlsplit(url).scheme in {"http", "https"}
                and image.get("type") != "avatar" and not image.get("is_avatar")
                and not is_avatar_media_url(url, parsed.author_avatar_url)
                and url not in photos):
            photos.append(url)
    for url in re.findall(r"!\[[^\]]*\]\(([^\s)]+)\)", parsed.body or ""):
        if (url in parsed.media_urls and urlsplit(url).scheme in {"http", "https"}
                and not is_avatar_media_url(url, parsed.author_avatar_url) and url not in photos):
            photos.append(url)
    if not photos and parsed.cover_url and not is_avatar_media_url(parsed.cover_url, parsed.author_avatar_url):
        photos.append(parsed.cover_url)

    body = parsed.body or ""
    limit = 500 if parsed.layout_type == "video" else 1500
    nodes = []
    used = set()
    article_inline = parsed.layout_type == "article" and re.search(r"!\[[^\]]*\]\([^\s)]+\)", body)
    if article_inline:
        # Each node retains the paragraph immediately before its illustration.
        remaining = limit
        pending = ""
        for part in re.split(r"(!\[[^\]]*\]\([^\s)]+\))", body):
            match = re.fullmatch(r"!\[[^\]]*\]\(([^\s)]+)\)", part)
            if match:
                url = match.group(1)
                if url in photos and url not in used:
                    nodes.append({"body": pending, "media_items": [{"type": "photo", "url": url}]})
                    pending = ""
                    used.add(url)
            elif remaining > 0:
                text = strip_markdown(part)
                pending += ("\n\n" if pending and text else "") + truncate_message_body(text, remaining)
                if len(text) > remaining:
                    break
                remaining = max(0, remaining - len(text))
        if pending:
            nodes.append({"body": pending, "media_items": []})
    else:
        nodes.append({"body": truncate_message_body(strip_markdown(body), limit), "media_items": []})

    # A single illustration and its text belong to the same QQ message,
    # including an article whose image appears before its main paragraph.
    if len(nodes) > 1 and len(photos) <= 1:
        nodes = [{"body": "\n\n".join(node["body"] for node in nodes if node["body"]),
                  "media_items": [item for node in nodes for item in node["media_items"]]}]
    if parsed.layout_type == "video":
        cover = parsed.cover_url or (photos[0] if photos else None)
        photos = [cover] if cover and not is_avatar_media_url(cover, parsed.author_avatar_url) else []

    extras = [] if article_inline else [url for url in photos if url not in used]
    if article_inline and not used and nodes and photos:
        nodes[0]["media_items"] = [{"type": "photo", "url": photos[0]}]
    for offset in range(0, len(extras), 3):
        media = [{"type": "photo", "url": url} for url in extras[offset:offset + 3]]
        if offset == 0 and nodes and not nodes[0]["media_items"]:
            nodes[0]["media_items"] = media
        else:
            nodes.append({"body": "", "media_items": media})
    if not nodes:
        nodes = [{"body": "", "media_items": []}]
    nodes[0].update(title=parsed.title, author_name=parsed.author_name, clean_url=parsed.clean_url,
                    platform=parsed.platform, content_type=parsed.content_type, stats=parsed.stats)
    for node in nodes:
        node["render_config"] = {"format": "full"}
        node["body_label"] = "简介" if parsed.layout_type == "video" else "正文"
    return nodes


async def prepare_link_preview_images(messages: list[dict]) -> None:
    """Fetch images for an ephemeral upload; never create storage or DB assets."""
    proxy = await ConfigService().get_http_proxy()
    semaphore = asyncio.Semaphore(4)
    async with httpx.AsyncClient(
        proxy=proxy or None,
        transport=None if proxy else create_safe_async_transport(),
        timeout=25, trust_env=False,
    ) as client:
        async def fetch(item: dict) -> None:
            async with semaphore:
                result = await safe_client_get(
                    client, item["url"], headers=_request_headers_for_url(item["url"]),
                    max_bytes=_MAX_ARCHIVE_IMAGE_BYTES,
                    allowed_content_type_prefixes=("image/",),
                )
                if result.status_code != 200 or not result.content:
                    raise ValueError("Preview image download failed")
                item["upload_bytes"] = result.content

        await asyncio.gather(*(fetch(item) for message in messages for item in message["media_items"]))
