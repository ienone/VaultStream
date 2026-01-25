"""
B站平台适配器

简化的主适配器，负责：
- URL类型检测
- URL清洗
- 路由到相应的parser

具体的解析逻辑已拆分到bilibili_parser子模块
"""
import re
import httpx
from typing import Optional, Dict
from urllib.parse import urlparse, parse_qs, urlencode
from app.logging import logger

from app.adapters.base import PlatformAdapter, ParsedContent
from app.models import BilibiliContentType

# 导入各个专门的parser
from app.adapters.bilibili_parser import (
    parse_video,
    parse_article,
    parse_dynamic,
    parse_bangumi,
    parse_live,
)


class BilibiliAdapter(PlatformAdapter):
    """
    B站适配器
    
    负责识别URL类型并路由到相应的parser进行解析
    """
    
    # URL模式
    PATTERNS = {
        BilibiliContentType.VIDEO: [
            r'bilibili\.com/video/(BV[0-9A-Za-z]{10})',
            r'bilibili\.com/video/av(\d+)',
            r'b23\.tv/(BV[0-9A-Za-z]{10})',
            r'b23\.tv/av(\d+)',
        ],
        BilibiliContentType.ARTICLE: [
            r'bilibili\.com/read/cv(\d+)',
        ],
        BilibiliContentType.DYNAMIC: [
            r'bilibili\.com/opus/(\d+)',
            r't\.bilibili\.com/(\d+)',
        ],
        BilibiliContentType.BANGUMI: [
            r'bilibili\.com/bangumi/play/(ss\d+)',
            r'bilibili\.com/bangumi/play/(ep\d+)',
        ],
        BilibiliContentType.AUDIO: [
            r'bilibili\.com/audio/au(\d+)',
        ],
        BilibiliContentType.LIVE: [
            r'live\.bilibili\.com/(\d+)',
        ],
        BilibiliContentType.CHEESE: [
            r'bilibili\.com/cheese/(ss\d+)',
            r'bilibili\.com/cheese/(ep\d+)',
        ],
    }
    
    def __init__(self, cookies: Optional[Dict[str, str]] = None):
        """
        初始化B站适配器
        
        Args:
            cookies: B站cookies（可选，用于访问需要登录的内容）
        """
        self.cookies = cookies or {}
        self.headers = {
            'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
            'Referer': 'https://www.bilibili.com',
        }

    async def detect_content_type(self, url: str) -> Optional[str]:
        """
        检测B站内容类型
        
        Args:
            url: B站URL
            
        Returns:
            Optional[str]: 内容类型，如果无法识别则返回None
        """
        # b23.tv的通用短链无法直接用正则识别类型，需要先还原
        if 'b23.tv' in url:
            url = await self._resolve_short_url(url)
        
        for content_type, patterns in self.PATTERNS.items():
            for pattern in patterns:
                if re.search(pattern, url):
                    return content_type.value
        return None
    
    async def clean_url(self, url: str) -> str:
        """
        净化URL
        
        去除追踪参数，保留必要的查询参数
        
        Args:
            url: 原始URL
            
        Returns:
            str: 净化后的URL
        """
        # 处理短链
        if 'b23.tv' in url:
            url = await self._resolve_short_url(url)
        
        # 移除追踪参数
        parsed = urlparse(url)
        clean_url = f"{parsed.scheme}://{parsed.netloc}{parsed.path}"
        
        # 保留必要的查询参数（如视频的p参数）
        if parsed.query:
            query_params = parse_qs(parsed.query)
            essential_params = {}
            if 'p' in query_params:  # 视频分P
                essential_params['p'] = query_params['p'][0]
            if essential_params:
                clean_url += '?' + urlencode(essential_params)
        
        return clean_url
    
    async def _resolve_short_url(self, short_url: str) -> str:
        """
        解析短链
        
        Args:
            short_url: 短链URL
            
        Returns:
            str: 解析后的完整URL
        """
        try:
            async with httpx.AsyncClient(follow_redirects=True, timeout=10.0) as client:
                response = await client.get(short_url, headers=self.headers)
                return str(response.url)
        except Exception as e:
            logger.error(f"解析短链失败: {short_url}, 错误: {e}")
            return short_url
    
    async def parse(self, url: str) -> ParsedContent:
        """
        解析B站内容
        
        根据URL类型路由到相应的parser进行解析
        
        Args:
            url: B站URL
            
        Returns:
            ParsedContent: 解析后的标准化内容
            
        Raises:
            NonRetryableAdapterError: 不支持的URL类型
        """
        # 先净化再识别：确保通用b23.tv短链也能解析
        clean_url = await self.clean_url(url)

        content_type = await self.detect_content_type(clean_url)
        if not content_type:
            from app.adapters.errors import NonRetryableAdapterError
            raise NonRetryableAdapterError(f"不支持的B站URL: {url}")
        
        # 根据内容类型路由到相应的parser
        if content_type == BilibiliContentType.VIDEO.value:
            return await parse_video(clean_url, self.headers, self.cookies)
        
        elif content_type == BilibiliContentType.ARTICLE.value:
            return await parse_article(clean_url, self.headers, self.cookies)
        
        elif content_type == BilibiliContentType.BANGUMI.value:
            return await parse_bangumi(clean_url, self.headers, self.cookies)
        
        elif content_type == BilibiliContentType.LIVE.value:
            return await parse_live(clean_url, self.headers, self.cookies)
        
        elif content_type == BilibiliContentType.DYNAMIC.value:
            return await parse_dynamic(clean_url, self.headers, self.cookies)
        
        # 其他类型暂未实现
        from app.adapters.errors import NonRetryableAdapterError
        raise NonRetryableAdapterError(f"尚未实现 {content_type} 的解析")
