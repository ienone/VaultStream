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
            
        logger.info(f"TelegramAdapter: Fetching single message {embed_url}")
        resp = await self.client.get(embed_url)
        soup = BeautifulSoup(resp.text, 'html.parser')
        
        msg = soup.select_one('.tgme_widget_message')
        if not msg:
            raise ValueError(f"Telegram 消息解析失败，未找到有效内容: {url}")
            
        return self._parse_message_element(msg, clean_url)

    def map_stats_to_content(self, content: Any, parsed: ParsedContent) -> None:
        self.map_common_stats(content, parsed.stats)

    async def parse_channel(self, channel_url: str, limit: int = 20) -> List[ParsedContent]:
        """解析 Telegram 频道（用于 Discovery）"""
        if "/s/" not in channel_url:
            channel_url = channel_url.replace("t.me/", "t.me/s/")
        
        logger.info(f"TelegramAdapter: Fetching channel {channel_url}")
        resp = await self.client.get(channel_url)
        soup = BeautifulSoup(resp.text, 'html.parser')
        
        messages = soup.select('.tgme_widget_message_wrap')
        results = []
        
        for msg in messages[-limit:]:
            try:
                msg_elem = msg.select_one('.tgme_widget_message')
                if not msg_elem:
                    continue
                
                # 尝试提取当前消息的链接
                link_elem = msg_elem.select_one('.tgme_widget_message_date')
                msg_url = link_elem['href'] if link_elem else channel_url
                
                parsed_msg = self._parse_message_element(msg_elem, msg_url)
                if parsed_msg:
                    results.append(parsed_msg)
            except Exception as e:
                logger.warning(f"TelegramAdapter: 解析单条频道消息失败: {e}")
                continue
                
        return results

    def _parse_message_element(self, msg: BeautifulSoup, fallback_url: str) -> Optional[ParsedContent]:
        """将 DOM 元素转换为 ParsedContent"""
        text_elem = msg.select_one('.js-message_text')
        if not text_elem: 
            return None
        
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
        content_copy = BeautifulSoup(str(text_elem), 'html.parser')
        for a in content_copy.find_all('a'):
            a.replace_with(f"[{a.get_text()}]({a.get('href', '')})")
        for b in content_copy.find_all(['b', 'strong']):
            b.replace_with(f"**{b.get_text()}**")
        
        main_body = content_copy.get_text(separator="\n").strip()
        title = main_body.split('\n')[0][:50] + "..." if main_body else "无正文内容"
        
        media_urls = []
        photo_elem = msg.select_one('.tgme_widget_message_photo_wrap')
        if photo_elem and 'style' in photo_elem.attrs:
            match = re.search(r"background-image:url\(['\"](.*?)['\"]\)", photo_elem['style'])
            if match:
                media_urls.append(match.group(1))
        
        video_elem = msg.select_one('.tgme_widget_message_video_player i')
        if video_elem and 'style' in video_elem.attrs:
            match = re.search(r"background-image:url\(['\"](.*?)['\"]\)", video_elem['style'])
            if match:
                # 在此设计中，将其视为视频的缩略图占位
                media_urls.append(match.group(1))

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
        if len(media_urls) >= 1 and len(main_body) < 100:
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
            media_urls=media_urls,
            published_at=published_at,
            stats=stats,
            rich_payload=rich_payload
        )
