"""
RSS/Atom 订阅源适配器

基于 Horizon RSSScraper 移植，适配 VaultStream DiscoverySource 模型。
"""
import calendar
import os
import re
from datetime import datetime, timezone
from email.utils import parsedate_to_datetime
from typing import Optional
from bs4 import BeautifulSoup

import feedparser
import httpx

from app.core.logging import logger
from app.adapters.discovery.base import BaseDiscoveryScraper, DiscoveryItem


class RSSDiscoveryScraper(BaseDiscoveryScraper):
    """RSS/Atom 订阅源抓取器。"""

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

                if last_cursor and entry_id == last_cursor:
                    break

                published_at = self._parse_date(entry)
                raw_content = self._extract_content(entry)
                
                # 强化版清洗逻辑：原地提取并替换为 Markdown (0-Token 策略)
                content_soup = BeautifulSoup(raw_content, 'html.parser')
                media_urls = []
                for img in content_soup.find_all('img'):
                    src = img.get('src', '')
                    alt = img.get('alt', '图片')
                    if src:
                        media_urls.append(src)
                        img.replace_with(f"\n![{alt}]({src})\n")
                
                for h in content_soup.find_all(['h1', 'h2', 'h3', 'h4', 'h5', 'h6']):
                    level = int(h.name[1])
                    h.replace_with(f"\n{'#' * level} {h.get_text()}\n")
                for b in content_soup.find_all(['b', 'strong']):
                    b.replace_with(f"**{b.get_text()}**")
                for a in content_soup.find_all('a'):
                    a.replace_with(f"[{a.get_text()}]({a.get('href', '')})")
                
                clean_body = content_soup.get_text(separator="\n\n").strip()
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
