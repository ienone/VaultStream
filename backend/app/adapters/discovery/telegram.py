"""
Telegram 频道发现源适配器
"""
from typing import Optional
from app.adapters import managed_adapter
from app.adapters.discovery.base import BaseDiscoveryScraper, DiscoveryItem
from app.adapters.telegram import TelegramAdapter


class TelegramDiscoveryScraper(BaseDiscoveryScraper):
    """Telegram 频道抓取器"""

    async def fetch(self, last_cursor: Optional[str] = None) -> tuple[list[DiscoveryItem], Optional[str]]:
        channel_url = self.config.get("url", "")
        if not channel_url:
            raise ValueError("Telegram 订阅缺少频道 URL")

        items: list[DiscoveryItem] = []
        new_cursor = last_cursor

        try:
            async with managed_adapter(TelegramAdapter()) as adapter:
                parsed_contents = await adapter.parse_channel(channel_url, last_cursor=last_cursor)

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
                    cover_url=parsed.cover_url,
                    media_urls=parsed.media_urls,
                    layout_type=parsed.layout_type,
                    archive_metadata=parsed.archive_metadata,
                    rich_payload=parsed.rich_payload,
                    extra_stats=parsed.stats,
                    raw_metadata={"entry_id": entry_id},
                )
                items.append(item)

            if items:
                # 记录最新的 ID 为下次抓取的游标
                new_cursor = items[0].raw_metadata["entry_id"]

        except Exception:
            # The task persists this message. Never include subscription URLs,
            # response bodies or credentials in the durable failure receipt.
            raise ValueError("Telegram 频道抓取或解析失败，请检查公开频道地址与网络") from None

        return items, new_cursor
