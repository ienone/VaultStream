"""
B站视频解析器

负责解析B站视频内容，提取标题、描述、封面、UP主信息等
"""
import re
import httpx
from datetime import datetime
from typing import Optional, Dict, Any
from app.core.logging import logger
from app.adapters.base import ParsedContent, LAYOUT_GALLERY
from app.adapters.errors import (
    AuthRequiredAdapterError,
    NonRetryableAdapterError,
    RetryableAdapterError,
)
from app.models import BilibiliContentType
from .base import clean_text, safe_url, prune_metadata, format_request_error


# API端点
API_VIDEO_INFO = "https://api.bilibili.com/x/web-interface/view"


async def parse_video(
    url: str,
    headers: Dict[str, str],
    cookies: Dict[str, str]
) -> ParsedContent:
    """
    解析B站视频
    
    Args:
        url: 视频URL（已净化）
        headers: HTTP请求头
        cookies: 登录Cookie
        
    Returns:
        ParsedContent: 解析后的标准化内容
        
    Raises:
        AuthRequiredAdapterError: 需要登录
        NonRetryableAdapterError: 资源不可用
        RetryableAdapterError: 网络错误或API错误
    """
    # 提取视频ID（bvid或aid）
    bv_match = re.search(r'video/(BV[0-9A-Za-z]{10})', url)
    av_match = re.search(r'video/av(\d+)', url)
    
    bvid = bv_match.group(1) if bv_match else None
    aid = av_match.group(1) if av_match else None
    
    if not bvid and not aid:
        raise NonRetryableAdapterError(f"无法从URL提取视频ID: {url}")
        
    # 准备API请求参数
    params = {'bvid': bvid} if bvid else {'aid': aid}
    
    # 发起requests
    async with httpx.AsyncClient(headers=headers, cookies=cookies, timeout=10.0) as client:
        try:
            response = await client.get(API_VIDEO_INFO, params=params)
            data = response.json()
        except httpx.RequestError as e:
            raise RetryableAdapterError(f"B站请求失败: {format_request_error(e)}")
        
        # 检查API响应状态
        if data.get('code') != 0:
            code = data.get('code')
            msg = data.get('message')
            
            # 权限不足（需要登录）
            if code in (-403, 62002, 62012):
                raise AuthRequiredAdapterError(f"B站权限不足: {msg}", details={"code": code})
            
            # 资源不可用（视频已删除、不存在等）
            if code in (-400, -404, 62004):
                raise NonRetryableAdapterError(f"B站资源不可用: {msg}", details={"code": code})
            
            # 其他错误
            raise RetryableAdapterError(f"B站API错误: {msg}", details={"code": code})
        
        # 提取数据
        item = data['data']
        
        # 提取互动数据
        stat = item.get('stat', {})
        stats = {
            'view': stat.get('view', 0),
            'like': stat.get('like', 0),
            'favorite': stat.get('favorite', 0),
            'coin': stat.get('coin', 0),
            'share': stat.get('share', 0),
            'reply': stat.get('reply', 0),
            'danmaku': stat.get('danmaku', 0)
        }

        # 提取UP主信息
        owner = item.get('owner', {})
        author_mid = owner.get('mid')
        author_avatar_url = owner.get('face')

        # 构建存档结构（用于媒体存档）
        archive = {
            "version": 2,
            "type": "bilibili_video",
            "title": item.get('title', ''),
            "plain_text": item.get('desc', ''),
            "markdown": item.get('desc', ''),
            "images": [{"url": item.get('pic')}] if item.get('pic') else [],
            "videos": [],  # TODO: 支持视频下载
            "links": [],
            "stored_images": [],
            "stored_videos": []
        }
        
        # 添加头像（标记为type:avatar，避免被添加到media_urls）
        if author_avatar_url:
            archive["images"].append({"url": author_avatar_url, "type": "avatar"})
        
        # 保留原始元数据并附加archive
        
        # 构建ParsedContent
        # 视频当前只存封面不存视频，layout_type设为GALLERY
        return ParsedContent(
            platform='bilibili',
            content_type=BilibiliContentType.VIDEO.value,
            content_id=bvid or f"av{aid}",
            clean_url=url,
            layout_type=LAYOUT_GALLERY,
            title=item.get('title'),
            description=item.get('desc'),
            author_name=owner.get('name'),
            author_id=str(author_mid) if author_mid else None,
            author_avatar_url=owner.get('face'),
            author_url=f"https://space.bilibili.com/{author_mid}" if author_mid else None,
            cover_url=item.get('pic'),
            media_urls=[item.get('pic')] if item.get('pic') else [],
            published_at=datetime.fromtimestamp(item.get('pubdate')) if item.get('pubdate') else None,
            archive_metadata=archive_metadata,
            stats=stats
        )
