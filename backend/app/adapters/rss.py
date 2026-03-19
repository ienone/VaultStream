import calendar
import html
import hashlib
import re
from datetime import datetime, timezone
from email.utils import parsedate_to_datetime
from typing import Any, Optional
from urllib.parse import urljoin, urlparse

import feedparser
import httpx
from bs4 import BeautifulSoup
from markdownify import markdownify as md

from app.adapters.base import LAYOUT_ARTICLE, ParsedContent, PlatformAdapter
from app.models.base import Platform
from app.utils.datetime_utils import normalize_datetime_for_db
from app.utils.bbcode_utils import convert_bbcode_to_html
from app.core.logging import logger


class RssAdapter(PlatformAdapter):
    """RSS/Atom 适配器（规范化解析）。"""

    _IMAGE_EXTENSIONS = (".jpg", ".jpeg", ".png", ".webp", ".gif", ".bmp", ".avif", ".svg")
    _VIDEO_EXTENSIONS = (".mp4", ".m3u8", ".mov", ".webm", ".mkv", ".avi")
    _IMG_URL_ATTRS = (
        "data-original",
        "data-src",
        "data-lazy-src",
        "data-original-src",
        "data-actualsrc",
        "src",
    )

    def __init__(self, **kwargs):
        self.client = httpx.AsyncClient(
            follow_redirects=True,
            timeout=20.0,
            headers={
                "User-Agent": (
                    "Mozilla/5.0 (Windows NT 10.0; Win64; x64) "
                    "AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
                ),
                "Accept": "application/rss+xml, application/atom+xml, text/xml, application/xml, */*",
            },
        )

    async def close(self):
        await self.client.aclose()

    async def detect_content_type(self, url: str) -> Optional[str]:
        return "article"

    async def clean_url(self, url: str) -> str:
        return (url or "").strip()

    async def parse(self, url: str) -> ParsedContent:
        """
        解析 feed URL 并返回最新一条内容。

        该适配器主要用于频道批量拉取（parse_channel），这里提供单条兜底行为。
        """
        entries = await self.parse_channel(url, limit=1)
        if not entries:
            raise ValueError(f"RSS/Atom 源没有可解析条目: {url}")
        return entries[0]

    def map_stats_to_content(self, content: Any, parsed: ParsedContent) -> None:
        self.map_common_stats(content, parsed.stats)

    async def parse_channel(self, url: str, limit: int = 20) -> list[ParsedContent]:
        """规范化解析 RSS/Atom 频道。"""
        feed_url = (url or "").strip()
        if not feed_url:
            return []
        if limit <= 0:
            return []

        logger.info(f"RssAdapter: Fetching {feed_url}")
        try:
            response = await self.client.get(feed_url)
            response.raise_for_status()
        except Exception as e:
            logger.warning(f"RssAdapter: 请求失败 {feed_url}: {e}")
            return []

        feed = feedparser.parse(response.content)
        raw_entries = self._extract_raw_entries(response.content)
        raw_lookup = self._build_raw_entry_lookup(raw_entries)
        if feed.bozo and not feed.entries:
            logger.warning(f"RssAdapter: feed 格式异常且无可用条目 {feed_url}: {feed.bozo_exception}")

        feed_title = str(feed.feed.get("title") or "RSS Source")
        feed_link = self._normalize_candidate_url(feed.feed.get("link"), feed_url) or feed_url

        results: list[ParsedContent] = []
        for entry_index, entry in enumerate(feed.entries[:limit]):
            try:
                raw_entry = self._match_raw_entry(entry, raw_entries, raw_lookup, entry_index)
                parsed = self._parse_entry(
                    entry=entry,
                    feed_url=feed_url,
                    feed_title=feed_title,
                    feed_link=feed_link,
                    raw_entry=raw_entry,
                )
                if parsed:
                    results.append(parsed)
            except Exception as e:
                logger.warning(f"RssAdapter: 解析 RSS 单条目失败: {e}")
                continue

        return results

    def _parse_entry(
        self,
        *,
        entry: dict,
        feed_url: str,
        feed_title: str,
        feed_link: str,
        raw_entry: Optional[dict[str, str]] = None,
    ) -> ParsedContent:
        entry_url = self._extract_entry_url(entry, feed_link)
        title = str(entry.get("title") or "No Title").strip() or "No Title"
        source_tags = self._extract_source_tags(entry)
        author_name = self._extract_author(entry, default=feed_title)
        published_at = self._parse_date(entry)

        raw_html = self._extract_content(entry, raw_entry=raw_entry)
        markdown_body, plain_text, body_images, body_links = self._extract_body_assets(raw_html, base_url=entry_url)

        enclosure_images, enclosure_videos = self._extract_enclosure_media(entry, base_url=entry_url)
        cover_url = self._extract_cover_url(
            entry,
            base_url=entry_url,
            fallback_images=body_images + enclosure_images,
        )

        media_urls = self._dedupe_urls(body_images + enclosure_videos)
        content_id = self._build_content_id(entry, entry_url=entry_url, title=title)

        archive_images: list[dict[str, Any]] = []
        seen_image_urls: set[str] = set()

        for image_url in body_images:
            if image_url not in seen_image_urls:
                seen_image_urls.add(image_url)
                archive_images.append({"url": image_url, "type": "image"})

        if cover_url and cover_url not in seen_image_urls:
            seen_image_urls.add(cover_url)
            archive_images.append({"url": cover_url, "type": "cover"})

        for image_url in enclosure_images:
            if image_url not in seen_image_urls:
                seen_image_urls.add(image_url)
                archive_images.append({"url": image_url, "type": "image"})

        archive_videos = [{"url": video_url, "type": "video"} for video_url in enclosure_videos]

        archive = {
            "version": 2,
            "type": "rss_article",
            "title": title,
            "plain_text": plain_text,
            "markdown": markdown_body or plain_text,
            "images": archive_images,
            "videos": archive_videos,
            "links": body_links,
            "stored_images": [],
            "stored_videos": [],
        }

        archive_metadata = {
            "feed": {
                "url": feed_url,
                "link": feed_link,
                "title": feed_title,
            },
            "entry": {
                "id": str(entry.get("id") or entry.get("guid") or ""),
                "link": entry_url,
                "title": title,
                "author": author_name,
                "published": str(entry.get("published") or ""),
                "updated": str(entry.get("updated") or ""),
                "tags": source_tags,
            },
            "archive": archive,
        }

        return ParsedContent(
            platform=Platform.RSS.value,
            content_type="article",
            content_id=content_id,
            clean_url=entry_url,
            layout_type=LAYOUT_ARTICLE,
            title=title,
            body=archive["markdown"],
            author_name=author_name,
            cover_url=cover_url,
            media_urls=media_urls,
            published_at=published_at,
            stats={},
            source_tags=source_tags,
            rich_payload={},
            archive_metadata=archive_metadata,
        )

    @staticmethod
    def _normalize_markdown(markdown_text: str) -> str:
        markdown_text = (markdown_text or "").replace("\r\n", "\n").strip()
        markdown_text = re.sub(r"\n{3,}", "\n\n", markdown_text)
        return markdown_text

    @classmethod
    def _extract_body_assets(cls, html_text: str, *, base_url: str) -> tuple[str, str, list[str], list[dict[str, str]]]:
        if not isinstance(html_text, str) or not html_text.strip():
            return "", "", [], []

        html_text = html.unescape(html_text)
        html_text = convert_bbcode_to_html(html_text)
        soup = BeautifulSoup(html_text, "html.parser")

        body_images: list[str] = []
        links: list[dict[str, str]] = []
        link_seen: set[str] = set()

        for img in soup.find_all("img"):
            img_url = cls._extract_image_url(img, base_url)
            if img_url:
                body_images.append(img_url)
                img["src"] = img_url
                for attr in ("data-original", "data-src", "data-lazy-src", "data-original-src", "data-actualsrc", "srcset", "data-srcset"):
                    if attr in img.attrs and attr != "src":
                        del img[attr]
            else:
                img.decompose()

        for link in soup.find_all("a"):
            normalized_href = cls._normalize_candidate_url(link.get("href"), base_url)
            if not normalized_href:
                link.unwrap()
                continue
            link["href"] = normalized_href
            text = (link.get_text() or "").strip()
            if normalized_href not in link_seen:
                link_seen.add(normalized_href)
                links.append({"url": normalized_href, "text": text})

        markdown_body = cls._normalize_markdown(md(str(soup), heading_style="ATX"))
        plain_text = re.sub(r"\n{3,}", "\n\n", soup.get_text(separator="\n").strip())
        return markdown_body, plain_text, cls._dedupe_urls(body_images), links

    @classmethod
    def _extract_source_tags(cls, entry: dict) -> list[str]:
        tags: list[str] = []
        seen: set[str] = set()

        for t in entry.get("tags") or []:
            term = str((t or {}).get("term") or "").strip()
            if term and term not in seen:
                seen.add(term)
                tags.append(term)

        category = str(entry.get("category") or "").strip()
        if category and category not in seen:
            tags.append(category)
        return tags

    @classmethod
    def _extract_author(cls, entry: dict, *, default: str) -> str:
        author = str(entry.get("author") or "").strip()
        if author:
            return author
        detail = entry.get("author_detail")
        if isinstance(detail, dict):
            name = str(detail.get("name") or "").strip()
            if name:
                return name
        return default

    @classmethod
    def _build_content_id(cls, entry: dict, *, entry_url: str, title: str) -> str:
        for key in ("id", "guid"):
            value = str(entry.get(key) or "").strip()
            if value:
                return value
        if entry_url:
            return entry_url
        return hashlib.md5(f"{title}".encode("utf-8"), usedforsecurity=False).hexdigest()

    @staticmethod
    def _parse_date(entry: dict) -> Optional[datetime]:
        for parsed_key in ("published_parsed", "updated_parsed", "created_parsed"):
            parsed_value = entry.get(parsed_key)
            if parsed_value:
                dt = datetime.fromtimestamp(calendar.timegm(parsed_value), tz=timezone.utc)
                return normalize_datetime_for_db(dt)

        for field_name in ("published", "updated", "created"):
            raw = str(entry.get(field_name) or "").strip()
            if not raw:
                continue
            try:
                return normalize_datetime_for_db(parsedate_to_datetime(raw))
            except Exception:
                try:
                    return normalize_datetime_for_db(datetime.fromisoformat(raw.replace("Z", "+00:00")))
                except Exception:
                    continue
        return None

    @staticmethod
    def _extract_content(entry: dict, *, raw_entry: Optional[dict[str, str]] = None) -> str:
        if raw_entry:
            raw_content = str(raw_entry.get("content") or "").strip()
            if raw_content:
                return raw_content

        # 优先 content/value（RSS content:encoded / Atom content）
        content = entry.get("content")
        if isinstance(content, list) and content:
            value = str(content[0].get("value") or "").strip()
            if value:
                return value
        elif isinstance(content, dict):
            value = str(content.get("value") or "").strip()
            if value:
                return value

        if raw_entry:
            for key in ("summary", "description"):
                raw_value = str(raw_entry.get(key) or "").strip()
                if raw_value:
                    return raw_value

        # 再 summary / description（Atom summary / RSS description）
        for key in ("summary", "description"):
            value = str(entry.get(key) or "").strip()
            if value:
                return value
        return ""

    @staticmethod
    def _extract_raw_entries(xml_content: bytes) -> list[dict[str, str]]:
        if not xml_content:
            return []

        try:
            soup = BeautifulSoup(xml_content, "xml")
        except Exception:
            return []

        raw_entries: list[dict[str, str]] = []
        for node in soup.find_all(["item", "entry"]):
            raw_entries.append(
                {
                    "id": RssAdapter._safe_tag_text(node.find("id")),
                    "guid": RssAdapter._safe_tag_text(node.find("guid")),
                    "link": RssAdapter._extract_raw_link(node),
                    "title": RssAdapter._safe_tag_text(node.find("title")),
                    "content": RssAdapter._extract_raw_content(node),
                    "summary": RssAdapter._extract_raw_summary(node),
                    "description": RssAdapter._extract_raw_description(node),
                }
            )
        return raw_entries

    @staticmethod
    def _safe_tag_text(tag: Any) -> str:
        if tag is None:
            return ""
        try:
            return str(tag.get_text() or "").strip()
        except Exception:
            return ""

    @staticmethod
    def _safe_tag_html(tag: Any) -> str:
        if tag is None:
            return ""
        try:
            return str(tag.decode_contents() or "").strip()
        except Exception:
            return ""

    @staticmethod
    def _extract_raw_link(node: Any) -> str:
        if node is None:
            return ""

        for link_tag in node.find_all("link"):
            href = str(link_tag.get("href") or "").strip()
            if href:
                return href
            text = RssAdapter._safe_tag_text(link_tag)
            if text:
                return text
        return ""

    @staticmethod
    def _extract_raw_content(node: Any) -> str:
        if node is None:
            return ""

        for tag in node.find_all():
            name = str(getattr(tag, "name", "")).lower()
            if name in ("content:encoded", "encoded") or name.endswith(":encoded"):
                value = RssAdapter._safe_tag_html(tag) or RssAdapter._safe_tag_text(tag)
                if value:
                    return value

        for tag in node.find_all("content"):
            value = RssAdapter._safe_tag_html(tag) or RssAdapter._safe_tag_text(tag)
            if value:
                return value
        return ""

    @staticmethod
    def _extract_raw_summary(node: Any) -> str:
        if node is None:
            return ""

        tag = node.find("summary")
        return RssAdapter._safe_tag_html(tag) or RssAdapter._safe_tag_text(tag)

    @staticmethod
    def _extract_raw_description(node: Any) -> str:
        if node is None:
            return ""

        tag = node.find("description")
        return RssAdapter._safe_tag_html(tag) or RssAdapter._safe_tag_text(tag)

    @staticmethod
    def _build_raw_entry_lookup(raw_entries: list[dict[str, str]]) -> dict[str, dict[str, str]]:
        lookup: dict[str, dict[str, str]] = {}
        for raw_entry in raw_entries:
            for field in ("id", "guid", "link", "title"):
                value = str(raw_entry.get(field) or "").strip()
                if not value:
                    continue
                key = f"{field}:{value}"
                if key not in lookup:
                    lookup[key] = raw_entry
        return lookup

    @staticmethod
    def _match_raw_entry(
        entry: dict,
        raw_entries: list[dict[str, str]],
        raw_lookup: dict[str, dict[str, str]],
        fallback_index: int,
    ) -> Optional[dict[str, str]]:
        for field in ("id", "guid", "link", "title"):
            value = str(entry.get(field) or "").strip()
            if not value:
                continue
            key = f"{field}:{value}"
            matched = raw_lookup.get(key)
            if matched:
                return matched

        if 0 <= fallback_index < len(raw_entries):
            return raw_entries[fallback_index]
        return None

    @classmethod
    def _normalize_candidate_url(cls, url: Any, base_url: str) -> Optional[str]:
        if not isinstance(url, str):
            return None
        candidate = url.strip()
        if not candidate or candidate.startswith(("data:", "javascript:")):
            return None
        return urljoin(base_url, candidate)

    @staticmethod
    def _candidate_from_srcset(srcset: Any) -> Optional[str]:
        if not isinstance(srcset, str):
            return None
        candidates = [
            segment.strip().split(" ")[0]
            for segment in srcset.split(",")
            if segment.strip()
        ]
        return candidates[-1] if candidates else None

    @classmethod
    def _extract_image_url(cls, img, base_url: str) -> Optional[str]:
        for attr in cls._IMG_URL_ATTRS:
            candidate = cls._normalize_candidate_url(img.get(attr), base_url)
            if candidate:
                return candidate

        for attr in ("data-srcset", "srcset"):
            srcset_candidate = cls._candidate_from_srcset(img.get(attr))
            candidate = cls._normalize_candidate_url(srcset_candidate, base_url)
            if candidate:
                return candidate
        return None

    @classmethod
    def _looks_like_image_url(cls, url: Any) -> bool:
        if not isinstance(url, str):
            return False
        path = urlparse(url.strip()).path.lower()
        return any(path.endswith(ext) for ext in cls._IMAGE_EXTENSIONS)

    @classmethod
    def _looks_like_video_url(cls, url: Any) -> bool:
        if not isinstance(url, str):
            return False
        path = urlparse(url.strip()).path.lower()
        return any(path.endswith(ext) for ext in cls._VIDEO_EXTENSIONS)

    @classmethod
    def _is_image_candidate(cls, url: Any, *, media_type: Any = None, medium: Any = None, force: bool = False) -> bool:
        if force:
            return True
        normalized_medium = str(medium or "").lower()
        normalized_type = str(media_type or "").lower()
        if normalized_medium == "image":
            return True
        if normalized_type.startswith("image/"):
            return True
        return cls._looks_like_image_url(url)

    @classmethod
    def _is_video_candidate(cls, url: Any, *, media_type: Any = None, medium: Any = None) -> bool:
        normalized_medium = str(medium or "").lower()
        normalized_type = str(media_type or "").lower()
        if normalized_medium == "video":
            return True
        if normalized_type.startswith("video/"):
            return True
        return cls._looks_like_video_url(url)

    @classmethod
    def _extract_enclosure_media(cls, entry: dict, *, base_url: str) -> tuple[list[str], list[str]]:
        images: list[str] = []
        videos: list[str] = []
        seen_images: set[str] = set()
        seen_videos: set[str] = set()

        def add_image(url: Any, *, media_type: Any = None, medium: Any = None, force: bool = False) -> None:
            if not cls._is_image_candidate(url, media_type=media_type, medium=medium, force=force):
                return
            normalized = cls._normalize_candidate_url(url, base_url)
            if normalized and normalized not in seen_images:
                seen_images.add(normalized)
                images.append(normalized)

        def add_video(url: Any, *, media_type: Any = None, medium: Any = None) -> None:
            if not cls._is_video_candidate(url, media_type=media_type, medium=medium):
                return
            normalized = cls._normalize_candidate_url(url, base_url)
            if normalized and normalized not in seen_videos:
                seen_videos.add(normalized)
                videos.append(normalized)

        media_thumbnails = entry.get("media_thumbnail") or []
        if isinstance(media_thumbnails, dict):
            media_thumbnails = [media_thumbnails]
        for thumbnail in media_thumbnails:
            if isinstance(thumbnail, dict):
                add_image(thumbnail.get("url") or thumbnail.get("href"), force=True)

        media_contents = entry.get("media_content") or []
        if isinstance(media_contents, dict):
            media_contents = [media_contents]
        for media in media_contents:
            if not isinstance(media, dict):
                continue
            media_url = media.get("url") or media.get("href")
            media_type = media.get("type")
            medium = media.get("medium")
            add_image(media_url, media_type=media_type, medium=medium)
            add_video(media_url, media_type=media_type, medium=medium)

        for link in entry.get("links", []) or []:
            if not isinstance(link, dict):
                continue
            if str(link.get("rel") or "").lower() != "enclosure":
                continue
            link_url = link.get("href") or link.get("url")
            link_type = link.get("type")
            add_image(link_url, media_type=link_type)
            add_video(link_url, media_type=link_type)

        enclosures = entry.get("enclosures") or []
        if isinstance(enclosures, dict):
            enclosures = [enclosures]
        for enclosure in enclosures:
            if not isinstance(enclosure, dict):
                continue
            enclosure_url = enclosure.get("href") or enclosure.get("url")
            enclosure_type = enclosure.get("type")
            add_image(enclosure_url, media_type=enclosure_type)
            add_video(enclosure_url, media_type=enclosure_type)

        image = entry.get("image")
        if isinstance(image, dict):
            add_image(image.get("href") or image.get("url"), force=True)
        elif isinstance(image, str):
            add_image(image, force=True)

        return images, videos

    @classmethod
    def _extract_cover_url(cls, entry: dict, *, base_url: str, fallback_images: list[str]) -> Optional[str]:
        images, _videos = cls._extract_enclosure_media(entry, base_url=base_url)
        if images:
            return images[0]
        return fallback_images[0] if fallback_images else None

    @classmethod
    def _extract_entry_url(cls, entry: dict, default_base: str) -> str:
        entry_link = cls._normalize_candidate_url(entry.get("link"), default_base)
        if entry_link:
            return entry_link

        for link in entry.get("links", []) or []:
            if not isinstance(link, dict):
                continue
            if str(link.get("rel") or "").lower() in ("", "alternate"):
                candidate = cls._normalize_candidate_url(link.get("href") or link.get("url"), default_base)
                if candidate:
                    return candidate
        return default_base

    @staticmethod
    def _dedupe_urls(urls: list[str]) -> list[str]:
        unique: list[str] = []
        seen: set[str] = set()
        for url in urls:
            if not isinstance(url, str):
                continue
            candidate = url.strip()
            if not candidate or candidate in seen:
                continue
            seen.add(candidate)
            unique.append(candidate)
        return unique
