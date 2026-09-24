"""
小红书用户信息解析器

负责解析小红书用户主页
"""
from typing import Dict, Any, Optional
from app.adapters.base import ParsedContent, LAYOUT_GALLERY
from app.adapters.errors import (
    AuthRequiredAdapterError,
    NonRetryableAdapterError,
    RetryableAdapterError,
)
import httpx
from urllib.parse import quote
from .base import clean_text
from .ssr import extract_initial_state, navigation_headers


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


def extract_ssr_user(html: str, user_id: str) -> dict:
    state = extract_initial_state(html).get("user")
    if not isinstance(state, dict) or not isinstance(state.get("userPageData"), dict):
        raise NonRetryableAdapterError("小红书页面未提供目标用户资料")
    user = state["userPageData"]
    result = user.get("result")
    basic_info = user.get("basicInfo")
    if (not isinstance(result, dict) or not isinstance(basic_info, dict)
            or state.get("userFetchingStatus") != "resolved"
            or result.get("success") is not True or result.get("code") != 0
            or not basic_info.get("nickname")):
        raise NonRetryableAdapterError("小红书页面未提供目标用户资料")
    queries = state.get("noteQueries")
    if (not isinstance(queries, list) or not queries
            or any(not isinstance(query, dict) or query.get("userId") != user_id
                   for query in queries)):
        raise NonRetryableAdapterError("小红书 SSR 主页身份不匹配")
    return user


async def fetch_user_via_api(user_id, xhs_client, cookies, headers, xsec_token=None, session=None):
    """Saved-account access remains separate from anonymous public SSR."""
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
        params=params,
        session=session,
    )
    
    request_headers = {**headers, **sign_headers}
    api_url = f"{API_BASE}{API_USER_INFO}"
    
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
                
                if code == -100:
                    raise AuthRequiredAdapterError(f"小红书session过期: {msg}", details={"code": code, "reason": "session_expired"})
                if code == 300012:
                    raise AuthRequiredAdapterError(f"小红书IP被封: {msg}", details={"code": code, "reason": "ip_blocked"})
                if code == -1:
                    raise AuthRequiredAdapterError(f"小红书认证失败: {msg}", details={"code": code, "reason": "auth_failed"})
                if code in (-2, 9999):
                    raise RetryableAdapterError(f"小红书服务暂时不可用: {msg}", details={"code": code})
                
                raise NonRetryableAdapterError(f"小红书API错误: {msg}", details={"code": code})
            
            user = data.get("data", {})
            
        except httpx.RequestError as e:
            raise RetryableAdapterError(f"小红书请求失败: {e}")
    
    return user


async def parse_user(
    user_id: str,
    url: str,
    xhs_client,
    cookies: Dict[str, str],
    headers: Dict[str, str],
    xsec_token: Optional[str] = None,
    session=None,
) -> ParsedContent:
    """Public profiles expose their structured data in SSR, without a login."""
    if cookies:
        user = await fetch_user_via_api(user_id, xhs_client, cookies, headers, xsec_token, session)
    else:
        request_url = f"https://www.xiaohongshu.com/user/profile/{user_id}"
        if xsec_token:
            request_url += f"?xsec_token={quote(xsec_token, safe='')}"
        try:
            async with httpx.AsyncClient(timeout=15, follow_redirects=True) as client:
                response = await client.get(request_url, headers=navigation_headers(headers))
            if response.status_code in (404, 410) or '/404' in str(response.url):
                raise NonRetryableAdapterError("小红书用户主页不可访问")
            if response.status_code != 200:
                raise RetryableAdapterError(f"小红书主页请求失败: HTTP {response.status_code}")
            user = extract_ssr_user(response.text, user_id)
        except httpx.RequestError as error:
            raise RetryableAdapterError(f"小红书主页请求失败: {error}") from error

    # Account API and SSR normalize into the existing profile contract.
    basic_info = user.get("basicInfo") or user.get("basic_info") or {}
    nickname = clean_text(basic_info.get("nickname"))
    desc = clean_text(basic_info.get("desc"))
    avatar = safe_url(basic_info.get("imageb") or basic_info.get("images") or basic_info.get("image"))
    # CLI有返回这三个字段，后端之前未提取
    red_id = basic_info.get("redId") or basic_info.get("red_id", "")
    ip_location = basic_info.get("ipLocation") or basic_info.get("ip_location", "")
    gender = basic_info.get("gender")
    
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
    
    # 将ip_location加入stats（对内容发现有意义）
    if ip_location:
        stats["ip_location"] = ip_location
    
    # 构建存档
    archive = {
        "version": 2,
        "type": "xiaohongshu_user",
        "title": nickname,
        "plain_text": desc,
        "images": [],
        "links": [],
        # CLI有提取的额外字段
        "red_id": red_id,
        "ip_location": ip_location,
        "gender": gender,
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
        body=desc,
        author_name=nickname,
        author_id=user_id,
        author_url=url,
        author_avatar_url=avatar,
        cover_url=avatar,
        media_urls=[avatar] if avatar else [],
        published_at=None,
        archive_metadata=archive_metadata,
        stats=stats,
    )
