"""
小红书平台适配器

使用 xhshow 库进行签名，访问小红书 API 获取笔记内容
"""
import re
import html as _html
import httpx
from datetime import datetime
from typing import Optional, Dict, Any, List
from urllib.parse import urlparse, parse_qs, urlencode

from xhshow import Xhshow

from app.logging import logger
from app.adapters.base import PlatformAdapter, ParsedContent
from app.adapters.errors import (
    AuthRequiredAdapterError,
    NonRetryableAdapterError,
    RetryableAdapterError,
)
from app.config import settings


class XiaohongshuAdapter(PlatformAdapter):
    """
    小红书内容解析适配器
    
    使用 xhshow 库进行 API 签名，支持图文和视频笔记解析
    
    依赖:
    - settings.xiaohongshu_cookie: 必须配置有效的 Cookie 才能获取数据
    """
    
    # API 端点
    API_BASE = "https://edith.xiaohongshu.com"
    API_NOTE_FEED = "/api/sns/web/v1/feed"
    API_USER_INFO = "/api/sns/web/v1/user/otherinfo"
    API_USER_POSTED = "/api/sns/web/v1/user_posted"
    
    # URL 模式
    PATTERNS = {
        'note': [
            r'xiaohongshu\.com/explore/([a-f0-9]+)',
            r'xiaohongshu\.com/discovery/item/([a-f0-9]+)',
            r'xhslink\.com/([a-zA-Z0-9]+)',
        ],
        'user': [
            r'xiaohongshu\.com/user/profile/([a-f0-9]+)',
        ],
    }
    
    def __init__(self, cookie: Optional[str] = None, cookies: Optional[Dict[str, str]] = None):
        """
        初始化
        
        Args:
            cookie: 小红书 Cookie 字符串
            cookies: 小红书 Cookie 字典（兼容 worker 调用）
        """
        # 兼容 cookies 字典参数
        if cookies and not cookie:
            cookie = "; ".join([f"{k}={v}" for k, v in cookies.items()])
        
        self.cookie_str = cookie or (
            settings.xiaohongshu_cookie.get_secret_value() 
            if settings.xiaohongshu_cookie else None
        )
        self.cookies = self._parse_cookies(self.cookie_str) if self.cookie_str else {}
        self.xhs_client = Xhshow()
        self.headers = {
            'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
            'Referer': 'https://www.xiaohongshu.com/',
            'Origin': 'https://www.xiaohongshu.com',
            'Accept': 'application/json, text/plain, */*',
            'Accept-Language': 'zh-CN,zh;q=0.9,en;q=0.8',
            'Content-Type': 'application/json;charset=UTF-8',
        }
    
    def _parse_cookies(self, cookie_str: str) -> Dict[str, str]:
        """解析 Cookie 字符串为字典"""
        cookies = {}
        if not cookie_str:
            return cookies
        for item in cookie_str.split(';'):
            item = item.strip()
            if '=' in item:
                key, value = item.split('=', 1)
                cookies[key.strip()] = value.strip()
        return cookies
    
    def _clean_text(self, text: Any) -> str:
        """清洗文本"""
        if text is None:
            return ""
        if not isinstance(text, str):
            text = str(text)
        val = _html.unescape(text)
        val = val.replace("\u200b", "").replace("\ufeff", "")
        val = val.replace("\r\n", "\n").replace("\r", "\n")
        val = "\n".join([ln.strip() for ln in val.split("\n")])
        val = re.sub(r"\n{3,}", "\n\n", val)
        return val.strip()
    
    def _safe_url(self, url: Any) -> Optional[str]:
        """安全获取 URL"""
        if not url or not isinstance(url, str):
            return None
        u = url.strip()
        if not u:
            return None
        if u.startswith("//"):
            return "https:" + u
        return u
    
    def _extract_note_id(self, url: str) -> Optional[str]:
        """从 URL 提取笔记 ID"""
        for pattern in self.PATTERNS['note']:
            match = re.search(pattern, url)
            if match:
                return match.group(1)
        return None
    
    def _extract_user_id(self, url: str) -> Optional[str]:
        """从 URL 提取用户 ID"""
        for pattern in self.PATTERNS['user']:
            match = re.search(pattern, url)
            if match:
                return match.group(1)
        return None
    
    def _extract_xsec_token(self, url: str) -> Optional[str]:
        """从 URL 提取 xsec_token"""
        parsed = urlparse(url)
        params = parse_qs(parsed.query)
        return params.get('xsec_token', [None])[0]
    
    def _extract_xsec_source(self, url: str) -> str:
        """从 URL 提取 xsec_source，默认返回 pc_feed"""
        parsed = urlparse(url)
        params = parse_qs(parsed.query)
        return params.get('xsec_source', ['pc_feed'])[0]
    
    def _extract_source_tags(self, note: Dict[str, Any]) -> List[str]:
        """提取平台原生标签
        
        来源：
        1. tag_list 字段中的话题标签
        2. desc 描述中的 #话题[话题]# 格式
        """
        tags = set()
        
        # 从 tag_list 提取
        tag_list = note.get("tag_list") or note.get("tagList") or []
        for tag in tag_list:
            if isinstance(tag, dict):
                name = tag.get("name", "").strip()
                if name:
                    tags.add(name)
        
        # 从描述中提取 #xxx[话题]# 或 #xxx# 格式
        desc = note.get("desc", "") or ""
        # 匹配 #标签名[话题]# 格式
        pattern1 = r'#([^#\[\]]+)\[话题\]#'
        for match in re.findall(pattern1, desc):
            tag_name = match.strip()
            if tag_name:
                tags.add(tag_name)
        
        # 匹配普通 #标签# 格式（不含[话题]的）
        pattern2 = r'#([^#\[\]]+)#'
        for match in re.findall(pattern2, desc):
            tag_name = match.strip()
            if tag_name and '[话题]' not in tag_name:
                tags.add(tag_name)
        
        return sorted(list(tags))
    
    def _strip_tags_from_text(self, text: str) -> str:
        """从文本中移除标签格式
        
        移除:
        - #标签名[话题]# 格式
        - #标签名# 格式（独立的）
        """
        if not text:
            return ""
        
        # 移除 #xxx[话题]# 格式
        result = re.sub(r'#[^#\[\]]+\[话题\]#\s*', '', text)
        
        # 移除独立的 #xxx# 格式（前后是空白或行首行尾）
        result = re.sub(r'(?:^|\s)#[^#\[\]\s]+#(?:\s|$)', ' ', result)
        
        # 清理多余空白
        result = re.sub(r'\s+', ' ', result).strip()
        result = re.sub(r'\n\s*\n', '\n\n', result)
        
        return result
    
    async def detect_content_type(self, url: str) -> Optional[str]:
        """检测内容类型"""
        if self._extract_note_id(url):
            return 'note'
        if self._extract_user_id(url):
            return 'user_profile'
        return None
    
    async def clean_url(self, url: str) -> str:
        """净化 URL，保留 xsec_token 和 xsec_source 以便后续访问"""
        xsec_token = self._extract_xsec_token(url)
        xsec_source = self._extract_xsec_source(url)
        
        def build_query() -> str:
            params = []
            if xsec_token:
                params.append(f"xsec_token={xsec_token}")
            if xsec_source and xsec_source != "pc_feed":
                params.append(f"xsec_source={xsec_source}")
            return "?" + "&".join(params) if params else ""
        
        note_id = self._extract_note_id(url)
        if note_id:
            return f"https://www.xiaohongshu.com/explore/{note_id}{build_query()}"
        
        user_id = self._extract_user_id(url)
        if user_id:
            return f"https://www.xiaohongshu.com/user/profile/{user_id}{build_query()}"
        
        return url
    
    async def _resolve_short_link(self, url: str) -> str:
        """解析短链接"""
        if 'xhslink.com' not in url:
            return url
        
        async with httpx.AsyncClient(follow_redirects=True, timeout=10.0) as client:
            try:
                response = await client.get(url, headers={'User-Agent': self.headers['User-Agent']})
                return str(response.url)
            except Exception as e:
                logger.warning(f"解析小红书短链接失败: {e}")
                return url
    
    async def _make_signed_request(
        self, 
        method: str,
        uri: str, 
        params: Optional[Dict[str, Any]] = None,
        payload: Optional[Dict[str, Any]] = None,
    ) -> Dict[str, Any]:
        """发起带签名的请求"""
        if not self.cookies:
            raise AuthRequiredAdapterError("需要配置小红书 Cookie (XIAOHONGSHU_COOKIE)")
        
        # 生成签名头
        if method.upper() == 'GET':
            sign_headers = self.xhs_client.sign_headers_get(
                uri=uri,
                cookies=self.cookies,
                params=params or {}
            )
        else:
            sign_headers = self.xhs_client.sign_headers_post(
                uri=uri,
                cookies=self.cookies,
                payload=payload or {}
            )
        
        # 合并请求头
        headers = {**self.headers, **sign_headers}
        
        url = f"{self.API_BASE}{uri}"
        
        async with httpx.AsyncClient(timeout=15.0) as client:
            try:
                if method.upper() == 'GET':
                    response = await client.get(
                        url,
                        params=params,
                        headers=headers,
                        cookies=self.cookies
                    )
                else:
                    response = await client.post(
                        url,
                        json=payload,
                        headers=headers,
                        cookies=self.cookies
                    )
                
                data = response.json()
                
                if data.get('code') != 0 and data.get('success') is not True:
                    code = data.get('code')
                    msg = data.get('msg') or data.get('message') or '未知错误'
                    
                    if code in (-1, -100, 300012):
                        raise AuthRequiredAdapterError(f"小红书认证失败: {msg}", details={"code": code})
                    if code in (-2, 9999):
                        raise RetryableAdapterError(f"小红书服务暂时不可用: {msg}", details={"code": code})
                    
                    raise NonRetryableAdapterError(f"小红书API错误: {msg}", details={"code": code})
                
                return data
                
            except httpx.RequestError as e:
                raise RetryableAdapterError(f"小红书请求失败: {e}")
    
    async def _fetch_note(
        self, 
        note_id: str, 
        xsec_token: Optional[str] = None,
        xsec_source: str = "pc_feed"
    ) -> Dict[str, Any]:
        """获取笔记详情，优先使用 API，失败时回退到 SSR 解析"""
        # 先尝试 API 方式
        try:
            result = await self._fetch_note_via_api(note_id, xsec_token, xsec_source)
            logger.info(f"小红书笔记获取成功 [方式=API]: note_id={note_id}")
            return result
        except (NonRetryableAdapterError, RetryableAdapterError) as e:
            if not xsec_token:
                raise
            logger.warning(f"API 获取失败，回退到 SSR 解析: {e}")
        
        # 回退到 SSR 方式
        result = await self._fetch_note_via_ssr(note_id, xsec_token, xsec_source)
        logger.info(f"小红书笔记获取成功 [方式=SSR]: note_id={note_id}")
        return result
    
    async def _fetch_note_via_api(
        self, 
        note_id: str, 
        xsec_token: Optional[str] = None,
        xsec_source: str = "pc_feed"
    ) -> Dict[str, Any]:
        """通过 API 获取笔记详情"""
        payload = {
            "source_note_id": note_id,
            "image_formats": ["jpg", "webp", "avif"],
            "extra": {"need_body_topic": "1"},
            "xsec_source": xsec_source,
        }
        
        if xsec_token:
            payload["xsec_token"] = xsec_token
        
        data = await self._make_signed_request(
            method='POST',
            uri=self.API_NOTE_FEED,
            payload=payload
        )
        
        items = data.get('data', {}).get('items', [])
        if not items:
            if xsec_token:
                raise NonRetryableAdapterError(
                    f"API 返回空数据: {note_id}，可能被风控拦截"
                )
            else:
                raise NonRetryableAdapterError(
                    f"找不到笔记: {note_id}，缺少 xsec_token，请使用完整的分享链接"
                )
        
        return items[0].get('note_card', items[0])
    
    async def _fetch_note_via_ssr(
        self, 
        note_id: str, 
        xsec_token: Optional[str] = None,
        xsec_source: str = "pc_feed"
    ) -> Dict[str, Any]:
        """通过网页 SSR 数据获取笔记详情（备选方案）"""
        import json
        
        # 构建带 token 的 URL
        url = f"https://www.xiaohongshu.com/explore/{note_id}"
        if xsec_token:
            from urllib.parse import quote
            url += f"?xsec_token={quote(xsec_token, safe='')}&xsec_source={xsec_source}"
        
        async with httpx.AsyncClient(follow_redirects=True, timeout=15.0) as client:
            try:
                response = await client.get(
                    url,
                    headers={
                        'User-Agent': self.headers['User-Agent'],
                        'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
                        'Accept-Language': 'zh-CN,zh;q=0.9',
                    },
                    cookies=self.cookies
                )
                
                if response.status_code != 200:
                    raise RetryableAdapterError(f"SSR 请求失败: HTTP {response.status_code}")
                
                html = response.text
                
                # 检查是否被重定向到验证页面
                if 'captcha' in str(response.url) or '/404' in str(response.url):
                    raise NonRetryableAdapterError(f"访问被拦截: {response.url}")
                
                # 提取 __INITIAL_STATE__
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
                    raise NonRetryableAdapterError(f"SSR 数据解析失败: {e}")
                
                # 提取笔记数据
                note_detail = data.get('note', {}).get('noteDetailMap', {})
                if not note_detail:
                    note_detail = data.get('noteDetail', {}).get('data', {})
                
                if not note_detail:
                    raise NonRetryableAdapterError("SSR 数据中找不到笔记")
                
                # 获取目标笔记
                note_data = note_detail.get(note_id)
                if not note_data:
                    # 尝试获取第一个
                    first_key = next(iter(note_detail.keys()), None)
                    if first_key:
                        note_data = note_detail[first_key]
                
                if not note_data:
                    raise NonRetryableAdapterError(f"SSR 数据中找不到笔记: {note_id}")
                
                note = note_data.get('note', note_data)
                
                # 转换为与 API 兼容的格式
                return self._normalize_ssr_note(note)
                
            except httpx.RequestError as e:
                raise RetryableAdapterError(f"SSR 请求失败: {e}")
    
    def _normalize_ssr_note(self, note: Dict[str, Any]) -> Dict[str, Any]:
        """将 SSR 格式的笔记数据转换为 API 格式"""
        # SSR 格式使用 camelCase，API 格式使用 snake_case
        # 这里做兼容处理，保留两种格式的字段
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
            # SSR 格式: urlDefault, urlPre
            # API 格式: info_list[].url
            if 'urlDefault' in img and 'info_list' not in img:
                img['info_list'] = [
                    {'url': img.get('urlPre', img['urlDefault'])},
                    {'url': img['urlDefault']},
                ]
        
        # 处理互动信息格式差异
        interact = normalized.get('interact_info') or normalized.get('interactInfo') or {}
        if 'likedCount' in interact and 'liked_count' not in interact:
            interact['liked_count'] = interact['likedCount']
        if 'collectedCount' in interact and 'collected_count' not in interact:
            interact['collected_count'] = interact['collectedCount']
        if 'commentCount' in interact and 'comment_count' not in interact:
            interact['comment_count'] = interact['commentCount']
        if 'shareCount' in interact and 'share_count' not in interact:
            interact['share_count'] = interact['shareCount']
        
        normalized['interact_info'] = interact
        
        logger.debug(f"SSR 笔记数据已标准化: {normalized.get('note_id') or normalized.get('noteId')}")
        return normalized
    
    def _build_note_archive(self, note: Dict[str, Any]) -> Dict[str, Any]:
        """构建笔记存档数据"""
        archive = {
            "version": 1,
            "type": "xiaohongshu_note",
            "note_id": note.get("note_id") or note.get("id"),
            "title": self._clean_text(note.get("title")),
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
        title = self._clean_text(note.get("title"))
        if title:
            blocks.append({"type": "title", "text": title})
        
        # 正文描述（移除标签后的干净文本）
        raw_desc = self._clean_text(note.get("desc"))
        desc = self._strip_tags_from_text(raw_desc)
        if desc:
            blocks.append({"type": "text", "text": desc})
            text_chunks.append(desc)
        
        # 提取话题标签
        tag_list = note.get("tag_list") or []
        for tag in tag_list:
            if isinstance(tag, dict):
                tag_name = tag.get("name") or tag.get("tag_name")
                if tag_name:
                    archive["topics"].append(self._clean_text(tag_name))
        
        # 处理图片列表
        image_list = note.get("image_list") or note.get("images_list") or []
        for img in image_list:
            if not isinstance(img, dict):
                continue
            
            # 优先使用高清链接
            url_default = self._safe_url(img.get("url_default"))
            url_pre = self._safe_url(img.get("url_pre"))
            url = self._safe_url(img.get("url"))
            info_list = img.get("info_list") or []
            
            # 从 info_list 获取高清版本 (WB_DFT > WB_PRV)
            best_url = None
            for info in info_list:
                if isinstance(info, dict):
                    scene = info.get("image_scene", "")
                    info_url = self._safe_url(info.get("url"))
                    if info_url and "wm_1" not in info_url:  # 排除水印版
                        # 优先选择 WB_DFT (Default/高清)
                        if scene == "WB_DFT":
                            best_url = info_url
                            break
                        elif scene == "CRD_DFT":  # 卡片默认也是高清
                            best_url = info_url
                            break
                        elif not best_url:
                            best_url = info_url
            
            # 兜底：使用 url_default (通常是高清)
            if not best_url:
                best_url = url_default or url_pre or url
            
            if best_url:
                img_data = {
                    "url": best_url,
                    "width": img.get("width"),
                    "height": img.get("height"),
                    "original_url": url,
                }
                images.append(img_data)
                blocks.append({"type": "image", **img_data})
        
        # 处理视频
        video_info = note.get("video") or {}
        if video_info:
            # 获取视频 URL
            media = video_info.get("media") or {}
            stream = media.get("stream") or {}
            
            # 尝试获取 h264/h265 流
            h264_streams = stream.get("h264") or stream.get("h265") or []
            video_url = None
            
            for s in h264_streams:
                if isinstance(s, dict):
                    master_url = self._safe_url(s.get("master_url"))
                    backup_urls = s.get("backup_urls") or []
                    video_url = master_url or (backup_urls[0] if backup_urls else None)
                    if video_url:
                        break
            
            # 备用：从 consumer.origin_video_key 获取
            if not video_url:
                consumer = video_info.get("consumer") or {}
                origin_key = consumer.get("origin_video_key")
                if origin_key:
                    video_url = f"https://sns-video-bd.xhscdn.com/{origin_key}"
            
            if video_url:
                vid_data = {
                    "url": video_url,
                    "width": video_info.get("width"),
                    "height": video_info.get("height"),
                    "duration": video_info.get("duration"),
                    "cover": self._safe_url(video_info.get("first_frame")),
                }
                videos.append(vid_data)
                blocks.append({"type": "video", **vid_data})
        
        # 处理 at_user（提及用户）
        at_user_list = note.get("at_user_list") or []
        for at_user in at_user_list:
            if isinstance(at_user, dict):
                archive["mentions"].append({
                    "user_id": at_user.get("user_id"),
                    "nickname": self._clean_text(at_user.get("nickname")),
                })
        
        archive["blocks"] = blocks
        archive["images"] = images
        archive["videos"] = videos
        archive["plain_text"] = "\n\n".join([t for t in text_chunks if t])
        archive["markdown"] = self._render_markdown(blocks)
        
        return archive
    
    def _render_markdown(self, blocks: List[Dict[str, Any]]) -> str:
        """将 blocks 渲染为 Markdown"""
        parts: List[str] = []
        for b in blocks:
            b_type = b.get("type")
            if b_type == "title":
                t = b.get("text")
                if t:
                    parts.append(f"# {t}")
            elif b_type == "text":
                t = b.get("text")
                if t:
                    parts.append(t)
            elif b_type == "image":
                u = self._safe_url(b.get("url"))
                if u:
                    parts.append(f"![image]({u})")
            elif b_type == "video":
                u = self._safe_url(b.get("url"))
                cover = self._safe_url(b.get("cover"))
                if cover:
                    parts.append(f"[![video]({cover})]({u})")
                elif u:
                    parts.append(f"[视频]({u})")
        return "\n\n".join([p for p in parts if p]).strip()
    
    async def parse(self, url: str) -> ParsedContent:
        """解析小红书内容"""
        # 解析短链接
        url = await self._resolve_short_link(url)
        
        content_type = await self.detect_content_type(url)
        
        if content_type == 'note':
            return await self._parse_note(url)
        elif content_type == 'user_profile':
            return await self._parse_user(url)
        else:
            raise NonRetryableAdapterError(f"不支持的小红书链接类型: {url}")
    
    async def _parse_note(self, url: str) -> ParsedContent:
        """解析笔记"""
        note_id = self._extract_note_id(url)
        if not note_id:
            raise NonRetryableAdapterError(f"无法从URL提取笔记ID: {url}")
        
        xsec_token = self._extract_xsec_token(url)
        xsec_source = self._extract_xsec_source(url)
        
        logger.info(f"解析小红书笔记: note_id={note_id}, xsec_source={xsec_source}")
        
        note = await self._fetch_note(note_id, xsec_token, xsec_source)
        
        # 构建存档
        archive = self._build_note_archive(note)
        
        # 提取作者信息
        user = note.get("user") or {}
        author_id = user.get("user_id") or user.get("userid")
        author_name = self._clean_text(user.get("nickname") or user.get("nick_name"))
        author_avatar = self._safe_url(user.get("avatar") or user.get("images"))
        # 构建作者主页链接（带 xsec_token）
        author_url = None
        if author_id:
            user_xsec_token = user.get("xsec_token")
            author_url = f"https://www.xiaohongshu.com/user/profile/{author_id}"
            if user_xsec_token:
                author_url += f"?xsec_token={user_xsec_token}"
        
        # 提取平台原生标签（从 tag_list 和 desc 中的 #话题#）
        source_tags = self._extract_source_tags(note)
        
        # 提取封面
        images = archive.get("images", [])
        videos = archive.get("videos", [])
        cover_url = None
        if images:
            cover_url = images[0].get("url")
        elif videos and videos[0].get("cover"):
            cover_url = videos[0].get("cover")
        
        # 提取媒体 URL 列表
        media_urls = [img.get("url") for img in images if img.get("url")]
        for vid in videos:
            if vid.get("url"):
                media_urls.append(vid.get("url"))
        
        # 确定内容类型
        note_type = note.get("type")
        if note_type == "video" or videos:
            content_type = "video"
        else:
            content_type = "note"
        
        # 提取互动数据
        interact_info = note.get("interact_info") or {}
        stats = {
            "like": self._parse_count(interact_info.get("liked_count")),
            "collect": self._parse_count(interact_info.get("collected_count")),
            "comment": self._parse_count(interact_info.get("comment_count")),
            "share": self._parse_count(interact_info.get("share_count")),
            "view": 0,  # 小红书不公开展示浏览量
        }
        
        # 时间
        time_str = note.get("time") or note.get("create_time")
        published_at = None
        if time_str:
            try:
                if isinstance(time_str, (int, float)):
                    published_at = datetime.fromtimestamp(time_str / 1000 if time_str > 1e12 else time_str)
                else:
                    published_at = datetime.fromisoformat(str(time_str).replace('Z', '+00:00'))
            except Exception:
                pass
        
        # raw_metadata
        raw_metadata = dict(note) if isinstance(note, dict) else {"note": note}
        raw_metadata["archive"] = archive
        
        clean_url = await self.clean_url(url)
        
        logger.info(
            f"小红书笔记解析完成: note_id={note_id}, type={content_type}, "
            f"images={len(images)}, videos={len(videos)}"
        )
        
        return ParsedContent(
            platform='xiaohongshu',
            content_type=content_type,
            content_id=note_id,
            clean_url=clean_url,
            title=archive.get("title") or "小红书笔记",
            description=archive.get("plain_text"),
            author_name=author_name or "未知用户",
            author_id=author_id,
            author_avatar_url=author_avatar,
            author_url=author_url,
            cover_url=cover_url,
            media_urls=media_urls,
            published_at=published_at,
            raw_metadata=raw_metadata,
            stats=stats,
            source_tags=source_tags,
        )
    
    async def _parse_user(self, url: str) -> ParsedContent:
        """解析用户主页"""
        user_id = self._extract_user_id(url)
        if not user_id:
            raise NonRetryableAdapterError(f"无法从URL提取用户ID: {url}")
        
        xsec_token = self._extract_xsec_token(url)
        
        logger.info(f"解析小红书用户: user_id={user_id}")
        
        params = {"target_user_id": user_id}
        if xsec_token:
            params["xsec_token"] = xsec_token
        
        data = await self._make_signed_request(
            method='GET',
            uri=self.API_USER_INFO,
            params=params
        )
        
        user = data.get("data", {})
        
        # API 返回 camelCase，需要兼容两种格式
        basic_info = user.get("basicInfo") or user.get("basic_info") or {}
        nickname = self._clean_text(basic_info.get("nickname"))
        desc = self._clean_text(basic_info.get("desc"))
        avatar = self._safe_url(basic_info.get("imageb") or basic_info.get("images") or basic_info.get("image"))
        
        # 互动数据
        interactions = user.get("interactions") or []
        stats = {}
        for item in interactions:
            if isinstance(item, dict):
                item_type = (item.get("type") or "").lower()
                name = item.get("name", "")
                count = self._parse_count(item.get("count"))
                
                if item_type == "follows" or "关注" in name:
                    stats["following"] = count
                elif item_type == "fans" or "粉丝" in name:
                    stats["followers"] = count
                elif item_type == "interaction" or "获赞" in name or "收藏" in name:
                    stats["liked"] = count
        
        # 构建存档
        archive = {
            "version": 1,
            "type": "xiaohongshu_user",
            "user_id": user_id,
            "nickname": nickname,
            "desc": desc,
            "avatar": avatar,
        }
        
        raw_metadata = dict(user) if isinstance(user, dict) else {"user": user}
        raw_metadata["archive"] = archive
        
        clean_url = await self.clean_url(url)
        
        return ParsedContent(
            platform='xiaohongshu',
            content_type='user_profile',
            content_id=user_id,
            clean_url=clean_url,
            title=nickname or "小红书用户",
            description=desc,
            author_name=nickname,
            author_id=user_id,
            author_avatar_url=avatar,
            cover_url=avatar,
            media_urls=[avatar] if avatar else [],
            published_at=None,
            raw_metadata=raw_metadata,
            stats=stats,
        )
    
    def _parse_count(self, count: Any) -> int:
        """解析计数（可能是字符串如 "1.2万"、"10+"、"1万+"）"""
        if count is None:
            return 0
        if isinstance(count, int):
            return count
        if isinstance(count, float):
            return int(count)
        
        count_str = str(count).strip()
        if not count_str:
            return 0
        
        # 移除 + 号（如 "10+"、"1万+"）
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
