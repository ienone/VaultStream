"""
微博解析器公共工具模块

提供所有微博解析器共用的工具函数
"""
import re
from typing import Any, Dict, List, Optional
from app.logging import logger


def clean_html_text(html_text: str) -> str:
    """
    从HTML中提取纯文本
    
    Args:
        html_text: HTML格式的文本
        
    Returns:
        str: 清洗后的纯文本
    """
    if not html_text:
        return ""
    
    # 简单清洗HTML标签
    plain_text = re.sub(r'<[^>]+>', '', html_text).strip()
    return plain_text


def select_best_image_url(pic_info: Dict[str, Any]) -> Optional[str]:
    """
    从微博图片信息中选择最佳质量的图片URL
    
    微博图片通常有多个尺寸：largest、large、mw2048等
    
    Args:
        pic_info: 图片信息字典
        
    Returns:
        Optional[str]: 最佳质量的图片URL
    """
    if not pic_info:
        return None
    
    # 按优先级尝试各种尺寸
    for size_key in ["largest", "mw2048", "large", "bmiddle", "thumbnail"]:
        size_info = pic_info.get(size_key, {})
        if isinstance(size_info, dict):
            url = size_info.get("url")
            if url:
                return url
    
    return None


def extract_weibo_images(data: Dict[str, Any]) -> List[Dict[str, Any]]:
    """
    从微博数据中提取所有图片
    
    Args:
        data: 微博API返回的数据
        
    Returns:
        List[Dict]: 图片列表，每个包含url、width、height
    """
    images = []
    
    pic_infos = data.get("pic_infos", {})
    sorted_keys = data.get("pic_ids", [])
    
    # 如果pic_ids存在，按顺序提取；否则遍历字典
    keys_to_iter = sorted_keys if sorted_keys else pic_infos.keys()
    
    for pid in keys_to_iter:
        info = pic_infos.get(pid)
        url = None
        width = None
        height = None
        
        if info:
            url = select_best_image_url(info)
            width = info.get("largest", {}).get("width")
            height = info.get("largest", {}).get("height")
        else:
            # Fallback: 从pid构建URL
            if pid:
                url = f"https://wx1.sinaimg.cn/large/{pid}.jpg"
        
        if url:
            images.append({
                "url": url,
                "width": width,
                "height": height
            })
    
    return images


def extract_weibo_video(data: Dict[str, Any]) -> Optional[Dict[str, Any]]:
    """
    从微博数据中提取视频信息
    
    Args:
        data: 微博API返回的数据
        
    Returns:
        Optional[Dict]: 视频信息，包含url和cover
    """
    video_url = None
    cover_url = None
    
    # 1. 检查page_info
    if "page_info" in data and data["page_info"].get("type") == "video":
        page_info = data["page_info"]
        media_info = page_info.get("media_info", {})
        
        # 优先选择高清视频
        video_url = (
            media_info.get("mp4_720p_mp4") or 
            media_info.get("mp4_hd_url") or 
            media_info.get("stream_url_hd") or 
            media_info.get("stream_url")
        )
        cover_url = page_info.get("page_pic", {}).get("url")

    # 2. 检查mix_media_info（较新的结构）
    if not video_url and "mix_media_info" in data:
        items = data["mix_media_info"].get("items", [])
        for item in items:
            if item.get("type") == "video":
                media_info = item.get("data", {}).get("media_info", {})
                video_url = (
                    media_info.get("mp4_720p_mp4") or 
                    media_info.get("stream_url_hd") or 
                    media_info.get("stream_url")
                )
                break

    if video_url:
        return {
            "url": video_url,
            "cover": cover_url
        }
    
    return None
