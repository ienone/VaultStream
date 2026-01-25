"""
微博用户信息解析器

负责解析微博用户主页和个人信息
"""
import requests
from datetime import datetime
from typing import Dict, Any
from app.core.logging import logger
from app.adapters.base import ParsedContent
from app.adapters.errors import RetryableAdapterError
from app.core.config import settings


def fetch_user_profile(uid: str, headers: Dict[str, str], cookies: Dict[str, str], proxies: Dict[str, str] = None) -> Dict[str, Any]:
    """
    获取用户详细信息
    
    移植自WeiboSpider项目
    
    Args:
        uid: 用户ID
        headers: HTTP请求头
        cookies: Cookie字典
        proxies: 代理设置
        
    Returns:
        Dict: 用户信息字典
        
    Raises:
        RetryableAdapterError: 获取失败
    """
    # 1. 获取基本信息
    info_url = f"https://weibo.com/ajax/profile/info?uid={uid}"
    try:
        resp_info = requests.get(info_url, headers=headers, cookies=cookies, proxies=proxies, timeout=10)
        resp_info.raise_for_status()
        info_data = resp_info.json()
        user_base = parse_user_info(info_data.get('data', {}).get('user', {}))
    except Exception as e:
        logger.error(f"获取用户信息失败 {uid}: {e}")
        raise RetryableAdapterError(f"获取用户信息失败: {e}")

    # 2. 获取详细信息
    detail_url = f"https://weibo.com/ajax/profile/detail?uid={uid}"
    try:
        resp_detail = requests.get(detail_url, headers=headers, cookies=cookies, proxies=proxies, timeout=10)
        resp_detail.raise_for_status()
        detail_data = resp_detail.json()
        user_detail = parse_user_detail(user_base, detail_data.get('data', {}))
    except Exception as e:
        logger.warning(f"获取用户详细信息失败 {uid}: {e}")
        user_detail = user_base  # 回退到基本信息

    return user_detail


def parse_user_info(data: Dict[str, Any]) -> Dict[str, Any]:
    """
    解析用户基本信息
    
    参考WeiboSpider/weibospider/spiders/common.py
    
    Args:
        data: 用户信息数据
        
    Returns:
        Dict: 解析后的用户信息
    """
    user = {
        "platform_id": str(data.get('id', '')),
        "nick_name": data.get('screen_name', ''),
        "avatar_hd": data.get('avatar_hd', ''),
        "verified": data.get('verified', False),
        "description": data.get('description', ''),
        "followers_count": data.get('followers_count', 0),
        "friends_count": data.get('friends_count', 0),
        "statuses_count": data.get('statuses_count', 0),
        "gender": data.get('gender', 'n'),
        "location": data.get('location', ''),
        "mbrank": data.get('mbrank', 0),
        "mbtype": data.get('mbtype', 0),
        "credit_score": data.get('credit_score', 0),
    }
    
    if user['verified']:
        user['verified_type'] = data.get('verified_type', 0)
        user['verified_reason'] = data.get('verified_reason', '')
    
    return user


def parse_user_detail(item: Dict[str, Any], data: Dict[str, Any]) -> Dict[str, Any]:
    """
    解析用户详细信息
    
    参考WeiboSpider/weibospider/spiders/user.py
    
    Args:
        item: 基本用户信息
        data: 详细信息数据
        
    Returns:
        Dict: 合并后的完整用户信息
    """
    item['birthday'] = data.get('birthday', '')
    item['created_at_str'] = data.get('created_at', '')  # "2010-05-31 23:07:59"
    item['desc_text'] = data.get('desc_text', '')
    item['ip_location'] = data.get('ip_location', '')
    item['sunshine_credit'] = data.get('sunshine_credit', {}).get('level', '')
    
    if 'company' in data:
        item['company'] = data['company']
    if 'education' in data:
        item['education'] = data['education']
    
    # 合并原始数据供存档
    item['raw_data'] = {
        'detail': data
    }
    
    return item


async def parse_user(uid: str, url: str, headers: Dict[str, str], cookies: Dict[str, str], proxies: Dict[str, str] = None) -> ParsedContent:
    """
    解析微博用户主页
    
    Args:
        uid: 用户ID
        url: 用户主页URL
        headers: HTTP请求头
        cookies: Cookie字典
        proxies: 代理设置
        
    Returns:
        ParsedContent: 解析后的标准化内容
    """
    user_info = fetch_user_profile(uid, headers, cookies, proxies)
    
    # 构建存档（用于颜色提取和媒体处理）
    archive = {
        "type": "weibo_user",
        "version": 2,
        "title": user_info.get('nick_name', ''),
        "plain_text": user_info.get('description', ''),
        "images": [],
        "videos": []
    }
    
    if user_info.get('avatar_hd'):
        archive["images"].append({
            "url": user_info.get('avatar_hd'),
            "width": None, 
            "height": None
        })
    
    return ParsedContent(
        platform="weibo",
        content_type="user_profile",
        content_id=f"u_{uid}",
        clean_url=url,
        title=f"微博博主: {user_info.get('nick_name', uid)}",
        description=user_info.get('description', ''),
        author_name=user_info.get('nick_name', ''),
        author_id=uid,
        cover_url=user_info.get('avatar_hd', ''),
        media_urls=[user_info.get('avatar_hd', '')] if user_info.get('avatar_hd') else [],
        published_at=datetime.now(), 
        raw_metadata={
            **user_info,
            "archive": archive  # worker需要此字段进行颜色提取
        },
        stats={
            # 映射用户指标到标准统计键供前端显示
            # followers -> view (粉丝)
            # friends/following -> share (关注)
            # statuses -> reply (博文)
            "view": user_info.get('followers_count', 0),
            "share": user_info.get('friends_count', 0),
            "reply": user_info.get('statuses_count', 0),
            "like": 0,
            "favorite": 0
        }
    )
