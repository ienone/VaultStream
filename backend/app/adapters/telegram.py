import re
import hashlib
from typing import Optional, List, Dict, Any
from urllib.parse import urlparse, urljoin
from bs4 import BeautifulSoup
import httpx
from loguru import logger
from datetime import datetime

from app.adapters.base import PlatformAdapter, ParsedContent, LAYOUT_ARTICLE, LAYOUT_GALLERY, LAYOUT_VIDEO
from app.models.base import Platform


class TelegramAdapter(PlatformAdapter):
    """Telegram 适配器，支持单条消息解析与频道批量解析"""
    
    def __init__(self, **kwargs):
        self.client = httpx.AsyncClient(
            follow_redirects=True, 
            timeout=20.0,
            headers={"User-Agent": "VaultStream/1.0 (Discovery Explorer)"}
        )

    async def close(self):
        await self.client.aclose()

    async def detect_content_type(self, url: str) -> Optional[str]:
        return "post"

    async def clean_url(self, url: str) -> str:
        parsed = urlparse(url)
        return f"{parsed.scheme}://{parsed.netloc}{parsed.path}"

    async def parse(self, url: str) -> ParsedContent:
        """解析单条 Telegram 消息（用于收藏库）"""
        clean_url = await self.clean_url(url)
        # 单条消息的 Web Preview 需要带 ?embed=1，或者直接请求
        if "/s/" not in clean_url and "?embed=1" not in url:
            embed_url = clean_url + "?embed=1"
        else:
            embed_url = clean_url
            
        resp = await self.client.get(embed_url)
        resp.raise_for_status()
        soup = BeautifulSoup(resp.text, 'html.parser')
        
        msg = soup.select_one('.tgme_widget_message')
        if not msg:
            raise ValueError(f"Telegram 消息解析失败，未找到有效内容: {url}")
            
        return self._parse_message_element(msg, clean_url)

    def map_stats_to_content(self, content: Any, parsed: ParsedContent) -> None:
        self.map_common_stats(content, parsed.stats)

    async def parse_channel(
        self, channel_url: str, limit: int = 20, *, last_cursor: str | None = None,
    ) -> List[ParsedContent]:
        """Read the latest page initially; subsequent runs catch up to the saved ID.

        Telegram public history exposes an older-page link with data-before.
        Never advance the caller's watermark across a failed or incomplete scan.
        """
        parsed_url = urlparse(channel_url)
        match = re.fullmatch(r"/(?:s/)?([A-Za-z0-9_]+)/?", parsed_url.path)
        if parsed_url.scheme != "https" or parsed_url.netloc != "t.me" or not match:
            raise ValueError("Telegram 订阅需要 https://t.me/频道名 公开频道地址")
        channel = match.group(1)
        channel_url = f"https://t.me/s/{channel}"
        watermark = None
        if last_cursor:
            cursor_match = re.fullmatch(r"([A-Za-z0-9_]+)/(\d+)", last_cursor)
            if not cursor_match or cursor_match.group(1).lower() != channel.lower():
                raise ValueError("Telegram 同步游标不属于当前频道，请重置游标")
            watermark = int(cursor_match.group(2))
        results: dict[int, ParsedContent] = {}
        before = None
        for _ in range(100):
            resp = await self.client.get(
                channel_url, params={"before": before} if before is not None else None,
            )
            resp.raise_for_status()
            soup = BeautifulSoup(resp.text, 'html.parser')
            if not soup.select_one('.tgme_channel_history'):
                raise ValueError("Telegram 未返回公开频道消息页")
            reached_watermark = False
            for msg in soup.select('.tgme_widget_message_wrap .tgme_widget_message'):
                identity = str(msg.get('data-post', ''))
                identity_match = re.fullmatch(r"([A-Za-z0-9_]+)/(\d+)", identity)
                if not identity_match or identity_match.group(1).lower() != channel.lower():
                    raise ValueError("Telegram 返回无效消息身份")
                message_id = int(identity_match.group(2))
                if watermark is not None and message_id <= watermark:
                    reached_watermark = True
                    continue
                item = self._parse_message_element(msg, f"https://t.me/{channel}/{message_id}")
                if item is None:
                    raise ValueError("Telegram 消息无法解析，未推进同步进度")
                results[message_id] = item
            ordered = [results[key] for key in sorted(results)]
            if watermark is None:
                return ordered[-limit:]
            if reached_watermark:
                return ordered
            older = soup.select_one('a.tme_messages_more[data-before]')
            if older is None:
                return ordered
            raw_before = str(older.get('data-before', ''))
            if not raw_before.isdigit():
                raise ValueError("Telegram 返回无效分页位置")
            next_before = int(raw_before)
            if before is not None and next_before >= before:
                raise ValueError("Telegram 分页未向历史推进")
            before = next_before
        raise ValueError("Telegram 增量超过单轮 100 页，未推进游标")

    def _parse_message_element(self, msg: BeautifulSoup, fallback_url: str) -> Optional[ParsedContent]:
        """将 DOM 元素转换为 ParsedContent"""
        text_elem = msg.select_one('.js-message_text')
        
        # 1. 发送者信息提取
        author_link = msg.select_one('.tgme_widget_message_owner_name')
        author_avatar = msg.select_one('.tgme_widget_message_user_photo img')
        
        author_name = author_link.get_text(strip=True) if author_link else "Unknown"
        author_url = author_link.get('href', '') if author_link else ""
        author_avatar_url = author_avatar.get('src', '') if author_avatar else ""

        # 2. 结构化解析引用回复
        quoted_content = None
        reply_elem = msg.select_one('.tgme_widget_message_reply')
        if reply_elem:
            q_author_elem = reply_elem.select_one('.tgme_widget_message_author_name')
            q_text_elem = reply_elem.select_one('.js-message_reply_text')
            q_url = reply_elem.get('href', '')
            
            q_thumb = None
            thumb_elem = reply_elem.select_one('.tgme_widget_message_reply_thumb')
            if thumb_elem and 'style' in thumb_elem.attrs:
                match = re.search(r"background-image:url\(['\"](.*?)['\"]\)", thumb_elem['style'])
                if match:
                    q_thumb = match.group(1)
            
            quoted_content = {
                "author": q_author_elem.get_text().strip() if q_author_elem else "未知",
                "text": q_text_elem.get_text().strip() if q_text_elem else "",
                "url": q_url,
                "thumbnail": q_thumb
            }

        # 3. 统计与元数据
        views_elem = msg.select_one('.tgme_widget_message_views')
        date_elem = msg.select_one('time')
        
        reactions = []
        for r in msg.select('.tgme_reaction'):
            emoji_node = r.select_one('b')
            emoji_text = emoji_node.get_text() if emoji_node else ""
            total_text = r.get_text(strip=True)
            count = total_text.replace(emoji_text, "").strip()
            reactions.append({"emoji": emoji_text, "count": count})

        views_str = views_elem.get_text(strip=True) if views_elem else "0"
        timestamp_str = date_elem.get('datetime', '') if date_elem else ""
        
        # 尝试转换时间
        published_at = None
        if timestamp_str:
            try:
                published_at = datetime.fromisoformat(timestamp_str.replace("Z", "+00:00"))
            except ValueError:
                pass

        # 4. 正文与媒体
        from app.adapters.telegram_text import telegram_html_to_markdown
        main_body = telegram_html_to_markdown(str(text_elem) if text_elem else '')
        title = main_body.split('\n')[0][:50] + "..." if main_body else "无正文内容"
        
        media_urls = []
        for photo_elem in msg.select('.tgme_widget_message_photo_wrap'):
            match = re.search(r"background-image:url\(['\"](.*?)['\"]\)", photo_elem.get('style', ''))
            if match and match.group(1) not in media_urls:
                media_urls.append(match.group(1))
        
        images = [{"url": url} for url in media_urls]
        videos = []
        cover_url = media_urls[0] if media_urls else None
        for player in msg.select('.tgme_widget_message_video_player'):
            poster = player.select_one('i[style]')
            match = re.search(r"background-image:url\(['\"](.*?)['\"]\)", poster.get('style', '')) if poster else None
            thumbnail = match.group(1) if match else None
            if thumbnail and not cover_url:
                cover_url = thumbnail
            for video in player.select('video.tgme_widget_message_video[src]'):
                url = urljoin(fallback_url, video['src'])
                if urlparse(url).scheme not in ('http', 'https') or url in media_urls:
                    continue
                media_urls.append(url)
                videos.append({"url": url, "thumbnail_url": thumbnail})

        # 5. 组装 Payload 和 Stats
        rich_payload = {}
        if quoted_content:
            rich_payload["quoted_content"] = quoted_content
            
        stats = {
            "telegram_views": views_str,
            "reactions": reactions
        }

        # 确定 LayoutType
        layout_type = LAYOUT_ARTICLE
        if videos:
            layout_type = LAYOUT_VIDEO
        elif images and len(main_body) < 100:
            layout_type = LAYOUT_GALLERY
            
        content_id = msg.get(
            'data-post',
            hashlib.md5(fallback_url.encode(), usedforsecurity=False).hexdigest(),
        )

        return ParsedContent(
            platform=Platform.TELEGRAM.value,
            content_type="post",
            content_id=content_id,
            clean_url=fallback_url,
            layout_type=layout_type,
            title=title,
            body=main_body,
            author_name=author_name,
            author_avatar_url=author_avatar_url,
            author_url=author_url,
            cover_url=cover_url,
            media_urls=media_urls,
            archive_metadata={"archive": {"type": "telegram_post", "version": "1",
                "images": images, "videos": videos}},
            published_at=published_at,
            stats=stats,
            rich_payload=rich_payload
        )
