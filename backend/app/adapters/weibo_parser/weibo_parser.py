"""
微博内容解析器

负责解析微博状态（推文）内容
"""
import requests
from datetime import datetime
from typing import Dict, Any, List
from app.core.logging import logger
from app.adapters.base import ParsedContent, LAYOUT_GALLERY
from app.adapters.errors import (
    AuthRequiredAdapterError,
    NonRetryableAdapterError,
    RetryableAdapterError,
)
from app.core.config import settings
from .base import clean_html_text, extract_weibo_images, extract_weibo_video


async def parse_weibo(
    bid: str,
    url: str,
    headers: Dict[str, str],
    cookies: Dict[str, str],
    proxies: Dict[str, str] = None
) -> ParsedContent:
    """
    解析微博状态
    
    Args:
        bid: 微博ID (mblogid)
        url: 原始URL
        headers: HTTP请求头
        cookies: Cookie字典
        proxies: 代理设置
        
    Returns:
        ParsedContent: 解析后的标准化内容
        
    Raises:
        AuthRequiredAdapterError: 需要登录
        NonRetryableAdapterError: 微博不存在或已删除
        RetryableAdapterError: 网络错误或API错误
    """
    api_url = f"https://weibo.com/ajax/statuses/show?id={bid}"
    
    try:
        response = requests.get(api_url, headers=headers, cookies=cookies, proxies=proxies, timeout=10)
        
        if response.status_code == 404:
            raise NonRetryableAdapterError(f"微博不存在: {bid}")
        
        if response.status_code != 200:
            raise RetryableAdapterError(f"获取微博API失败: {response.status_code}")
        
        data = response.json()
        
        # 检查认证失败
        if data.get("ok") != 1:
            # ok: -100通常意味着需要登录
            if data.get("ok") == -100:
                raise AuthRequiredAdapterError("微博需要登录（游客模式受限）", details=data)
            
            # 其他非ok状态
            if "text" not in data and "page_info" not in data:
                raise NonRetryableAdapterError(f"微博API返回错误状态: {data.get('ok')}", details=data)

        if "text" not in data and "page_info" not in data:
            raise NonRetryableAdapterError("无效的微博数据结构（可能被屏蔽或删除）")

        # 处理长文本
        if data.get("isLongText"):
            try:
                long_text_url = f"https://weibo.com/ajax/statuses/longtext?id={bid}"
                lt_resp = requests.get(long_text_url, headers=headers, cookies=cookies, timeout=10)
                if lt_resp.status_code == 200:
                    lt_data = lt_resp.json()
                    if lt_data.get("data", {}).get("longTextContent"):
                        data["text"] = lt_data["data"]["longTextContent"]
            except Exception as e:
                logger.warning(f"获取长文本失败 {bid}: {e}")

        # 构建标准化存档
        archive = build_weibo_archive(data)
        
        # 从存档中提取元数据
        title = archive.get("title", "微博分享")
        description = archive.get("plain_text", "")
        
        # 提取图片和视频
        media_urls = []
        cover_url = ""
        
        for img in archive.get("images", []):
            if img.get("url"):
                media_urls.append(img["url"])
        
        if archive.get("videos"):
            for vid in archive["videos"]:
                if vid.get("url"):
                    media_urls.append(vid["url"])
        
        # 封面选择逻辑：优先使用图片，其次使用视频封面
        if archive.get("images"):
            cover_url = archive["images"][0].get("url")
        elif archive.get("videos"):
            cover_url = archive["videos"][0].get("cover")
        
        # 如果仍未找到封面，使用page_info中的
        if not cover_url and "page_info" in data:
            page_pic = data["page_info"].get("page_pic", {}).get("url")
            if page_pic:
                cover_url = page_pic
                if page_pic not in media_urls:
                    media_urls.insert(0, page_pic)

        # 解析作者
        user = data.get("user", {})
        author_name = user.get("screen_name", "Unknown")
        author_id = str(user.get("id", ""))
        author_avatar_url = user.get("avatar_hd") or user.get("profile_image_url")
        author_url = f"https://weibo.com/u/{author_id}" if author_id else None
        
        # 统计
        reposts_count = data.get("reposts_count", 0)
        comments_count = data.get("comments_count", 0)
        attitudes_count = data.get("attitudes_count", 0)  # 点赞
        
        # 解析发布时间
        created_at_str = data.get("created_at")  # "Tue Jan 09 12:00:00 +0800 2024"
        published_at = None
        if created_at_str:
            try:
                published_at = datetime.strptime(created_at_str, "%a %b %d %H:%M:%S %z %Y")
            except ValueError:
                pass

        # 将archive放入raw_metadata
        raw_metadata = data
        raw_metadata["archive"] = archive

        return ParsedContent(
            platform="weibo",
            content_type="status",
            content_id=bid,
            clean_url=url,
            layout_type=LAYOUT_GALLERY,  # 微博默认为Gallery布局
            title=title[:100], 
            description=description,
            author_name=author_name,
            author_id=author_id,
            author_avatar_url=author_avatar_url,
            author_url=author_url,
            cover_url=cover_url,
            media_urls=media_urls,
            published_at=published_at,
            raw_metadata=raw_metadata,
            stats={
                "repost": reposts_count,
                "reply": comments_count,
                "like": attitudes_count,
                "share": reposts_count  # 映射share到repost供通用统计
            }
        )

    except requests.RequestException as e:
        raise RetryableAdapterError(f"网络错误: {str(e)}")
    except (AuthRequiredAdapterError, NonRetryableAdapterError, RetryableAdapterError):
        raise
    except Exception as e:
        logger.exception("解析微博内容时出错")
        raise NonRetryableAdapterError(f"意外错误: {str(e)}")


def build_weibo_archive(data: Dict[str, Any]) -> Dict[str, Any]:
    """
    构建标准化存档结构
    
    Args:
        data: 微博API返回的数据
        
    Returns:
        Dict: 存档数据结构
    """
    from app.adapters.utils import generate_title_from_text
    
    text_html = data.get("text", "")
    plain_text = clean_html_text(text_html)
    
    # 使用通用函数从正文生成标题
    title = generate_title_from_text(plain_text, max_len=60, fallback="微博内容")
    
    archive = {
        "version": 2,
        "type": "weibo_status",
        "title": title,
        "plain_text": plain_text,
        "markdown": plain_text,  # 暂且直接用纯文本作为markdown
        "images": [],
        "videos": [],
        "links": [],
        "stored_images": [],
        "stored_videos": []
    }
    
    # 提取图片
    images = extract_weibo_images(data)
    archive["images"] = images
    
    # 提取视频
    video = extract_weibo_video(data)
    if video:
        archive["videos"].append(video)
    
    # 添加头像（标记为type:avatar，用于媒体转码但不加入media_urls）
    user = data.get("user", {})
    author_avatar_url = user.get("avatar_hd") or user.get("profile_image_url")
    if author_avatar_url:
        archive["images"].append({"url": author_avatar_url, "type": "avatar"})
    
    return archive
