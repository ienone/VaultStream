"""
小红书笔记解析器

负责解析小红书笔记内容（图文/视频），从原xiaohongshu.py迁移而来
包含API和SSR两种获取方式
"""
import re
import json
import httpx
from datetime import datetime
from typing import Dict, Any, List, Optional
from app.core.logging import logger
from app.adapters.base import ParsedContent
from app.adapters.errors import (
    AuthRequiredAdapterError,
    NonRetryableAdapterError,
    RetryableAdapterError,
)
from app.adapters.utils import ensure_title
from .base import clean_text, extract_source_tags, strip_tags_from_text


async def parse_note(
    note_id: str,
    url: str,
    xhs_client,
    cookies: Dict[str, str],
    headers: Dict[str, str],
    xsec_token: Optional[str] = None,
    xsec_source: str = "pc_feed"
) -> ParsedContent:
    """
    解析小红书笔记
    
    优先使用API方式，失败时回退到SSR解析
    
    Args:
        note_id: 笔记ID
        url: 笔记URL
        xhs_client: Xhshow客户端用于签名
        cookies: Cookie字典
        headers: 请求头
        xsec_token: 安全token（可选）
        xsec_source: 来源标识
        
    Returns:
        ParsedContent: 解析后的标准化内容
    """
    logger.info(f"解析小红book笔记: note_id={note_id}, xsec_source={xsec_source}")
    
    # 获取笔记数据
    note = await fetch_note(note_id, xhs_client, cookies, headers, xsec_token, xsec_source)
    
    # 构建存档
    archive = build_note_archive(note)
    
    # 提取作者信息
    user = note.get("user") or {}
    author_id = user.get("user_id") or user.get("userid")
    author_name = clean_text(user.get("nickname") or user.get("nick_name"))
    author_avatar = safe_url(user.get("avatar") or user.get("images"))
    
    # 构建作者主页链接
    author_url = None
    if author_id:
        user_xsec_token = user.get("xsec_token")
        author_url = f"https://www.xiaohongshu.com/user/profile/{author_id}"
        if user_xsec_token:
            author_url += f"?xsec_token={user_xsec_token}"
    
    # 提取平台原生标签
    source_tags = extract_source_tags(note)
    
    # 提取封面（优先使用第一张图片，否则使用视频首帧）
    cover_url = None
    if archive.get("images"):
        cover_url = archive["images"][0].get("url")
    elif archive.get("videos"):
        cover_url = archive["videos"][0].get("cover")
    
    # 提取媒体URL列表
    media_urls = []
    for img in archive.get("images", []):
        if img.get("url"):
            media_urls.append(img["url"])
    for vid in archive.get("videos", []):
        if vid.get("url"):
            media_urls.append(vid["url"])
    
    # 提取互动数据
    interact = note.get("interact_info") or note.get("interactInfo") or {}
    stats = {
        "like": interact.get("liked_count") or interact.get("likedCount") or 0,
        "favorite": interact.get("collected_count") or interact.get("collectedCount") or 0,
        "reply": interact.get("comment_count") or interact.get("commentCount") or 0,
        "share": interact.get("share_count") or interact.get("shareCount") or 0,
    }
    
    # 解析发布时间
    published_at = None
    timestamp = note.get("time") or note.get("create_time") or note.get("createTime")
    if timestamp:
        try:
            published_at = datetime.fromtimestamp(int(timestamp) / 1000)
        except (ValueError, TypeError):
            pass
    
    # 将archive放入raw_metadata
    raw_metadata = dict(note)
    raw_metadata["archive"] = archive
    raw_metadata["source_tags"] = source_tags
    
    raw_title = archive.get("title")
    description = archive.get("plain_text", "")
    # 使用通用函数确保标题：优先原生标题，否则从正文生成
    title = ensure_title(raw_title, description, max_len=60, fallback="小红书笔记")
    
    return ParsedContent(
        platform="xiaohongshu",
        content_type="note",
        content_id=note_id,
        clean_url=url,
        title=title,
        description=description,
        author_name=author_name or "未知用户",
        author_id=str(author_id) if author_id else None,
        author_avatar_url=author_avatar,
        author_url=author_url,
        cover_url=cover_url,
        media_urls=media_urls,
        published_at=published_at,
        raw_metadata=raw_metadata,
        stats=stats
    )


async def fetch_note(
    note_id: str,
    xhs_client,
    cookies: Dict[str, str],
    headers: Dict[str, str],
    xsec_token: Optional[str] = None,
    xsec_source: str = "pc_feed"
) -> Dict[str, Any]:
    """
    获取笔记详情，优先使用API，失败时回退到SSR解析
    """
    # 先尝试API方式
    try:
        result = await fetch_note_via_api(note_id, xhs_client, cookies, headers, xsec_token, xsec_source)
        logger.info(f"小红书笔记获取成功 [方式=API]: note_id={note_id}")
        return result
    except (NonRetryableAdapterError, RetryableAdapterError) as e:
        if not xsec_token:
            raise
        logger.warning(f"API获取失败，回退到SSR解析: {e}")
    
    # 回退到SSR方式
    result = await fetch_note_via_ssr(note_id, cookies, headers, xsec_token, xsec_source)
    logger.info(f"小红书笔记获取成功 [方式=SSR]: note_id={note_id}")
    return result


async def fetch_note_via_api(
    note_id: str,
    xhs_client,
    cookies: Dict[str, str],
    headers: Dict[str, str],
    xsec_token: Optional[str] = None,
    xsec_source: str = "pc_feed"
) -> Dict[str, Any]:
    """通过API获取笔记详情"""
    if not cookies:
        raise AuthRequiredAdapterError("需要配置小红书Cookie")
    
    API_NOTE_FEED = "/api/sns/web/v1/feed"
    API_BASE = "https://edith.xiaohongshu.com"
    
    payload = {
        "source_note_id": note_id,
        "image_formats": ["jpg", "webp", "avif"],
        "extra": {"need_body_topic": "1"},
        "xsec_source": xsec_source,
    }
    
    if xsec_token:
        payload["xsec_token"] = xsec_token
    
    # 生成签名
    sign_headers = xhs_client.sign_headers_post(
        uri=API_NOTE_FEED,
        cookies=cookies,
        payload=payload
    )
    
    request_headers = {**headers, **sign_headers}
    url = f"{API_BASE}{API_NOTE_FEED}"
    
    async with httpx.AsyncClient(timeout=15.0) as client:
        try:
            response = await client.post(
                url,
                json=payload,
                headers=request_headers,
                cookies=cookies
            )
            
            data = response.json()
            
            if data.get('code') != 0 and data.get('success') is not True:
                code = data.get('code')
                msg = data.get('msg') or data.get('message') or '未知错误'
                
                if code in (-1, -100, 300012):
                    raise AuthRequiredAdapterError(f"小红书认证失败: {msg}", details={"code": code})
                
                raise NonRetryableAdapterError(f"小红书API错误: {msg}", details={"code": code})
            
            items = data.get('data', {}).get('items', [])
            if not items:
                if xsec_token:
                    raise NonRetryableAdapterError(f"API返回空数据: {note_id}，可能被风控拦截")
                else:
                    raise NonRetryableAdapterError(f"找不到笔记: {note_id}，缺少xsec_token")
            
            return items[0].get('note_card', items[0])
            
        except httpx.RequestError as e:
            raise RetryableAdapterError(f"小红书请求失败: {e}")


async def fetch_note_via_ssr(
    note_id: str,
    cookies: Dict[str, str],
    headers: Dict[str, str],
    xsec_token: Optional[str] = None,
    xsec_source: str = "pc_feed"
) -> Dict[str, Any]:
    """通过网页SSR数据获取笔记详情（备选方案）"""
    # 构建带token的URL
    url = f"https://www.xiaohongshu.com/explore/{note_id}"
    if xsec_token:
        from urllib.parse import quote
        url += f"?xsec_token={quote(xsec_token, safe='')}&xsec_source={xsec_source}"
    
    async with httpx.AsyncClient(follow_redirects=True, timeout=15.0) as client:
        try:
            response = await client.get(
                url,
                headers={
                    'User-Agent': headers.get('User-Agent'),
                    'Accept': 'text/html,application/xhtml+xml,application/xml',
                },
                cookies=cookies
            )
            
            if response.status_code != 200:
                raise RetryableAdapterError(f"SSR请求失败: HTTP {response.status_code}")
            
            html = response.text
            
            # 检查是否被重定向
            if 'captcha' in str(response.url) or '/404' in str(response.url):
                raise NonRetryableAdapterError(f"访问被拦截: {response.url}")
            
            # 提取__INITIAL_STATE__
            match = re.search(r'window\.__INITIAL_STATE__\s*=\s*(.+?)</script>', html, re.DOTALL)
            if not match:
                raise NonRetryableAdapterError("无法从页面提取数据")
            
            raw = match.group(1).strip()
            if raw.endswith(';'):
                raw = raw[:-1]
            raw = raw.replace('undefined', 'null')
            
            try:
                data = json.loads(raw)
            except json.JSONDecodeError as e:
                raise NonRetryableAdapterError(f"SSR数据解析失败: {e}")
            
            # 提取笔记数据
            note_detail = data.get('note', {}).get('noteDetailMap', {})
            if not note_detail:
                note_detail = data.get('noteDetail', {}).get('data', {})
            
            if not note_detail:
                raise NonRetryableAdapterError("SSR数据中找不到笔记")
            
            # 获取目标笔记
            note_data = note_detail.get(note_id)
            if not note_data:
                first_key = next(iter(note_detail.keys()), None)
                if first_key:
                    note_data = note_detail[first_key]
            
            if not note_data:
                raise NonRetryableAdapterError(f"SSR数据中找不到笔记: {note_id}")
            
            note = note_data.get('note', note_data)
            
            # 转换为与API兼容的格式
            return normalize_ssr_note(note)
            
        except httpx.RequestError as e:
            raise RetryableAdapterError(f"SSR请求失败: {e}")


def normalize_ssr_note(note: Dict[str, Any]) -> Dict[str, Any]:
    """将SSR格式的笔记数据转换为API格式"""
    normalized = dict(note)
    
    # 确保关键字段存在（兼容两种命名）
    if 'noteId' in note and 'note_id' not in note:
        normalized['note_id'] = note['noteId']
    if 'imageList' in note and 'image_list' not in note:
        normalized['image_list'] = note['imageList']
    if 'interactInfo' in note and 'interact_info' not in note:
        normalized['interact_info'] = note['interactInfo']
    if 'tagList' in note and 'tag_list' not in note:
        normalized['tag_list'] = note['tagList']
    
    # 处理图片列表格式差异
    image_list = normalized.get('image_list') or normalized.get('imageList') or []
    for img in image_list:
        if 'urlDefault' in img and 'info_list' not in img:
            img['info_list'] = [
                {'url': img['urlDefault'], 'image_scene': 'WB_DFT'},
                {'url': img.get('urlPre', img['urlDefault']), 'image_scene': 'PREVIEW'},
            ]
    
    return normalized

def build_note_archive(note: Dict[str, Any]) -> Dict[str, Any]:
    """构建笔记存档数据"""
    archive = {
        "version": 1,
        "type": "xiaohongshu_note",
        "note_id": note.get("note_id") or note.get("id"),
        "title": clean_text(note.get("title")),
        "blocks": [],
        "images": [],
        "videos": [],
        "topics": [],
        "mentions": [],
        "links": [],
        "plain_text": "",
        "markdown": "",
    }
    
    blocks: List[Dict[str, Any]] = []
    text_chunks: List[str] = []
    images: List[Dict[str, Any]] = []
    videos: List[Dict[str, Any]] = []
    
    # 标题
    title = clean_text(note.get("title"))
    if title:
        blocks.append({"type": "title", "text": title})
    
    # 正文描述（移除标签后的干净文本）
    raw_desc = clean_text(note.get("desc"))
    desc = strip_tags_from_text(raw_desc)
    if desc:
        blocks.append({"type": "text", "text": desc})
        text_chunks.append(desc)
    
    # 处理图片列表
    image_list = note.get("image_list") or note.get("images_list") or []
    for img in image_list:
        if not isinstance(img, dict):
            continue
        
        # 获取最佳URL
        best_url = None
        info_list = img.get("info_list") or []
        
        # 优先级映射: 越高越好
        SCENE_PRIORITY = {
            "ORIGIN": 100,
            "WB_DFT": 90,  # Web Default
            "POST_DETAIL": 80,
            "CRD": 10,     # Card/Thumbnail
            "PREVIEW": 5,
        }
        
        candidates = []
        for info in info_list:
            if isinstance(info, dict):
                info_url = safe_url(info.get("url"))
                # 过滤掉水印图片 (wm_1)
                if info_url and "wm_1" not in info_url:
                    scene = info.get("image_scene", "")
                    priority = SCENE_PRIORITY.get(scene, 50) # 默认为50
                    candidates.append((priority, info_url))
        
        # 按优先级排序 (降序)
        candidates.sort(key=lambda x: x[0], reverse=True)
        
        if candidates:
            best_url = candidates[0][1]
        
        if not best_url:
            best_url = safe_url(img.get("url_default") or img.get("url"))
        
        if best_url:
            img_data = {
                "url": best_url,
                "width": img.get("width"),
                "height": img.get("height"),
            }
            images.append(img_data)
            blocks.append({"type": "image", **img_data})
    
    # 处理视频
    video_info = note.get("video") or {}
    if video_info:
        media = video_info.get("media") or {}
        stream = media.get("stream") or {}
        h264_streams = stream.get("h264") or []
        
        video_url = None
        for s in h264_streams:
            if isinstance(s, dict):
                video_url = safe_url(s.get("master_url"))
                if video_url:
                    break
        
        if video_url:
            vid_data = {
                "url": video_url,
                "width": video_info.get("width"),
                "height": video_info.get("height"),
                "duration": video_info.get("duration"),
                "cover": safe_url(video_info.get("first_frame")),
            }
            videos.append(vid_data)
            blocks.append({"type": "video", **vid_data})
    
    archive["blocks"] = blocks
    archive["images"] = images
    archive["videos"] = videos
    archive["plain_text"] = "\n\n".join([t for t in text_chunks if t])
    
    return archive


def safe_url(url: Any) -> Optional[str]:
    """安全获取URL"""
    if not url or not isinstance(url, str):
        return None
    u = url.strip()
    if not u:
        return None
    if u.startswith("//"):
        return "https:" + u
    return u
