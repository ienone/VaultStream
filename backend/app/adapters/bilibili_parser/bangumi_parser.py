"""
B站番剧/影视解析器

负责解析B站番剧、电影等PGC内容
"""
import httpx
from typing import Dict, Any
from app.core.logging import logger
from app.adapters.base import ParsedContent
from app.adapters.errors import (
    AuthRequiredAdapterError,
    NonRetryableAdapterError,
    RetryableAdapterError,
)
from app.models import BilibiliContentType
from .base import safe_url, prune_metadata, format_request_error
import re


# API端点
API_BANGUMI_INFO = "https://api.bilibili.com/pgc/view/web/season"


async def parse_bangumi(
    url: str,
    headers: Dict[str, str],
    cookies: Dict[str, str]
) -> ParsedContent:
    """
    解析B站番剧/电影（PGC内容）
    
    Args:
        url: 番剧URL（已净化）
        headers: HTTP请求头
        cookies: 登录Cookie
        
    Returns:
        ParsedContent: 解析后的标准化内容
        
    Raises:
        AuthRequiredAdapterError: 需要登录
        NonRetryableAdapterError: 资源不可用
        RetryableAdapterError: 网络错误或API错误
    """
    # 提取番剧ID（ss或ep）
    match = re.search(r'bilibili\.com/bangumi/play/((?:ss|ep)\d+)', url)
    if not match:
        raise NonRetryableAdapterError(f"无法从URL提取番剧ID: {url}")
    
    id_val = match.group(1)
    
    # 准备API请求参数
    params = {}
    if id_val.startswith('ss'):
        params['season_id'] = id_val[2:]
    elif id_val.startswith('ep'):
        params['ep_id'] = id_val[2:]
    
    # 发起API请求
    async with httpx.AsyncClient(headers=headers, cookies=cookies, timeout=10.0) as client:
        try:
            response = await client.get(API_BANGUMI_INFO, params=params)
            data = response.json()
        except httpx.RequestError as e:
            raise RetryableAdapterError(f"B站请求失败: {format_request_error(e)}")
        
        # 检查API响应状态
        if data.get('code') != 0:
            code = data.get('code')
            msg = data.get('message')
            
            # 权限不足
            if code in (-403,):
                raise AuthRequiredAdapterError(f"B站权限不足: {msg}", details={"code": code})
            
            # 资源不可用
            if code in (-400, -404):
                raise NonRetryableAdapterError(f"B站资源不可用: {msg}", details={"code": code})
            
            # 其他错误
            raise RetryableAdapterError(f"B站API错误: {msg}", details={"code": code})
        
        # 提取数据
        item = data['result']
        
        # 提取互动数据
        stat = item.get('stat', {})
        stats = {
            'view': stat.get('views', 0),
            'like': stat.get('likes', 0),
            'favorite': stat.get('favorites', 0),
            'coin': stat.get('coins', 0),
            'reply': stat.get('reply', 0),
            'share': stat.get('share', 0),
            'danmaku': stat.get('danmakus', 0)
        }
        
        # 构建ParsedContent
        return ParsedContent(
            platform='bilibili',
            content_type=BilibiliContentType.BANGUMI.value,
            content_id=id_val,
            clean_url=url,
            title=item.get('title'),
            description=item.get('evaluate'),
            author_name="Bilibili Bangumi",
            author_id="0",
            cover_url=item.get('cover'),
            media_urls=[item.get('cover')] if item.get('cover') else [],
            published_at=None,
            raw_metadata=prune_metadata(dict(item)),
            stats=stats
        )
