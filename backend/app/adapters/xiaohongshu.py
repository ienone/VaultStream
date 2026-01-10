import re
import json
import logging
import requests
from typing import Optional, List, Dict, Any
from app.adapters.base import PlatformAdapter, ParsedContent
from app.adapters.errors import NonRetryableAdapterError, RetryableAdapterError
from app.config import settings

logger = logging.getLogger(__name__)

class XiaohongshuAdapter(PlatformAdapter):
    """
    小红书内容解析适配器
    
    依赖:
    - settings.xiaohongshu_cookie: 必须配置有效的 Cookie 才能获取数据
    """
    
    # 匹配小红书笔记链接 (Explore 或 Discovery)
    # e.g., https://www.xiaohongshu.com/explore/64c878540000000010032e5c
    # e.g., https://www.xiaohongshu.com/discovery/item/64c878540000000010032e5c
    URL_PATTERN = re.compile(r"xiaohongshu\.com/(?:explore|discovery/item)/([a-f0-9]{24})")

    async def detect_content_type(self, url: str) -> Optional[str]:
        if self.URL_PATTERN.search(url):
            return "note"
        return None

    async def clean_url(self, url: str) -> str:
        # 提取 Note ID 并重组为标准 URL
        match = self.URL_PATTERN.search(url)
        if match:
            note_id = match.group(1)
            return f"https://www.xiaohongshu.com/explore/{note_id}"
        return url.split("?")[0]

    async def parse(self, url: str) -> ParsedContent:
        cookie = settings.xiaohongshu_cookie.get_secret_value() if settings.xiaohongshu_cookie else None
        if not cookie:
            raise NonRetryableAdapterError("Missing XIAOHONGSHU_COOKIE in settings. Please configure it to parse Xiaohongshu content.")

        match = self.URL_PATTERN.search(url)
        if not match:
            raise NonRetryableAdapterError("Invalid Xiaohongshu URL")
        
        note_id = match.group(1)
        headers = {
            "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36",
            "Cookie": cookie,
            "Referer": "https://www.xiaohongshu.com/",
            "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,image/apng,*/*;q=0.8",
        }

        try:
            # 1. 获取页面 HTML
            # 注意：此处使用同步 requests，但在 async 函数中。对于低频调用可接受；高并发应使用 httpx
            response = requests.get(url, headers=headers, timeout=10)
            
            if response.status_code == 404:
                raise NonRetryableAdapterError(f"Note not found: {url}")
            if response.status_code != 200:
                raise RetryableAdapterError(f"Failed to fetch page: {response.status_code}")
                
            html = response.text

            # 2. 提取 Initial State
            # window.__INITIAL_STATE__ = {...}
            state_match = re.search(r"window\.__INITIAL_STATE__\s*=\s*({.*?});", html, re.DOTALL)
            if not state_match:
                # 尝试另一种常见的 JSON 嵌入方式
                state_match = re.search(r"<script>window\.__INITIAL_STATE__=({.*?})</script>", html, re.DOTALL)
            
            if not state_match:
                 # 检测是否有验证码/重定向标记
                if "sec_u" in response.url or "captcha" in html:
                    raise RetryableAdapterError("Triggered Xiaohongshu anti-scraping/captcha. Cookie might be expired or IP blocked.")
                raise NonRetryableAdapterError("Failed to extract initial state from Xiaohongshu page")

            state_json_str = state_match.group(1)
            # 替换 undefined 为 null 以符合 JSON 规范
            state_json_str = state_json_str.replace("undefined", "null")
            
            try:
                data = json.loads(state_json_str)
            except json.JSONDecodeError as e:
                logger.error(f"JSON Decode Error for XHS: {e}")
                raise NonRetryableAdapterError("Failed to decode XHS JSON state")

            # 3. 解析数据
            # 路径通常在 note.noteDetailMap[note_id]
            note_data = data.get("note", {}).get("noteDetailMap", {}).get(note_id, {})
            if not note_data:
                # 备用路径: note.note (单条)
                note_data = data.get("note", {}).get("note", {})
            
            if not note_data:
                raise NonRetryableAdapterError("Note data is empty in state")

            # 提取字段
            title = note_data.get("title", "")
            desc = note_data.get("desc", "")
            user = note_data.get("user", {})
            author_name = user.get("nickname", "Unknown")
            author_id = user.get("userId", "")
            author_avatar = user.get("avatar", "")
            
            # 图片/视频
            media_urls = []
            image_list = note_data.get("imageList", [])
            for img in image_list:
                # 优先取高比如 1080p webp，如果没有则取 urlDefault
                # infoList 包含不同尺寸/格式
                # 简单起见，取 urlDefault
                url_default = img.get("urlDefault")
                if url_default:
                    media_urls.append(url_default)

            # 视频
            if note_data.get("type") == "video":
                video_info = note_data.get("video", {})
                consumer = video_info.get("consumer", {})
                origin_video = consumer.get("originVideoKey")
                # 视频地址构造比较复杂，通常 media.consumer.originVideoKey 是 key
                # 需要配合 dns 域名，如 http://sns-video-bd.xhscdn.com/{key}
                # 这里暂时尝试提取 masterUrl
                # 注意：视频通常有鉴权或时效性
                # 简单策略：如果有 imageList，作为图文存；如果是纯视频，尝试找 url
                # XHS 视频解析较复杂，暂时只存封面，未来扩展
                pass

            # 封面
            cover_url = ""
            if image_list:
                cover_url = image_list[0].get("urlDefault", "")
            
            # 统计数据
            interact_info = note_data.get("interactInfo", {})
            extra_stats = {
                "liked_count": interact_info.get("likedCount", 0),
                "collected_count": interact_info.get("collectedCount", 0),
                "comment_count": interact_info.get("commentCount", 0),
                "share_count": interact_info.get("shareCount", 0),
            }

            created_timestamp = note_data.get("time", 0) / 1000  # ms -> s
            from datetime import datetime
            published_at = datetime.fromtimestamp(created_timestamp) if created_timestamp else None
            
            tags = []
            tag_list = note_data.get("tagList", [])
            for t in tag_list:
                tags.append(t.get("name", ""))

            return ParsedContent(
                platform="xiaohongshu",
                title=title,
                description=desc,
                author_name=author_name,
                author_id=author_id,
                cover_url=cover_url,
                media_urls=media_urls,
                platform_id=note_id,
                content_type="note",
                published_at=published_at,
                tags=tags,
                raw_metadata=note_data,
                extra_stats=extra_stats
            )

        except requests.RequestException as e:
            raise RetryableAdapterError(f"Network error: {str(e)}")
        except Exception as e:
            logger.exception("Error parsing Xiaohongshu content")
            raise NonRetryableAdapterError(f"Unexpected error: {str(e)}")