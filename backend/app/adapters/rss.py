import re
import hashlib
from typing import Optional, List, Any
from bs4 import BeautifulSoup
import httpx
from loguru import logger
from datetime import datetime
from email.utils import parsedate_to_datetime

from app.adapters.base import PlatformAdapter, ParsedContent, LAYOUT_ARTICLE
from app.models.base import Platform
from app.utils.datetime_utils import normalize_datetime_for_db


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


class RssAdapter(PlatformAdapter):
    """RSS 适配器，支持 RSS Feed 批量解析"""
    
    def __init__(self, **kwargs):
        self.client = httpx.AsyncClient(
            follow_redirects=True, 
            timeout=20.0,
            headers={"User-Agent": "VaultStream/1.0 (Discovery Explorer)"}
        )

    async def close(self):
        await self.client.aclose()

    async def detect_content_type(self, url: str) -> Optional[str]:
        return "article"

    async def clean_url(self, url: str) -> str:
        return url

    async def parse(self, url: str) -> ParsedContent:
        raise NotImplementedError("RSS Adapter 目前主要用于频道批量拉取 (parse_channel)")

    def map_stats_to_content(self, content: Any, parsed: ParsedContent) -> None:
        self.map_common_stats(content, parsed.stats)

    async def parse_channel(self, url: str, limit: int = 20) -> List[ParsedContent]:
        """解析 RSS Feed（用于 Discovery）"""
        logger.info(f"RssAdapter: Fetching {url}")
        resp = await self.client.get(url)
        soup = BeautifulSoup(resp.text, 'xml')
        items = soup.find_all('item')
        
        feed_title = soup.find('title')
        author_name = feed_title.text if feed_title else "RSS Source"

        results = []
        for item in items[:limit]:
            try:
                title = item.title.text if item.title else "No Title"
                link = item.link.text if item.link else ""
                
                # 获取内容
                desc_html = item.find('content:encoded')
                if not desc_html:
                    desc_html = item.description
                html_text = desc_html.text if desc_html else ""
                
                # 解析发布时间
                published_at = None
                pub_date = item.find('pubDate')
                if pub_date:
                    try:
                        published_at = normalize_datetime_for_db(
                            parsedate_to_datetime(pub_date.text)
                        )
                    except Exception:
                        pass
                
                html_text = _convert_bbcode_to_html(html_text)
                content_soup = BeautifulSoup(html_text, 'html.parser')
                
                # 1. 还原媒体到正文位置
                media_urls = []
                for img in content_soup.find_all('img'):
                    src = img.get('src', '')
                    alt = img.get('alt', '图片')
                    if src:
                        media_urls.append(src)
                        # 原地替换为 Markdown 占位符
                        img.replace_with(f"\n![{alt}]({src})\n")
                
                # 2. 转换其他 HTML 标签为 Markdown
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
                
                body = content_soup.get_text(separator="\n\n").strip()
                # 清理多余空行
                body = re.sub(r'\n{3,}', '\n\n', body)
                
                guid_tag = item.find('guid')
                content_id = guid_tag.text if guid_tag is not None else hashlib.md5(link.encode()).hexdigest()

                parsed = ParsedContent(
                    platform=Platform.RSS.value,
                    content_type="article",
                    content_id=content_id,
                    clean_url=link,
                    layout_type=LAYOUT_ARTICLE,
                    title=title,
                    body=body,
                    author_name=author_name,
                    media_urls=media_urls,
                    published_at=published_at,
                    stats={},
                    rich_payload={}
                )
                results.append(parsed)
            except Exception as e:
                logger.warning(f"RssAdapter: 解析 RSS 单条目失败: {e}")
                continue
                
        return results
