import re
import json
import logging
import requests
from typing import Optional, List, Dict, Any
from app.adapters.base import PlatformAdapter, ParsedContent
from app.adapters.errors import NonRetryableAdapterError, RetryableAdapterError, AuthRequiredAdapterError
from app.config import settings
from datetime import datetime

logger = logging.getLogger(__name__)

class WeiboAdapter(PlatformAdapter):
    """
    微博内容解析适配器
    
    API: https://weibo.com/ajax/statuses/show?id={mblogid}
    依赖: settings.weibo_cookie
    """
    
    # https://weibo.com/2656274875/49999... 
    # https://weibo.com/detail/49999...
    # https://m.weibo.cn/status/49999...
    # group 1: uid (optional), group 2: mblogid (bid)
    URL_PATTERN = re.compile(r"(?:weibo\.com|weibo\.cn)/(?:(\d+)/|status/|detail/)?([A-Za-z0-9]{9,})")

    def __init__(self, cookies: Optional[Dict[str, str]] = None):
        """
        初始化
        
        Args:
            cookies: 微博cookies（可选）
        """
        self.cookies = cookies or {}

    async def detect_content_type(self, url: str) -> Optional[str]:
        if self.URL_PATTERN.search(url):
            return "status"
        # mapp links detection
        if "mapp.api.weibo.cn" in url:
            return "status"
        return None

    async def clean_url(self, url: str) -> str:
        # Resolve short/mobile links first
        if "mapp.api.weibo.cn" in url or "m.weibo.cn" in url:
            try:
                # Use HEAD request to resolve redirect
                # Use allow_redirects=True to follow to the end
                resp = requests.head(url, allow_redirects=True, timeout=10)
                url = resp.url
            except Exception:
                pass # Fallback to original logic if network fails

        match = self.URL_PATTERN.search(url)
        if match:
            bid = match.group(2)
            uid = match.group(1)
            if uid:
                return f"https://weibo.com/{uid}/{bid}"
            return f"https://weibo.com/detail/{bid}"
        return url.split("?")[0]

    async def parse(self, url: str) -> ParsedContent:
        # Merge settings cookie and passed cookies
        cookies_dict = self.cookies.copy()
        
        # Priority: settings > passed cookies (usually settings has the secret value)
        if settings.weibo_cookie:
            # Assuming settings.weibo_cookie is a full cookie string, we might need to parse it if we want to merge granularly.
            # But here, we just use it as a header "Cookie" string if available, or rely on passed dict.
            # However, requests.get accepts `cookies` dict OR `headers={'Cookie': ...}`.
            # Let's prefer the dict for requests if possible, but the setting is a string.
            pass

        headers = {
            "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36",
            "Referer": "https://weibo.com/",
            "Accept": "application/json, text/plain, */*",
        }
        
        # If settings.weibo_cookie is set, use it as the Cookie header (it's usually a raw string)
        if settings.weibo_cookie:
             headers["Cookie"] = settings.weibo_cookie.get_secret_value()
        # If we have instance cookies (from factory), and no settings cookie, or we want to merge?
        # Usually settings.weibo_cookie contains the full auth.
        # If headers["Cookie"] is not set, we can use requests `cookies` parameter.
        
        request_cookies = None
        if "Cookie" not in headers and self.cookies:
            request_cookies = self.cookies

        match = self.URL_PATTERN.search(url)
        if not match:
            raise NonRetryableAdapterError("Invalid Weibo URL")
        
        bid = match.group(2) # mblogid
        
        api_url = f"https://weibo.com/ajax/statuses/show?id={bid}"
        
        try:
            response = requests.get(api_url, headers=headers, cookies=request_cookies, timeout=10)
            if response.status_code == 404:
                raise NonRetryableAdapterError(f"Weibo not found: {bid}")
            if response.status_code != 200:
                raise RetryableAdapterError(f"Failed to fetch Weibo API: {response.status_code}")
            
            data = response.json()
            
            # Check for auth failure
            if data.get("ok") != 1:
                # ok: -100 usually means login required
                if data.get("ok") == -100:
                    raise AuthRequiredAdapterError("Weibo login required (Visitor mode restricted)", details=data)
                # Other non-ok statuses
                if "text" not in data and "page_info" not in data:
                     raise NonRetryableAdapterError(f"Weibo API returned error status: {data.get('ok')}", details=data)

            if "text" not in data and "page_info" not in data:
                 raise NonRetryableAdapterError("Invalid Weibo data structure (possibly blocked or deleted)")

            # 构建标准化存档（用于媒体下载和展示）
            archive = self._build_weibo_archive(data)
            
            # 从存档中提取元数据
            title = archive.get("title", "微博分享")
            description = archive.get("plain_text", "")
            
            # 提取图片和视频（优先使用存档中的清洗结果）
            media_urls = []
            cover_url = ""
            
            for img in archive.get("images", []):
                if img.get("url"):
                    media_urls.append(img["url"])
            
            # 如果有视频，封面可能在视频信息里，或者单独的图片
            if archive.get("videos"):
                for vid in archive["videos"]:
                    if vid.get("url"):
                        media_urls.append(vid["url"])
            
            # 封面选择逻辑：优先使用图片，其次使用视频封面
            if archive.get("images"):
                cover_url = archive["images"][0].get("url")
            elif archive.get("videos"):
                cover_url = archive["videos"][0].get("cover")
            
            # 如果仍未找到封面，且 media_urls 存在（且不是视频），则使用第一个
            # 但既然已经分别处理了 images 和 videos，这里只要防止 cover_url 为空即可
            if not cover_url and media_urls:
                 # 简单检查是否为视频扩展名
                 first_media = media_urls[0]
                 if not (first_media.endswith(".mp4") or first_media.endswith(".mov")):
                     cover_url = first_media

            # 原有逻辑兼容：视频封面
            if not cover_url and "page_info" in data:
                 page_pic = data["page_info"].get("page_pic", {}).get("url")
                 if page_pic:
                     cover_url = page_pic
                     if page_pic not in media_urls:
                         media_urls.insert(0, page_pic)

            # 解析作者
            user = data.get("user", {})
            author_name = user.get("screen_name", "Unknown")
            author_id = str(user.get("id", ""))
            
            # 统计
            reposts_count = data.get("reposts_count", 0)
            comments_count = data.get("comments_count", 0)
            attitudes_count = data.get("attitudes_count", 0) # 点赞
            
            created_at_str = data.get("created_at") # "Tue Jan 09 12:00:00 +0800 2024"
            published_at = None
            if created_at_str:
                try:
                    # Python 3.7+ strptime %z can handle +0800
                    published_at = datetime.strptime(created_at_str, "%a %b %d %H:%M:%S %z %Y")
                except ValueError:
                    pass

            # clean_url logic is separate, but we can compute it here or use the one from helper
            cleaned_url = await self.clean_url(url)
            
            # 将 archive 放入 raw_metadata
            raw_metadata = data
            raw_metadata["archive"] = archive

            return ParsedContent(
                platform="weibo",
                content_type="status",
                content_id=bid,
                clean_url=cleaned_url,
                title=title[:100], 
                description=description,
                author_name=author_name,
                author_id=author_id,
                cover_url=cover_url,
                media_urls=media_urls,
                published_at=published_at,
                raw_metadata=raw_metadata,
                stats={
                    "repost": reposts_count,
                    "reply": comments_count,
                    "like": attitudes_count,
                    "share": reposts_count  # mapping share to repost for generic stats
                }
            )

        except requests.RequestException as e:
            raise RetryableAdapterError(f"Network error: {str(e)}")
        except Exception as e:
            logger.exception("Error parsing Weibo content")
            raise NonRetryableAdapterError(f"Unexpected error: {str(e)}")

    def _build_weibo_archive(self, data: Dict[str, Any]) -> Dict[str, Any]:
        """构建标准化存档结构"""
        text_html = data.get("text", "")
        # 简单清洗 HTML
        plain_text = re.sub(r'<[^>]+>', '', text_html).strip()
        
        archive = {
            "type": "weibo_status",
            "title": plain_text[:50] if plain_text else "微博内容",
            "plain_text": plain_text,
            "images": [],
            "videos": [],
            "markdown": plain_text # 暂且直接用纯文本作为 markdown
        }
        
        # 图片提取
        pic_infos = data.get("pic_infos", {})
        sorted_keys = data.get("pic_ids", [])
        
        # 如果 pic_ids 存在，按顺序提取；否则遍历字典
        keys_to_iter = sorted_keys if sorted_keys else pic_infos.keys()
        
        for pid in keys_to_iter:
            info = pic_infos.get(pid)
            url = None
            width = None
            height = None
            
            if info:
                largest = info.get("largest", {}).get("url")
                mw2000 = info.get("mw2000", {}).get("url")
                url = mw2000 or largest
                width = info.get("largest", {}).get("width")
                height = info.get("largest", {}).get("height")
            else:
                # Fallback: Construct URL from pid
                # Usually https://wx1.sinaimg.cn/large/{pid}.jpg works
                if pid:
                    url = f"https://wx1.sinaimg.cn/large/{pid}.jpg"
            
            if url:
                archive["images"].append({
                    "url": url,
                    "width": width,
                    "height": height
                })

        # 视频提取
        video_url = None
        cover_url = None
        
        # 1. Check page_info
        if "page_info" in data and data["page_info"].get("type") == "video":
            page_info = data["page_info"]
            media_info = page_info.get("media_info", {})
            video_url = (
                media_info.get("mp4_720p_mp4") or 
                media_info.get("mp4_hd_url") or 
                media_info.get("stream_url_hd") or 
                media_info.get("stream_url")
            )
            cover_url = page_info.get("page_pic", {}).get("url")

        # 2. Check mix_media_info (Newer structure)
        if not video_url and "mix_media_info" in data:
            items = data["mix_media_info"].get("items", [])
            for item in items:
                if item.get("type") == "video":
                    media_info = item.get("data", {}).get("media_info", {})
                    video_url = (
                        media_info.get("mp4_720p_mp4") or 
                        media_info.get("stream_url_hd") or 
                        media_info.get("stream_url")
                    )
                    # cover often in data.page_pic
                    if not cover_url:
                         # try to find cover in mix items
                         pass
                    break

        if video_url:
            archive["videos"].append({
                "url": video_url,
                "cover": cover_url,
                # Duration/dimensions might be missing in fallback, but acceptable
            })
                
        return archive