"""
Twitter/X 平台适配器 - 使用 FxTwitter API
无需登录/cookies，通过第三方服务获取推文内容
"""
import re
from datetime import datetime
from datetime import timezone
from app.utils.url_utils import normalize_datetime_for_db
from typing import Optional, Dict, Any
from urllib.parse import urlparse
import httpx

from app.core.logging import logger
from app.adapters.base import PlatformAdapter, ParsedContent
from app.adapters.errors import (
    NonRetryableAdapterError,
    RetryableAdapterError,
)
from app.models import TwitterContentType
from app.core.config import settings


class TwitterFxAdapter(PlatformAdapter):
    """
    Twitter/X 适配器 - 使用 FxTwitter API
    
    优势:
    - ✅ 无需登录或 cookies
    - ✅ 免费使用，无需 API key
    - ✅ 返回完整的推文数据（文本、图片、视频等）
    - ✅ 不会被 Cloudflare 拦截
    
    限制:
    - ⚠️ 依赖第三方服务 (fxtwitter.com)
    - ⚠️ 可能有速率限制
    - ⚠️ 无法获取需要登录才能看的内容
    """
    
    PLATFORM_NAME = "twitter"
    SUPPORTED_DOMAINS = ["twitter.com", "x.com", "mobile.twitter.com", "mobile.x.com"]
    
    # FxTwitter API 端点
    FXTWITTER_API = "https://api.fxtwitter.com"
    
    def __init__(self, **kwargs):
        """
        初始化 Twitter 适配器
        
        Args:
            **kwargs: 兼容参数（Twitter 适配器不需要任何配置）
        """
        # FxTwitter API 不需要 cookies 或其他配置
        # 忽略所有传入的参数
        pass
    
    async def can_handle(self, url: str) -> bool:
        """检查是否可以处理该 URL"""
        parsed = urlparse(url)
        domain = parsed.netloc.lower().replace("www.", "")
        return domain in self.SUPPORTED_DOMAINS
    
    async def clean_url(self, url: str) -> str:
        """
        清理 URL，移除追踪参数
        
        Args:
            url: 原始 URL
            
        Returns:
            清理后的 URL
        """
        # 移除常见的追踪参数
        parsed = urlparse(url)
        
        # 提取基本路径（去除查询参数和片段）
        clean = f"{parsed.scheme}://{parsed.netloc}{parsed.path}"
        
        return clean
    
    def detect_content_type(self, url: str) -> str:
        """
        检测内容类型（在实际解析前的快速判断）
        
        Args:
            url: Twitter URL
            
        Returns:
            内容类型字符串
        """
        # Twitter URL 无法从 URL 直接判断类型，需要解析后才知道
        # 默认返回 TWEET
        return TwitterContentType.TWEET.value
    
    def _extract_tweet_id(self, url: str) -> Optional[tuple[str, str]]:
        """
        从 URL 提取用户名和推文ID
        
        Returns:
            tuple[username, tweet_id] 或 None
        """
        # 支持多种 URL 格式:
        # https://twitter.com/username/status/1234567890
        # https://x.com/username/status/1234567890
        # https://mobile.twitter.com/username/status/1234567890
        patterns = [
            r'(?:twitter|x)\.com/([^/]+)/status/(\d+)',
            r'mobile\.(?:twitter|x)\.com/([^/]+)/status/(\d+)',
        ]
        
        for pattern in patterns:
            match = re.search(pattern, url)
            if match:
                username = match.group(1)
                tweet_id = match.group(2)
                return (username, tweet_id)
        
        return None
    
    async def parse(self, url: str) -> ParsedContent:
        """
        解析 Twitter URL，使用 FxTwitter API 获取内容
        
        Args:
            url: Twitter/X 推文链接
            
        Returns:
            ParsedContent: 解析后的内容
            
        Raises:
            NonRetryableAdapterError: URL 格式错误或推文不存在
            RetryableAdapterError: 网络错误或 API 暂时不可用
        """
        # 提取推文信息
        tweet_info = self._extract_tweet_id(url)
        if not tweet_info:
            raise NonRetryableAdapterError(f"无法从 URL 提取推文信息: {url}")
        
        username, tweet_id = tweet_info
        logger.info(f"解析 Twitter 推文: @{username}/status/{tweet_id}")
        
        # 构建 FxTwitter API URL
        api_url = f"{self.FXTWITTER_API}/{username}/status/{tweet_id}"
        logger.debug(f"FxTwitter API URL: {api_url}")
        
        try:
            # 创建 HTTP 客户端（使用代理如果配置了）
            proxy = settings.http_proxy or settings.https_proxy
            timeout = httpx.Timeout(30.0, read=60.0)
            
            # 设置请求头（模拟浏览器避免被拦截）
            headers = {
                "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36",
                "Accept": "application/json",
                "Accept-Language": "zh-CN,zh;q=0.9,en;q=0.8",
            }
            
            async with httpx.AsyncClient(proxy=proxy, timeout=timeout, headers=headers, follow_redirects=True) as client:
                response = await client.get(api_url)
                
                # 检查响应状态
                if response.status_code == 404:
                    raise NonRetryableAdapterError(
                        f"推文不存在或已被删除 (Tweet ID: {tweet_id})"
                    )
                elif response.status_code == 429:
                    raise RetryableAdapterError(
                        "FxTwitter API 速率限制，请稍后重试"
                    )
                elif response.status_code >= 500:
                    raise RetryableAdapterError(
                        f"FxTwitter API 服务器错误 ({response.status_code})"
                    )
                elif response.status_code != 200:
                    raise NonRetryableAdapterError(
                        f"FxTwitter API 请求失败: {response.status_code}"
                    )
                
                # 解析 JSON 响应
                data = response.json()
                
                # FxTwitter API 返回格式:
                # {
                #   "code": 200,
                #   "message": "OK",
                #   "tweet": { ... }
                # }
                if data.get("code") != 200:
                    error_msg = data.get("message", "Unknown error")
                    raise NonRetryableAdapterError(f"FxTwitter API 错误: {error_msg}")
                
                tweet = data.get("tweet")
                if not tweet:
                    raise NonRetryableAdapterError("FxTwitter API 返回数据格式错误")
                
                return self._parse_tweet_data(tweet, url)
        
        except httpx.TimeoutException:
            raise RetryableAdapterError("FxTwitter API 请求超时")
        except httpx.NetworkError as e:
            raise RetryableAdapterError(f"网络错误: {str(e)}")
        except Exception as e:
            if isinstance(e, (NonRetryableAdapterError, RetryableAdapterError)):
                raise
            logger.error(f"解析 Twitter 推文时出错: {e}", exc_info=True)
            raise NonRetryableAdapterError(f"解析失败: {str(e)}")
    
    def _parse_tweet_data(self, tweet: Dict[str, Any], original_url: str) -> ParsedContent:
        """
        解析 FxTwitter API 返回的推文数据
        
        Args:
            tweet: FxTwitter API 返回的推文对象
            original_url: 原始URL
            
        Returns:
            ParsedContent
        """
        # 提取基本信息
        author = tweet.get("author", {})
        text = tweet.get("text", "")
        created_at_str = tweet.get("created_at")  # ISO 8601 格式
        
        # 提取媒体
        media_list = []
        media_objects = tweet.get("media", {}).get("all", []) or tweet.get("media", {}).get("photos", [])
        
        for media in media_objects:
            media_url = media.get("url")
            media_type = media.get("type", "photo")  # photo, video, gif
            
            if media_url:
                media_list.append({
                    "type": "video" if media_type in ["video", "gif"] else "image",
                    "url": media_url,
                    "thumbnail_url": media.get("thumbnail_url"),
                    "width": media.get("width"),
                    "height": media.get("height"),
                })
        
        # 解析时间 (Twitter 格式: "Sat Jan 03 02:37:01 +0000 2026")
        published_at = None
        if created_at_str:
            try:
                # Twitter 时间格式: "Sat Jan 03 02:37:01 +0000 2026"
                published_at = datetime.strptime(created_at_str, "%a %b %d %H:%M:%S %z %Y")
                # 规范化为 UTC naive（与数据库模型中 utcnow() 的行为一致）
                published_at = normalize_datetime_for_db(published_at)
            except Exception as e:
                logger.warning(f"解析推文时间失败: {e}")
        
        # 构建存档结构（用于媒体处理）
        archive_images = []
        archive_videos = []
        for media in media_list:
            if media.get("type") == "image":
                archive_images.append({
                    "url": media["url"],
                    "width": media.get("width"),
                    "height": media.get("height"),
                    "thumbnail_url": media.get("thumbnail_url"),
                })
            elif media.get("type") == "video":
                archive_videos.append({
                    "url": media["url"],
                    "width": media.get("width"),
                    "height": media.get("height"),
                    "thumbnail_url": media.get("thumbnail_url"),
                })
        
        # 构建元数据
        raw_metadata = {
            "source": "fxtwitter_api",
            "api_version": "1.0",
            "tweet_id": tweet.get("id"),
            "author": {
                "id": author.get("id"),
                "name": author.get("name"),
                "screen_name": author.get("screen_name"),
                "avatar_url": author.get("avatar_url"),
                "banner_url": author.get("banner_url"),
                "description": author.get("description"),
                "followers": author.get("followers"),
                "following": author.get("following"),
                "verified": author.get("verified", False),
            },
            "stats": {
                "replies": tweet.get("replies"),
                "retweets": tweet.get("retweets"),
                "likes": tweet.get("likes"),
                "views": tweet.get("views"),
            },
            "lang": tweet.get("lang"),
            "possibly_sensitive": tweet.get("possibly_sensitive", False),
            "media": media_list,
            "poll": tweet.get("poll"),  # 如果是投票推文
            "quote": tweet.get("quote"),  # 如果是引用推文
            # "original_api_response": tweet,  # 移除冗余字段
            # 私有存档结构（用于媒体处理）
            "archive": {
                "type": "twitter_status",
                "version": "1",
                "images": archive_images,
                "videos": archive_videos,
            } if (archive_images or archive_videos) else None,
        }
        
        # 确定内容类型 (TwitterContentType 只有 TWEET 和 THREAD)
        content_type = TwitterContentType.TWEET
        
        # 提取推文ID
        tweet_id = tweet.get("id") or "unknown"
        
        # 收集媒体URL
        media_urls = [m["url"] for m in media_list if m.get("url")]
        
        # 构建统计数据（使用通用键名，与 Bilibili 适配器一致）
        stats = {
            "view": tweet.get("views") or 0,
            "like": tweet.get("likes") or 0,
            "share": tweet.get("retweets") or 0,
            "reply": tweet.get("replies") or 0,
            # Twitter 特有数据
            "bookmarks": tweet.get("bookmarks") or 0,
            "screen_name": author.get("screen_name"),
            "replying_to": tweet.get("replying_to"),
            # Twitter 没有 favorite（收藏）概念，保持为 0
            "favorite": 0,
        }
        
        return ParsedContent(
            platform=self.PLATFORM_NAME,
            content_type=content_type.value,
            content_id=tweet_id,
            clean_url=original_url,
            title=f"@{author.get('screen_name', 'unknown')}: {text[:50]}...",
            description=text,
            author_name=author.get('name'),
            author_id=author.get('screen_name'),  # 使用 screen_name 作为 author_id
            author_avatar_url=author.get('avatar_url'),  # 添加作者头像URL
            cover_url=media_list[0]["url"] if media_list else author.get("avatar_url"),
            media_urls=media_urls,
            published_at=published_at,
            stats=stats,
            raw_metadata=raw_metadata
        )
