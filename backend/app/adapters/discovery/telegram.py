"""
Telegram 频道发现源适配器
"""
from typing import Optional
from app.core.logging import logger
from app.adapters.discovery.base import BaseDiscoveryScraper, DiscoveryItem
from app.adapters.telegram import TelegramAdapter


class TelegramDiscoveryScraper(BaseDiscoveryScraper):
    """Telegram 频道抓取器"""

    async def fetch(self, last_cursor: Optional[str] = None) -> tuple[list[DiscoveryItem], Optional[str]]:
        channel_url = self.config.get("url", "")
        if not channel_url:
            logger.warning("Telegram source config missing 'url'")
            return [], last_cursor

        items: list[DiscoveryItem] = []
        new_cursor = last_cursor

        try:
            adapter = TelegramAdapter()
            parsed_contents = await adapter.parse_channel(channel_url, limit=15)
            await adapter.close()

            # Telegram 抓取的顺序是从旧到新（网页底部是最新消息）
            # 反转为从新到旧
            parsed_contents.reverse()

            for parsed in parsed_contents:
                # 使用 URL 中最后一个分段作为游标/ID
                entry_id = parsed.content_id
                
                if last_cursor and entry_id == last_cursor:
                    # 遇到上次抓取的记录，停止
                    break
                    
                category = self.config.get("category")
                tags = [category] if category else []

                item = DiscoveryItem(
                    url=parsed.clean_url,
                    title=parsed.title or "Telegram Message",
                    content=parsed.body or "",
                    author=parsed.author_name,
                    author_avatar_url=parsed.author_avatar_url,
                    author_url=parsed.author_url,
                    published_at=parsed.published_at,
                    source_tags=tags,
                    media_urls=parsed.media_urls,
                    rich_payload=parsed.rich_payload,
                    extra_stats=parsed.stats,
                    raw_metadata={"entry_id": entry_id},
                )
                items.append(item)

            if items:
                # 记录最新的 ID 为下次抓取的游标
                new_cursor = items[0].raw_metadata["entry_id"]

        except Exception as e:
            logger.error(f"Telegram parse error for {channel_url}: {e}")

        return items, new_cursor
