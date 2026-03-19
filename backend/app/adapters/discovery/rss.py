"""
RSS/Atom 订阅源适配器

基于 Horizon RSSScraper 移植，适配 VaultStream DiscoverySource 模型。
"""
import calendar
import html
import os
import re
from datetime import datetime, timezone
from email.utils import parsedate_to_datetime
from typing import Any, Optional
from urllib.parse import urljoin, urlparse
from bs4 import BeautifulSoup

import feedparser
import httpx

from app.core.logging import logger
from app.adapters.discovery.base import BaseDiscoveryScraper, DiscoveryItem
from app.utils.bbcode_utils import convert_bbcode_to_html


class RSSDiscoveryScraper(BaseDiscoveryScraper):
    """RSS/Atom 订阅源抓取器。"""

    _IMAGE_EXTENSIONS = (
        ".jpg",
        ".jpeg",
        ".png",
        ".webp",
        ".gif",
        ".bmp",
        ".avif",
        ".svg",
    )
    _IMG_URL_ATTRS = (
        "data-original",
        "data-src",
        "data-lazy-src",
        "data-original-src",
        "data-actualsrc",
        "src",
    )

    async def fetch(self, last_cursor: Optional[str] = None) -> tuple[list[DiscoveryItem], Optional[str]]:
        feed_url = self._expand_env_vars(self.config.get("url", ""))
        if not feed_url:
            logger.warning("RSS source config missing 'url'")
            return [], last_cursor

        items: list[DiscoveryItem] = []
        new_cursor = last_cursor

        try:
            # 使用更真实的 User-Agent 避免 403 (e.g. RSSHub/V2EX 等源常屏蔽默认 httpx/python UA)
            headers = {
                "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36",
                "Accept": "application/rss+xml, application/atom+xml, text/xml, application/xml, */*",
            }
            async with httpx.AsyncClient(timeout=30, headers=headers) as client:
                response = await client.get(feed_url, follow_redirects=True)
                response.raise_for_status()

            # 优先使用 content (bytes) 传给 feedparser，让其根据 XML 声明检测编码 (对 GBK/Big5 等源更准确)
            feed = feedparser.parse(response.content)
            raw_nodes = self._extract_raw_nodes(response.content)

            if feed.bozo and not feed.entries:
                logger.warning("RSS formatting error (Bozo) for %s: %s", feed_url, feed.bozo_exception)

            for entry_index, entry in enumerate(feed.entries):
                entry_id: str = str(entry.get("id") or entry.get("link") or "")
                entry_url: str = str(entry.get("link") or feed_url)
                raw_node = raw_nodes[entry_index] if entry_index < len(raw_nodes) else None

                if last_cursor and entry_id == last_cursor:
                    break

                published_at = self._parse_date(entry)
                raw_content = self._extract_content(entry, raw_node=raw_node)
                explicit_cover_url = self._extract_cover_url(entry, entry_url)
                
                # BBCode → HTML 预处理（兼容论坛 RSS 源）
                raw_content = html.unescape(raw_content)
                raw_content = self._convert_bbcode_to_html(raw_content)
                # 强化版清洗逻辑：原地提取并替换为 Markdown (0-Token 策略)
                content_soup = BeautifulSoup(raw_content, 'html.parser')
                media_urls = []
                for img in content_soup.find_all('img'):
                    src = self._extract_image_url(img, entry_url)
                    alt = img.get('alt', '图片')
                    if src:
                        media_urls.append(src)
                        img.replace_with(f"\n![{alt}]({src})\n")
                    else:
                        img.decompose()

                media_urls = list(dict.fromkeys(media_urls))
                cover_url = explicit_cover_url or (media_urls[0] if media_urls else None)
                
                # 开始转换 HTML 为 Markdown (0-Token 策略)
                # 1. 处理块级元素换行 (从内向外 unwrap，避免父子节点重复处理)
                for tag in reversed(content_soup.find_all(['p', 'div', 'br', 'li'])):
                    if tag.name == 'br':
                        tag.replace_with("\n")
                    elif tag.name == 'li':
                        tag.insert_before("- ")
                        tag.insert_after("\n")
                        tag.unwrap()
                    else:
                        # p, div — 确保上下有换行，然后移除标签
                        tag.insert_before("\n")
                        tag.insert_after("\n")
                        tag.unwrap()

                # 2. 处理标题 (h1-h6)
                for h in content_soup.find_all(['h1', 'h2', 'h3', 'h4', 'h5', 'h6']):
                    level = int(h.name[1])
                    inner_text = h.get_text().strip()
                    if inner_text:
                        h.replace_with(f"\n{'#' * level} {inner_text}\n")
                    else:
                        h.decompose()

                # 3. 处理内联格式 (加粗、斜体、删除线)
                # 特别注意：清理两端空行，防止 Markdown 语法失效或异常换行
                for b in content_soup.find_all(['b', 'strong']):
                    text = b.get_text()
                    stripped = text.strip()
                    if stripped:
                        # 保持原有的外部换行趋势，但将 ** 紧贴文本
                        prefix = "\n" if text.startswith("\n") else ""
                        suffix = "\n" if text.endswith("\n") else ""
                        b.replace_with(f"{prefix}**{stripped}**{suffix}")
                    else:
                        b.decompose()

                for i in content_soup.find_all(['i', 'em']):
                    text = i.get_text()
                    stripped = text.strip()
                    if stripped:
                        prefix = "\n" if text.startswith("\n") else ""
                        suffix = "\n" if text.endswith("\n") else ""
                        i.replace_with(f"{prefix}*{stripped}*{suffix}")
                    else:
                        i.decompose()

                for s in content_soup.find_all(['s', 'del', 'strike']):
                    text = s.get_text()
                    stripped = text.strip()
                    if stripped:
                        s.replace_with(f"~~{stripped}~~")
                    else:
                        s.decompose()

                # 4. 处理引用和代码块
                for bq in content_soup.find_all('blockquote'):
                    lines = bq.get_text().strip().splitlines()
                    bq.replace_with("\n" + "\n".join(f"> {l.strip()}" for l in lines) + "\n")
                
                for code in content_soup.find_all('pre'):
                    code.replace_with(f"\n```\n{code.get_text()}\n```\n")
                
                for a in content_soup.find_all('a'):
                    link_text = a.get_text().strip()
                    if link_text:
                        a.replace_with(f"[{link_text}]({a.get('href', '')})")
                    else:
                        a.decompose()

                # 5. 最终清洗
                clean_body = content_soup.get_text(separator="").strip()
                # 合并过多的连续换行
                clean_body = re.sub(r'\n{3,}', '\n\n', clean_body)
                # 修复 Markdown 加粗/斜体被意外拆分的常见问题
                clean_body = re.sub(r'\*\*\s+\n', '**\n', clean_body)
                clean_body = re.sub(r'\n\s+\*\*', '\n**', clean_body)

                tags: list[str] = [str(t.get("term", "")) for t in (entry.get("tags") or []) if t.get("term")]
                category = self.config.get("category")
                if category:
                    tags.append(category)

                _feed_info: Any = feed.feed
                _feed_title: Optional[str] = str(_feed_info.get("title")) if hasattr(_feed_info, "get") and _feed_info.get("title") else None

                item = DiscoveryItem(
                    url=str(entry.get("link") or feed_url),
                    title=str(entry.get("title") or "Untitled"),
                    content=clean_body,
                    author=str(entry.get("author")) if entry.get("author") else _feed_title,
                    published_at=published_at,
                    source_tags=tags,
                    cover_url=cover_url,
                    media_urls=media_urls,
                    rich_payload={},
                    extra_stats={},
                    raw_metadata={
                        "feed_url": feed_url,
                        "entry_id": entry_id,
                    },
                )
                items.append(item)

            if feed.entries:
                first_id: str = str(feed.entries[0].get("id") or feed.entries[0].get("link") or "")
                if first_id:
                    new_cursor = first_id

        except Exception as e:
            logger.warning("RSS parse error for %s: %s", feed_url, e)

        return items, new_cursor

    @staticmethod
    def _convert_bbcode_to_html(text: str) -> str:
        return convert_bbcode_to_html(text)

    @staticmethod
    def _expand_env_vars(url: str) -> str:
        return re.sub(
            r'\$\{(\w+)\}',
            lambda m: os.environ.get(m.group(1), m.group(0)).strip(),
            url,
        )

    @staticmethod
    def _parse_date(entry: dict) -> Optional[datetime]:
        for field_name in ("published", "updated", "created"):
            if field_name not in entry:
                continue
            try:
                parsed_key = f"{field_name}_parsed"
                if parsed_key in entry and entry[parsed_key]:
                    return datetime.fromtimestamp(
                        calendar.timegm(entry[parsed_key]),
                        tz=timezone.utc,
                    )
                return parsedate_to_datetime(entry[field_name])
            except Exception:
                continue
        return None

    @staticmethod
    def _extract_content(entry: dict, *, raw_node: Any = None) -> str:
        if raw_node is not None:
            raw_content = RSSDiscoveryScraper._extract_raw_content(raw_node)
            if raw_content:
                return raw_content
            raw_summary = RSSDiscoveryScraper._extract_raw_summary(raw_node)
            if raw_summary:
                return raw_summary
            raw_description = RSSDiscoveryScraper._extract_raw_description(raw_node)
            if raw_description:
                return raw_description

        if "content" in entry:
            content = entry.get("content")
            if isinstance(content, list) and content:
                return str(content[0].get("value", ""))
        if "summary" in entry:
            return str(entry.get("summary", ""))
        if "description" in entry:
            return str(entry.get("description", ""))
        return ""

    @staticmethod
    def _extract_raw_nodes(xml_content: bytes) -> list[Any]:
        if not xml_content:
            return []
        try:
            soup = BeautifulSoup(xml_content, "xml")
        except Exception:
            return []
        return soup.find_all(["item", "entry"])

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
    def _extract_raw_content(raw_node: Any) -> str:
        if raw_node is None:
            return ""

        for tag in raw_node.find_all():
            name = str(getattr(tag, "name", "")).lower()
            if name in ("content:encoded", "encoded") or name.endswith(":encoded"):
                value = RSSDiscoveryScraper._safe_tag_html(tag) or RSSDiscoveryScraper._safe_tag_text(tag)
                if value:
                    return value

        for tag in raw_node.find_all("content"):
            value = RSSDiscoveryScraper._safe_tag_html(tag) or RSSDiscoveryScraper._safe_tag_text(tag)
            if value:
                return value
        return ""

    @staticmethod
    def _extract_raw_summary(raw_node: Any) -> str:
        if raw_node is None:
            return ""
        tag = raw_node.find("summary")
        return RSSDiscoveryScraper._safe_tag_html(tag) or RSSDiscoveryScraper._safe_tag_text(tag)

    @staticmethod
    def _extract_raw_description(raw_node: Any) -> str:
        if raw_node is None:
            return ""
        tag = raw_node.find("description")
        return RSSDiscoveryScraper._safe_tag_html(tag) or RSSDiscoveryScraper._safe_tag_text(tag)

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
    def _is_image_candidate(
        cls,
        url: Any,
        *,
        media_type: Any = None,
        medium: Any = None,
        force: bool = False,
    ) -> bool:
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
    def _extract_cover_url(cls, entry: dict, base_url: str) -> Optional[str]:
        candidates: list[str] = []
        seen: set[str] = set()

        def add_candidate(
            url: Any,
            *,
            media_type: Any = None,
            medium: Any = None,
            force: bool = False,
        ) -> None:
            if not cls._is_image_candidate(
                url,
                media_type=media_type,
                medium=medium,
                force=force,
            ):
                return
            normalized = cls._normalize_candidate_url(url, base_url)
            if normalized and normalized not in seen:
                seen.add(normalized)
                candidates.append(normalized)

        media_thumbnails = entry.get("media_thumbnail") or []
        if isinstance(media_thumbnails, dict):
            media_thumbnails = [media_thumbnails]
        for thumbnail in media_thumbnails:
            if isinstance(thumbnail, dict):
                add_candidate(thumbnail.get("url") or thumbnail.get("href"), force=True)

        media_contents = entry.get("media_content") or []
        if isinstance(media_contents, dict):
            media_contents = [media_contents]
        for media in media_contents:
            if isinstance(media, dict):
                add_candidate(
                    media.get("url") or media.get("href"),
                    media_type=media.get("type"),
                    medium=media.get("medium"),
                )

        for link in entry.get("links", []) or []:
            if not isinstance(link, dict):
                continue
            if str(link.get("rel") or "").lower() != "enclosure":
                continue
            add_candidate(
                link.get("href") or link.get("url"),
                media_type=link.get("type"),
            )

        image = entry.get("image")
        if isinstance(image, dict):
            add_candidate(image.get("href") or image.get("url"), force=True)
        elif isinstance(image, str):
            add_candidate(image, force=True)

        return candidates[0] if candidates else None
