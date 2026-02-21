"""
B站直播间解析器

负责解析B站直播间信息
"""
import httpx
from typing import Dict, Any
from app.core.logging import logger
from app.adapters.base import ParsedContent, LAYOUT_GALLERY
from app.adapters.errors import (
    AuthRequiredAdapterError,
    NonRetryableAdapterError,
    RetryableAdapterError,
)
from app.models import BilibiliContentType
from .base import format_request_error
import re


# API端点
API_LIVE_INFO = "https://api.live.bilibili.com/xlive/web-room/v1/index/getRoomBaseInfo"


async def parse_live(
    url: str,
    headers: Dict[str, str],
    cookies: Dict[str, str]
) -> ParsedContent:
    """
    解析B站直播间
    
    Args:
        url: 直播间URL（已净化）
        headers: HTTP请求头
        cookies: 登录Cookie
        
    Returns:
        ParsedContent: 解析后的标准化内容
        
    Raises:
        AuthRequiredAdapterError: 需要登录
        NonRetryableAdapterError: 资源不可用
        RetryableAdapterError: 网络错误或API错误
    """
    # 提取直播间ID
    match = re.search(r'live\.bilibili\.com/(\d+)', url)
    if not match:
        raise NonRetryableAdapterError(f"无法从URL提取直播间ID: {url}")
    
    room_id = match.group(1)
    
    # 发起API请求
    # 使用 getRoomBaseInfo 接口，该接口支持短号且返回数据较全
    async with httpx.AsyncClient(headers=headers, cookies=cookies, timeout=10.0) as client:
        params = {
            'req_biz': 'web_room_componet',
            'room_ids': room_id
        }
        
        try:
            response = await client.get(API_LIVE_INFO, params=params)
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
        
        # 该接口返回的是字典，key是长号ID
        by_room_ids = data.get('data', {}).get('by_room_ids', {})
        if not by_room_ids:
            raise NonRetryableAdapterError("未找到直播间信息")
        
        # 获取第一个（也是唯一一个）直播间信息
        room_info = next(iter(by_room_ids.values()))
        
        # 直播间统计数据
        stats = {
            'view': room_info.get('online', 0),  # 人气值
            'live_status': room_info.get('live_status', 0),  # 0:未开播, 1:直播中, 2:轮播中
        }
        
        # 提取主播信息
        author_uid = room_info.get('uid')
        
        # 构建ParsedContent
        # 直播间封面展示，layout_type设为GALLERY
        return ParsedContent(
            platform='bilibili',
            content_type=BilibiliContentType.LIVE.value,
            content_id=str(room_info.get('room_id')),
            clean_url=url,
            layout_type=LAYOUT_GALLERY,
            title=room_info.get('title'),
            description=room_info.get('description'),
            author_name=room_info.get('uname'),
            author_id=str(author_uid) if author_uid else None,
            author_avatar_url=room_info.get('face'),
            author_url=f"https://space.bilibili.com/{author_uid}" if author_uid else None,
            cover_url=room_info.get('cover'),
            media_urls=[room_info.get('cover')] if room_info.get('cover') else [],
            published_at=None,
            archive_metadata={"raw_api_response": dict(room_info)},
            stats=stats
        )
