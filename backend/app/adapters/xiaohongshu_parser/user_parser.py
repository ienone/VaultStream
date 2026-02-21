"""
小红书用户信息解析器

负责解析小红书用户主页，从原xiaohongshu.py迁移而来
"""
from datetime import datetime
from typing import Dict, Any, Optional
from app.core.logging import logger
from app.adapters.base import ParsedContent, LAYOUT_GALLERY
from app.adapters.errors import (
    AuthRequiredAdapterError,
    NonRetryableAdapterError,
    RetryableAdapterError,
)
from .base import clean_text


def safe_url(url: Any) -> Optional[str]:
    """安全获取URL"""
    if not url or not isinstance(url, str):
        return None
    u = url.strip()
    if u.startswith("//"):
        return "https:" + u
    return u if u else None


def parse_count(count: Any) -> int:
    """
    解析计数（可能是字符串如"1.2万"、"10+"、"1万+"）
    
    Args:
        count: 计数值（可能是int、float或字符串）
        
    Returns:
        int: 解析后的整数值
    """
    if count is None:
        return 0
    if isinstance(count, int):
        return count
    if isinstance(count, float):
        return int(count)
    
    count_str = str(count).strip()
    if not count_str:
        return 0
    
    # 移除+号（如"10+"、"1万+"）
    count_str = count_str.replace('+', '').strip()
    
    try:
        # 处理中文数字后缀
        if '万' in count_str:
            num_part = count_str.replace('万', '').strip()
            return int(float(num_part) * 10000) if num_part else 10000
        if '亿' in count_str:
            num_part = count_str.replace('亿', '').strip()
            return int(float(num_part) * 100000000) if num_part else 100000000
        if 'k' in count_str.lower():
            num_part = count_str.lower().replace('k', '').strip()
            return int(float(num_part) * 1000) if num_part else 1000
        if 'm' in count_str.lower():
            num_part = count_str.lower().replace('m', '').strip()
            return int(float(num_part) * 1000000) if num_part else 1000000
        return int(float(count_str))
    except (ValueError, TypeError):
        return 0


async def parse_user(
    user_id: str,
    url: str,
    xhs_client,
    cookies: Dict[str, str],
    headers: Dict[str, str],
    xsec_token: Optional[str] = None
) -> ParsedContent:
    """
    解析小红书用户主页
    
    Args:
        user_id: 用户ID
        url: 用户主页URL
        xhs_client: Xhshow客户端用于签名
        cookies: Cookie字典
        headers: 请求头
        xsec_token: 安全token（可选）
        
    Returns:
        ParsedContent: 解析后的标准化内容
        
    Raises:
        AuthRequiredAdapterError: 需要登录
        NonRetryableAdapterError: 用户不存在
        RetryableAdapterError: 网络错误或API错误
    """
    logger.info(f"解析小红书用户: user_id={user_id}")
    
    # 准备API请求
    API_USER_INFO = "/api/sns/web/v1/user/otherinfo"
    API_BASE = "https://edith.xiaohongshu.com"
    
    params = {"target_user_id": user_id}
    if xsec_token:
        params["xsec_token"] = xsec_token
    
    # 发起带签名的请求
    if not cookies:
        raise AuthRequiredAdapterError("需要配置小红书Cookie")
    
    # 生成签名
    sign_headers = xhs_client.sign_headers_get(
        uri=API_USER_INFO,
        cookies=cookies,
        params=params
    )
    
    request_headers = {**headers, **sign_headers}
    api_url = f"{API_BASE}{API_USER_INFO}"
    
    import httpx
    async with httpx.AsyncClient(timeout=15.0) as client:
        try:
            response = await client.get(
                api_url,
                params=params,
                headers=request_headers,
                cookies=cookies
            )
            
            data = response.json()
            
            # 检查响应状态
            if data.get('code') != 0 and data.get('success') is not True:
                code = data.get('code')
                msg = data.get('msg') or data.get('message') or '未知错误'
                
                if code in (-1, -100, 300012):
                    raise AuthRequiredAdapterError(f"小红书认证失败: {msg}", details={"code": code})
                if code in (-2, 9999):
                    raise RetryableAdapterError(f"小红书服务暂时不可用: {msg}", details={"code": code})
                
                raise NonRetryableAdapterError(f"小红书API错误: {msg}", details={"code": code})
            
            user = data.get("data", {})
            
        except httpx.RequestError as e:
            raise RetryableAdapterError(f"小红书请求失败: {e}")
    
    # API返回camelCase，需要兼容两种格式
    basic_info = user.get("basicInfo") or user.get("basic_info") or {}
    nickname = clean_text(basic_info.get("nickname"))
    desc = clean_text(basic_info.get("desc"))
    avatar = safe_url(basic_info.get("imageb") or basic_info.get("images") or basic_info.get("image"))
    
    # 互动数据
    interactions = user.get("interactions") or []
    stats = {}
    for item in interactions:
        if isinstance(item, dict):
            item_type = (item.get("type") or "").lower()
            name = item.get("name", "")
            count = parse_count(item.get("count"))
            
            if item_type == "follows" or "关注" in name:
                stats["following"] = count
            elif item_type == "fans" or "粉丝" in name:
                stats["followers"] = count
            elif item_type == "interaction" or "获赞" in name or "收藏" in name:
                stats["liked"] = count
    
    # 构建存档
    archive = {
        "version": 2,
        "type": "xiaohongshu_user",
        "title": nickname,
        "plain_text": desc,
        "images": [],
        "links": [],
        "stored_images": []
    }
    
    if avatar:
        archive["images"].append({"url": avatar, "type": "avatar"})
    
    archive_metadata = dict(user) if isinstance(user, dict) else {"user": user}
    archive_metadata["archive"] = archive
    
    return ParsedContent(
        platform='xiaohongshu',
        content_type='user_profile',
        content_id=user_id,
        clean_url=url,
        layout_type=LAYOUT_GALLERY,  # 用户主页为Gallery布局
        title=nickname or "小红书用户",
        description=desc,
        author_name=nickname,
        author_id=user_id,
        author_avatar_url=avatar,
        cover_url=avatar,
        media_urls=[avatar] if avatar else [],
        published_at=None,
        archive_metadata=archive_metadata,
        stats=stats,
    )
