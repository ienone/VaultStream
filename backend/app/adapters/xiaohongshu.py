"""
小红书平台适配器

简化的主适配器，负责：
- URL类型检测（笔记/用户主页）
- URL清洗
- 路由到相应的parser

具体的解析逻辑已拆分到xiaohongshu_parser子模块
"""
import re
import httpx
from typing import Optional, Dict, Any
from urllib.parse import urlparse, parse_qs, quote

from xhshow import SessionManager, Xhshow

from app.core.logging import logger
from app.adapters.base import PlatformAdapter, ParsedContent
from app.adapters.errors import NonRetryableAdapterError
from app.adapters.xiaohongshu_profile import (
    DEFAULT_XHS_USER_AGENT,
    build_xhs_crypto_config,
)
from app.core.config import settings

# 导入parser
from app.adapters.xiaohongshu_parser import parse_note, parse_user


class XiaohongshuAdapter(PlatformAdapter):
    """
    小红书内容解析适配器
    
    使用xhshow库进行API签名，支持图文和视频笔记解析
    
    依赖:
    - settings.xiaohongshu_cookie: 必须配置有效的Cookie才能获取数据
    """
    
    USER_AGENT = DEFAULT_XHS_USER_AGENT

    # URL模式
    PATTERNS = {
        'note': [
            r'xiaohongshu\.com/explore/([a-f0-9]+)',
            r'xiaohongshu\.com/discovery/item/([a-f0-9]+)',
        ],
        'user': [
            r'xiaohongshu\.com/user/profile/([a-f0-9]+)',
        ],
    }
    
    def __init__(self, cookie: Optional[str] = None, cookies: Optional[Dict[str, str]] = None):
        """
        初始化
        
        Args:
            cookie: 小红书Cookie字符串
            cookies: 小红书Cookie字典（兼容worker调用）
        """
        # 兼容cookies字典参数
        if cookies and not cookie:
            cookie = "; ".join([f"{k}={v}" for k, v in cookies.items()])
        
        self.cookie_str = cookie or (
            settings.xiaohongshu_cookie.get_secret_value() 
            if settings.xiaohongshu_cookie else None
        )
        self.cookies = self._parse_cookies(self.cookie_str) if self.cookie_str else {}
        _config = build_xhs_crypto_config(self.USER_AGENT)
        self.xhs_client = Xhshow(_config)
        self._session = SessionManager(_config)
        self.headers = {
            'User-Agent': self.USER_AGENT,
            'Referer': 'https://www.xiaohongshu.com/',
            'Origin': 'https://www.xiaohongshu.com',
            'Accept': 'application/json, text/plain, */*',
            'Accept-Language': 'zh-CN,zh;q=0.9,en;q=0.8',
            'Content-Type': 'application/json;charset=UTF-8',
            'sec-ch-ua': '"Not:A-Brand";v="99", "Google Chrome";v="145", "Chromium";v="145"',
            'sec-ch-ua-mobile': '?0',
            'sec-ch-ua-platform': '"macOS"',
            'sec-fetch-dest': 'empty',
            'sec-fetch-mode': 'cors',
            'sec-fetch-site': 'same-site',
        }
    
    def _parse_cookies(self, cookie_str: str) -> Dict[str, str]:
        """解析Cookie字符串为字典"""
        return self.parse_cookie_str(cookie_str)
    
    def _extract_note_id(self, url: str) -> Optional[str]:
        """从URL中提取笔记ID"""
        for pattern in self.PATTERNS['note']:
            match = re.search(pattern, url)
            if match:
                return match.group(1)
        return None
    
    def _extract_user_id(self, url: str) -> Optional[str]:
        """从URL中提取用户ID"""
        for pattern in self.PATTERNS['user']:
            match = re.search(pattern, url)
            if match:
                return match.group(1)
        return None
    
    def _extract_xsec_token(self, url: str) -> Optional[str]:
        """从URL中提取xsec_token"""
        parsed = urlparse(url)
        params = parse_qs(parsed.query)
        return params.get('xsec_token', [None])[0]
    
    def _extract_xsec_source(self, url: str) -> str:
        """从URL中提取xsec_source"""
        parsed = urlparse(url)
        params = parse_qs(parsed.query)
        return params.get('xsec_source', ['pc_feed'])[0]
    
    async def detect_content_type(self, url: str) -> Optional[str]:
        """检测内容类型"""
        if self._extract_note_id(url):
            return 'note'
        if self._extract_user_id(url):
            return 'user_profile'
        return None
    
    async def clean_url(self, url: str) -> str:
        """
        净化URL，保留xsec_token和xsec_source以便后续访问
        """
        xsec_token = self._extract_xsec_token(url)
        xsec_source = self._extract_xsec_source(url)
        
        def build_query() -> str:
            params = []
            if xsec_token:
                params.append(f"xsec_token={xsec_token}")
            if xsec_source and xsec_source != "pc_feed":
                params.append(f"xsec_source={xsec_source}")
            return "?" + "&".join(params) if params else ""
        
        note_id = self._extract_note_id(url)
        if note_id:
            return f"https://www.xiaohongshu.com/explore/{note_id}{build_query()}"
        
        user_id = self._extract_user_id(url)
        if user_id:
            return f"https://www.xiaohongshu.com/user/profile/{user_id}{build_query()}"
        
        return url
    
    async def _resolve_short_link(self, url: str) -> str:
        """解析短链接"""
        if 'xhslink.com' not in url:
            return url
        
        async with httpx.AsyncClient(follow_redirects=True, timeout=10.0) as client:
            try:
                response = await client.get(url, headers={'User-Agent': self.headers['User-Agent']})
                return str(response.url)
            except Exception as e:
                logger.warning(f"解析小红书短链接失败: {e}")
                return url
    
    async def _refresh_cookie_from_settings(self) -> None:
        from app.services.settings_service import get_setting_value
        latest = await get_setting_value("xiaohongshu_cookie")
        if latest and latest != self.cookie_str:
            self.cookie_str = latest
            self.cookies = self._parse_cookies(latest)

    async def parse(self, url: str) -> ParsedContent:
        """
        解析小红书内容
        
        根据URL类型路由到相应的parser进行解析
        """
        await self._refresh_cookie_from_settings()

        # 解析短链接
        url = await self._resolve_short_link(url)
        
        content_type = await self.detect_content_type(url)
        
        if content_type == 'note':
            note_id = self._extract_note_id(url)
            if not note_id:
                raise NonRetryableAdapterError(f"无法从URL提取笔记ID: {url}")
            
            xsec_token = self._extract_xsec_token(url)
            xsec_source = self._extract_xsec_source(url)
            clean_url = await self.clean_url(url)
            
            return await parse_note(
                note_id,
                clean_url,
                self.xhs_client,
                self.cookies,
                self.headers,
                xsec_token,
                xsec_source,
                session=self._session,
            )
            
        elif content_type == 'user_profile':
            user_id = self._extract_user_id(url)
            if not user_id:
                raise NonRetryableAdapterError(f"无法从URL提取用户ID: {url}")
            
            xsec_token = self._extract_xsec_token(url)
            clean_url = await self.clean_url(url)
            
            return await parse_user(
                user_id,
                clean_url,
                self.xhs_client,
                self.cookies,
                self.headers,
                xsec_token,
                session=self._session,
            )
            
        else:
            raise NonRetryableAdapterError(f"不支持的小红书链接类型: {url}")

    def map_stats_to_content(self, content, parsed: ParsedContent) -> None:
        """小红书统计字段映射"""
        self.map_common_stats(content, parsed.stats)
