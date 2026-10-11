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


def _text_chunks(value: str, limit: int = 1500) -> list[str]:
    chunks = []
    while len(value) > limit:
        boundary = value.rfind("\n", 0, limit + 1)
        boundary = boundary if boundary >= limit // 2 else limit
        chunks.append(value[:boundary])
        value = value[boundary:]
    if value:
        chunks.append(value)
    return chunks


def build_link_preview_messages(parsed: ParsedContent, format: str = "full") -> list[dict]:
    """Select the requested format before splitting; full never drops article text."""
    if format not in {"full", "summary", "text"}:
        raise ValueError("Unknown preview format")
    archive = (parsed.archive_metadata or {}).get("archive") or {}
    photos = []
    for image in archive.get("images", []):
        url = image.get("url") if isinstance(image, dict) else None
        if (url and urlsplit(url).scheme in {"http", "https"}
                and image.get("type") not in {"avatar", "answer_avatar"} and not image.get("is_avatar")
                and not is_avatar_media_url(url, parsed.author_avatar_url) and url not in photos):
            photos.append(url)
    body = parsed.body or ""
    for url in re.findall(r"!\[[^\]]*\]\(([^\s)]+)\)", body):
        if (url in parsed.media_urls and urlsplit(url).scheme in {"http", "https"}
                and not is_avatar_media_url(url, parsed.author_avatar_url) and url not in photos):
            photos.append(url)
    if not photos and parsed.cover_url and not is_avatar_media_url(parsed.cover_url, parsed.author_avatar_url):
        photos.append(parsed.cover_url)

    # Bilibili video/season/live previews remain one cover-and-description message.
    # Other platforms can contain both video and photographs; retain their photos.
    compact_video = parsed.platform == "bilibili" and parsed.content_type in {"video", "bangumi", "live"}
    if compact_video:
        cover = parsed.cover_url or (photos[0] if photos else None)
        photos = [cover] if cover and not is_avatar_media_url(cover, parsed.author_avatar_url) else []
    if format == "text":
        photos = []
    if format == "summary" or compact_video:
        excerpt = truncate_message_body(strip_markdown(body), 500)
        nodes = [{"body": excerpt, "media_items": [{"type": "photo", "url": url} for url in photos[:1]]}]
    else:
        nodes = []
        used = set()
        inline = format == "full" and bool(re.search(r"!\[[^\]]*\]\([^\s)]+\)", body))
        if inline:
            pending = ""
            for part in re.split(r"(!\[[^\]]*\]\([^\s)]+\))", body):
                match = re.fullmatch(r"!\[[^\]]*\]\(([^\s)]+)\)", part)
                if match:
                    url = match.group(1)
                    if url in photos and url not in used:
                        chunks = _text_chunks(pending) or [""]
                        nodes.extend({"body": chunk, "media_items": []} for chunk in chunks)
                        nodes[-1]["media_items"] = [{"type": "photo", "url": url}]
                        pending = ""
                        used.add(url)
                else:
                    text = strip_markdown(part)
                    pending += ("\n\n" if pending and text else "") + text
            nodes.extend({"body": chunk, "media_items": []} for chunk in _text_chunks(pending))
            # A cover preceding a short paragraph is still a single mixed message.
            if len(photos) <= 1 and len("\n\n".join(n["body"] for n in nodes)) <= 1500:
                nodes = [{"body": "\n\n".join(n["body"] for n in nodes if n["body"]),
                          "media_items": [item for n in nodes for item in n["media_items"]]}]
        else:
            nodes = [{"body": chunk, "media_items": []} for chunk in _text_chunks(strip_markdown(body))] or [{"body": "", "media_items": []}]
        extras = [url for url in photos if url not in used]
        for offset in range(0, len(extras), 3):
            media = [{"type": "photo", "url": url} for url in extras[offset:offset + 3]]
            if offset == 0 and nodes and not nodes[0]["media_items"]:
                nodes[0]["media_items"] = media
            else:
                nodes.append({"body": "", "media_items": media})
    nodes = nodes or [{"body": "", "media_items": []}]
    nodes[0].update(title=parsed.title, author_name=parsed.author_name, clean_url=parsed.clean_url,
                    platform=parsed.platform, content_type=parsed.content_type, stats=parsed.stats)
    labeled = False
    for node in nodes:
        # The excerpt/chunks were already selected above. Avoid re-truncation.
        node["render_config"] = {"format": "text" if format == "text" else "full"}
        node["show_body_label"] = not labeled
        node["body_label"] = "简介" if compact_video else "正文"
        labeled = labeled or bool(node["body"].strip())
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
