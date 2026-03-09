"""
RSS/Atom 订阅源适配器

基于 Horizon RSSScraper 移植，适配 VaultStream DiscoverySource 模型。
"""
import calendar
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
            async with httpx.AsyncClient(timeout=30) as client:
                response = await client.get(feed_url, follow_redirects=True)
                response.raise_for_status()

            feed = feedparser.parse(response.text)

            for entry in feed.entries:
                entry_id = entry.get("id") or entry.get("link") or ""
                entry_url = entry.get("link") or feed_url

                if last_cursor and entry_id == last_cursor:
                    break

                published_at = self._parse_date(entry)
                raw_content = self._extract_content(entry)
                explicit_cover_url = self._extract_cover_url(entry, entry_url)
                
                # BBCode → HTML 预处理（兼容论坛 RSS 源）
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
                
                for h in content_soup.find_all(['h1', 'h2', 'h3', 'h4', 'h5', 'h6']):
                    level = int(h.name[1])
                    h.replace_with(f"\n{'#' * level} {h.get_text()}\n")
                for b in content_soup.find_all(['b', 'strong']):
                    b.replace_with(f"**{b.get_text()}**")
                for i in content_soup.find_all(['i', 'em']):
                    i.replace_with(f"*{i.get_text()}*")
                for s in content_soup.find_all(['s', 'del', 'strike']):
                    s.replace_with(f"~~{s.get_text()}~~")
                for bq in content_soup.find_all('blockquote'):
                    lines = bq.get_text().strip().splitlines()
                    bq.replace_with("\n" + "\n".join(f"> {l}" for l in lines) + "\n")
                for code in content_soup.find_all('pre'):
                    code.replace_with(f"\n```\n{code.get_text()}\n```\n")
                for a in content_soup.find_all('a'):
                    a.replace_with(f"[{a.get_text()}]({a.get('href', '')})")

                # 块级元素显式处理：折叠内部内联节点，防止 get_text(separator) 在
                # 内联 NavigableString 兄弟节点之间注入多余换行（加粗/斜体换行 bug）
                for br in content_soup.find_all('br'):
                    br.replace_with("\n")
                for li in content_soup.find_all('li'):
                    if li.parent is not None:
                        li.replace_with("- " + li.get_text(separator="").strip() + "\n")
                for tag in content_soup.find_all(['p', 'div']):
                    if tag.parent is not None:
                        inner = tag.get_text(separator="").strip()
                        tag.replace_with(inner + "\n\n" if inner else "")

                # separator="" — 块级换行已在上方显式插入，不需要 separator 补充
                clean_body = content_soup.get_text(separator="").strip()
                clean_body = re.sub(r'\n{3,}', '\n\n', clean_body)

                tags = [tag.term for tag in entry.get("tags", [])]
                category = self.config.get("category")
                if category:
                    tags.append(category)

                item = DiscoveryItem(
                    url=entry.get("link", feed_url),
                    title=entry.get("title", "Untitled"),
                    content=clean_body,
                    author=entry.get("author", feed.feed.get("title")),
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
                first_id = feed.entries[0].get("id") or feed.entries[0].get("link") or ""
                if first_id:
                    new_cursor = first_id

        except Exception as e:
            logger.warning("RSS parse error for %s: %s", feed_url, e)

        return items, new_cursor

    @staticmethod
    def _convert_bbcode_to_html(text: str) -> str:
        """将常见 BBCode 标签转换为 HTML 等价标签。"""
        _flags = re.IGNORECASE | re.DOTALL
        text = re.sub(r'\[b\](.*?)\[/b\]', r'<strong>\1</strong>', text, flags=_flags)
        text = re.sub(r'\[i\](.*?)\[/i\]', r'<em>\1</em>', text, flags=_flags)
        text = re.sub(r'\[u\](.*?)\[/u\]', r'<u>\1</u>', text, flags=_flags)
        text = re.sub(r'\[s\](.*?)\[/s\]', r'<s>\1</s>', text, flags=_flags)
        text = re.sub(r'\[url=(.*?)\](.*?)\[/url\]', r'<a href="\1">\2</a>', text, flags=_flags)
        text = re.sub(r'\[url\](.*?)\[/url\]', r'<a href="\1">\1</a>', text, flags=_flags)
        text = re.sub(r'\[img\](.*?)\[/img\]', r'<img src="\1"/>', text, flags=_flags)
        text = re.sub(r'\[code\](.*?)\[/code\]', r'<pre><code>\1</code></pre>', text, flags=_flags)
        text = re.sub(r'\[quote\](.*?)\[/quote\]', r'<blockquote>\1</blockquote>', text, flags=_flags)
        text = re.sub(r'\[size=[^\]]*\](.*?)\[/size\]', r'\1', text, flags=_flags)
        text = re.sub(r'\[color=[^\]]*\](.*?)\[/color\]', r'\1', text, flags=_flags)
        return text

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
    def _extract_content(entry: dict) -> str:
        if "content" in entry and entry.content:
            return entry.content[0].get("value", "")
        if "summary" in entry:
            return entry.summary
        if "description" in entry:
            return entry.description
        return ""

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
