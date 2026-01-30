"""
微博平台适配器

简化的主适配器，负责：
- URL类型检测（状态/用户主页）
- URL清洗和还原
- 路由到相应的parser

具体的解析逻辑已拆分到weibo_parser子模块
"""
import re
import httpx
from typing import Optional, Dict, Any
from app.core.logging import logger
from app.adapters.base import PlatformAdapter, ParsedContent
from app.adapters.errors import NonRetryableAdapterError
from app.core.config import settings

# 导入parser
from app.adapters.weibo_parser import parse_weibo, parse_user


class WeiboAdapter(PlatformAdapter):
    """
    微博内容解析适配器
    
    API: https://weibo.com/ajax/statuses/show?id={mblogid}
    依赖: settings.weibo_cookie
    """
    
    # URL模式
    # https://weibo.com/2656274875/49999...
    # https://weibo.com/detail/49999...
    # https://m.weibo.cn/status/49999...
    # https://weibo.com/u/5673255066
    # https://mapp.api.weibo.cn/fx/493bfdaf31cffc58f0ddcb59738cf77c.html
    URL_PATTERN = re.compile(r"(?:weibo\.com|weibo\.cn|mapp\.api\.weibo\.cn)/(?:(\d+)/|status/|detail/|u/|fx/)?([A-Za-z0-9]+)(?:\.html)?")

    def __init__(self, cookies: Optional[Dict[str, str]] = None):
        """
        初始化微博适配器
        
        Args:
            cookies: 微博cookies（可选）
        """
        self.cookies = cookies or {}

    async def detect_content_type(self, url: str) -> Optional[str]:
        """
        检测内容类型
        
        Args:
            url: 微博URL
            
        Returns:
            Optional[str]: 'user'或'status'，无法识别则返回None
        """
        if self.URL_PATTERN.search(url):
            if "/u/" in url:
                return "user"
            return "status"
        
        # mapp链接检测
        if "mapp.api.weibo.cn" in url:
            return "status"  # 可能是状态，将被还原
        
        return None

    async def clean_url(self, url: str) -> str:
        """
        净化URL
        
        还原短链接/移动端链接
        
        Args:
            url: 原始URL
            
        Returns:
            str: 净化后的URL
        """
        # 先还原短链/移动链接
        if "mapp.api.weibo.cn" in url or "m.weibo.cn" in url:
            try:
                # 使用移动端User-Agent以获得更好的重定向处理
                headers = {
                    "User-Agent": "Mozilla/5.0 (iPhone; CPU iPhone OS 15_0 like Mac OS X) AppleWebKit/605.1.15"
                }
                
                # 配置代理
                proxy = settings.http_proxy or settings.https_proxy
                
                # 对mapp链接使用GET请求，因为HEAD常常不能正确重定向
                async with httpx.AsyncClient(headers=headers, follow_redirects=True, timeout=10.0, proxy=proxy) as client:
                    resp = await client.get(url)
                    final_url = str(resp.url)
                    
                    # 检查是否跳转到了visitor.passport页面，从url参数中提取真实URL
                    if "visitor.passport.weibo.cn" in final_url:
                        from urllib.parse import urlparse, parse_qs, unquote
                        parsed = urlparse(final_url)
                        query_params = parse_qs(parsed.query)
                        if "url" in query_params:
                            real_url = unquote(query_params["url"][0])
                            logger.debug(f"从visitor页面提取真实URL: {real_url}")
                            url = real_url
                    elif "mapp.api.weibo.cn" in final_url:
                        # 尝试从响应体中解析
                        match_body = re.search(r'"mblogid":\s*"([a-zA-Z0-9]+)"', resp.text)
                        if match_body:
                            return f"https://weibo.com/detail/{match_body.group(1)}"
                        
                        match_bid = re.search(r'bid=([a-zA-Z0-9]+)', resp.text)
                        if match_bid:
                            return f"https://weibo.com/detail/{match_bid.group(1)}"
                    else:
                        url = final_url
            except Exception as e:
                logger.warning(f"还原移动端/mapp URL失败 {url}: {e}")

        match = self.URL_PATTERN.search(url)
        if match:
            part1 = match.group(1)
            part2 = match.group(2)
            
            # 检查是否为用户主页URL
            if "/u/" in url or (part1 is None and part2.isdigit() and len(part2) > 9): 
                if "/u/" in url:
                    return f"https://weibo.com/u/{part2}"

            bid = part2
            uid = part1
            if uid:
                return f"https://weibo.com/{uid}/{bid}"
            if bid:
                return f"https://weibo.com/detail/{bid}"
        
        return url.split("?")[0]

    async def parse(self, url: str) -> ParsedContent:
        """
        解析微博内容
        
        根据URL类型路由到相应的parser进行解析
        
        Args:
            url: 微博URL
            
        Returns:
            ParsedContent: 解析后的标准化内容
            
        Raises:
            NonRetryableAdapterError: 无效的微博URL
        """
        # 先还原URL（如果是mapp链接）
        if "mapp.api.weibo.cn" in url:
            url = await self.clean_url(url)

        # 准备请求头和cookies
        headers = {
            "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36",
            "Referer": "https://weibo.com/",
            "Accept": "application/json, text/plain, */*",
        }
        
        if settings.weibo_cookie:
            headers["Cookie"] = settings.weibo_cookie.get_secret_value().strip()
        
        request_cookies = None
        if "Cookie" not in headers and self.cookies:
            request_cookies = self.cookies

        # 准备代理
        proxies = None
        global_proxy = settings.http_proxy or settings.https_proxy
        if global_proxy:
            global_proxy = global_proxy.strip()
            proxies = {
                "http": global_proxy,
                "https": global_proxy
            }

        # 1. 处理用户主页
        if "/u/" in url:
            match = re.search(r"/u/(\d+)", url)
            if match:
                uid = match.group(1)
                return await parse_user(uid, url, headers, request_cookies or {}, proxies)

        # 2. 处理状态（推文）
        match = self.URL_PATTERN.search(url)
        if not match:
            raise NonRetryableAdapterError("无效的微博URL")
        
        bid = match.group(2)  # mblogid
        
        # 净化URL
        clean_url = await self.clean_url(url)
        
        return await parse_weibo(bid, clean_url, headers, request_cookies or {}, proxies)
