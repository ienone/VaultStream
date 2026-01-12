import re
import httpx
from typing import Optional, Dict
from app.adapters.base import PlatformAdapter, ParsedContent
from app.adapters.errors import NonRetryableAdapterError, RetryableAdapterError, AuthRequiredAdapterError
from app.adapters.zhihu_parser import (
    parse_article,
    parse_question,
    parse_answer,
    parse_pin,
    parse_people
)
from app.config import settings

class ZhihuAdapter(PlatformAdapter):
    """知乎平台适配器"""
    
    HEADERS = {
        "authority": "zhuanlan.zhihu.com",
        "accept": "text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,image/apng,*/*;q=0.8,application/signed-exchange;v=b3;q=0.7",
        "accept-language": "zh-CN,zh;q=0.9,en-US;q=0.8,en;q=0.7",
        "cache-control": "no-cache",
        "user-agent": "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
    }

    def __init__(self, cookies: Optional[Dict[str, str]] = None):
        self.cookies = cookies or {}
        # 如果传入的 cookies 为空，尝试从 settings 加载
        if not self.cookies and settings.zhihu_cookie:
             # 解析 cookie 字符串
             cookie_str = settings.zhihu_cookie.get_secret_value()
             for item in cookie_str.split(';'):
                 if '=' in item:
                     k, v = item.strip().split('=', 1)
                     self.cookies[k] = v

    async def detect_content_type(self, url: str) -> Optional[str]:
        if "zhuanlan.zhihu.com/p/" in url:
            return "article"
        elif "zhihu.com/question/" in url and "answer" not in url:
            return "question"
        elif "zhihu.com/question/" in url and "answer" in url:
            return "answer"
        elif "zhihu.com/answer/" in url: # Direct answer link
            return "answer"
        elif "zhihu.com/pin/" in url:
            return "pin"
        elif "zhihu.com/people/" in url:
            return "user_profile"
        return None

    async def clean_url(self, url: str) -> str:
        # Simple cleanup: remove query params that are likely tracking
        # But keep URL clean.
        return url.split('?')[0]

    async def parse(self, url: str) -> ParsedContent:
        content_type = await self.detect_content_type(url)
        if not content_type:
            raise NonRetryableAdapterError(f"不支持的知乎 URL: {url}")

        clean_url = await self.clean_url(url)
        
        # Proxy configuration
        proxy_url = None
        if settings.https_proxy:
            proxy_url = settings.https_proxy
        elif settings.http_proxy:
            proxy_url = settings.http_proxy
            
        if proxy_url and proxy_url.startswith("socks://"):
            proxy_url = proxy_url.replace("socks://", "socks5://")
    
        async with httpx.AsyncClient(
            headers=self.HEADERS, 
            cookies=self.cookies, 
            follow_redirects=True, 
            timeout=15.0,
            proxy=proxy_url
        ) as client:
            try:
                response = await client.get(clean_url)
                if response.status_code == 404:
                    raise NonRetryableAdapterError(f"内容不存在: {url}")
                if response.status_code in (401, 403):
                     # Check if it's really auth issue or just anti-bot
                     if "安全验证" in response.text:
                         raise RetryableAdapterError("触发知乎安全验证，请稍后重试或更新 Cookie")
                     raise AuthRequiredAdapterError("访问知乎需要登录或权限不足")
                if response.status_code != 200:
                    raise RetryableAdapterError(f"知乎请求失败: {response.status_code}")
                
                html = response.text
                
                parsed_content = None
                if content_type == "article":
                    parsed_content = parse_article(html, clean_url)
                elif content_type == "question":
                    parsed_content = parse_question(html, clean_url)
                elif content_type == "answer":
                    parsed_content = parse_answer(html, clean_url)
                elif content_type == "pin":
                    parsed_content = parse_pin(html, clean_url)
                elif content_type == "user_profile":
                    parsed_content = parse_people(html, clean_url)

                if not parsed_content:
                     # Check if it was a redirect to login or verification
                     if "登录" in html or "验证" in html:
                         raise AuthRequiredAdapterError("可能需要更新 Cookie")
                     raise NonRetryableAdapterError(f"解析失败，未找到数据: {url}")
                
                return parsed_content

            except httpx.RequestError as e:
                raise RetryableAdapterError(f"网络请求错误: {e}")
