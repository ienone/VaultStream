"""
B站专栏文章解析器

负责解析B站专栏文章内容
"""
import httpx
from datetime import datetime
from typing import Dict, Any
from app.logging import logger
from app.adapters.base import ParsedContent
from app.adapters.errors import (
    AuthRequiredAdapterError,
    NonRetryableAdapterError,
    RetryableAdapterError,
)
from app.models import BilibiliContentType
from .base import clean_text, safe_url, format_request_error
import re


# API端点
API_ARTICLE_INFO = "https://api.bilibili.com/x/article/viewinfo"


async def parse_article(
    url: str,
    headers: Dict[str, str],
    cookies: Dict[str, str]
) -> ParsedContent:
    """
    解析B站专栏文章
    
    Args:
        url: 文章URL（已净化）
        headers: HTTP请求头
        cookies: 登录Cookie
        
    Returns:
        ParsedContent: 解析后的标准化内容
        
    Raises:
        AuthRequiredAdapterError: 需要登录
        NonRetryableAdapterError: 资源不可用
        RetryableAdapterError: 网络错误或API错误
    """
    # 提取文章ID（cvid）
    cv_match = re.search(r'bilibili\.com/read/cv(\d+)', url)
    if not cv_match:
        raise NonRetryableAdapterError(f"无法从URL提取文章ID: {url}")
    
    cvid = cv_match.group(1)
    
    # 发起API请求
    async with httpx.AsyncClient(headers=headers, cookies=cookies, timeout=10.0) as client:
        try:
            response = await client.get(API_ARTICLE_INFO, params={'id': cvid})
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
        item = data['data']
        
        # 提取互动数据
        stats = {
            'view': item.get('stats', {}).get('view', 0),
            'like': item.get('stats', {}).get('like', 0),
            'favorite': item.get('stats', {}).get('favorite', 0),
            'coin': item.get('stats', {}).get('coin', 0),
            'reply': item.get('stats', {}).get('reply', 0),
            'share': item.get('stats', {}).get('share', 0),
        }

        # 构建存档结构
        image_urls = item.get('image_urls', [])
        archive = {
            "version": 2,
            "type": "bilibili_article",
            "title": item.get('title', ''),
            "plain_text": item.get('summary', ''),
            "markdown": item.get('summary', ''),  # 暂无全文Markdown，仅摘要
            "images": [{"url": u} for u in image_urls],
            "links": [],
            "stored_images": []
        }
        
        # 保留原始元数据并附加archive
        raw_metadata = dict(item)
        raw_metadata['archive'] = archive
        
        # 提取作者信息
        author_mid = item.get('mid')
        
        # 构建ParsedContent
        return ParsedContent(
            platform='bilibili',
            content_type=BilibiliContentType.ARTICLE.value,
            content_id=f"cv{cvid}",
            clean_url=url,
            title=item.get('title'),
            description=item.get('summary'),
            author_name=item.get('author_name'),
            author_id=str(author_mid) if author_mid else None,
            author_avatar_url=item.get('author_face'),
            author_url=f"https://space.bilibili.com/{author_mid}" if author_mid else None,
            cover_url=item.get('banner_url') or (image_urls[0] if image_urls else None),
            media_urls=image_urls,
            published_at=datetime.fromtimestamp(item.get('publish_time')) if item.get('publish_time') else None,
            raw_metadata=raw_metadata,
            stats=stats
        )
