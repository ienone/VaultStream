"""RSS/Atom discovery mapping."""

import os
import re
from typing import Optional

from app.adapters import managed_adapter
from app.adapters.discovery.base import BaseDiscoveryScraper, DiscoveryItem
from app.adapters.rss import RssAdapter


class RSSDiscoveryScraper(BaseDiscoveryScraper):
    """Map the canonical RSS parser output into discovery items."""

    async def fetch(
        self,
        last_cursor: Optional[str] = None,
    ) -> tuple[list[DiscoveryItem], Optional[str]]:
        feed_url = self._expand_env_vars(self.config.get("url", ""))
        if not feed_url:
            raise ValueError("RSS 来源缺少订阅地址")

        async with managed_adapter(RssAdapter(timeout=30.0)) as adapter:
            parsed_contents = await adapter.parse_channel(feed_url, limit=None)

        if not parsed_contents:
            return [], last_cursor

        new_cursor = parsed_contents[0].content_id or last_cursor
        category = str(self.config.get("category") or "").strip()
        items: list[DiscoveryItem] = []
        for parsed in parsed_contents:
            if last_cursor and parsed.content_id == last_cursor:
                break

            tags = list(parsed.source_tags or [])
            if category and category not in tags:
                tags.append(category)
            items.append(
                DiscoveryItem(
                    url=parsed.clean_url,
                    title=parsed.title or "Untitled",
                    content=parsed.body or "",
                    author=parsed.author_name,
                    author_avatar_url=parsed.author_avatar_url,
                    author_url=parsed.author_url,
                    published_at=parsed.published_at,
                    source_tags=tags,
                    cover_url=parsed.cover_url,
                    media_urls=parsed.media_urls,
                    rich_payload=parsed.rich_payload,
                    extra_stats=parsed.stats,
                    layout_type=parsed.layout_type,
                    archive_metadata=parsed.archive_metadata,
                    raw_metadata={"feed_url": feed_url, "entry_id": parsed.content_id},
                )
            )

        return items, new_cursor

    @staticmethod
    def _expand_env_vars(url: str) -> str:
        return re.sub(
            r"\$\{(\w+)\}",
            lambda match: os.environ.get(match.group(1), match.group(0)).strip(),
            url,
        )
