"""
B站平台适配器
"""
import re
import html as _html
import httpx
from datetime import datetime
from typing import Optional, Dict, Any
from urllib.parse import urlparse, parse_qs, urljoin
from app.logging import logger

from app.adapters.base import PlatformAdapter, ParsedContent
from app.adapters.errors import (
    AuthRequiredAdapterError,
    NonRetryableAdapterError,
    RetryableAdapterError,
)
from app.models import BilibiliContentType


class BilibiliAdapter(PlatformAdapter):
    """B站适配器"""
    
    # API 端点
    API_VIDEO_INFO = "https://api.bilibili.com/x/web-interface/view"
    # 文档：https://socialsisteryi.github.io/bilibili-API-collect/docs/article/info.html
    API_ARTICLE_INFO = "https://api.bilibili.com/x/article/viewinfo"
    API_DYNAMIC_INFO = "https://api.bilibili.com/x/polymer/web-dynamic/v1/opus/detail"
    # 兼容：标准动态详情接口（部分场景 opus/detail 不稳定时兜底）
    API_DYNAMIC_DETAIL = "https://api.bilibili.com/x/polymer/web-dynamic/v1/detail"
    API_BANGUMI_INFO = "https://api.bilibili.com/pgc/view/web/season"
    API_AUDIO_INFO = "https://www.bilibili.com/audio/music-service-c/web/song/info"
    API_LIVE_INFO = "https://api.live.bilibili.com/xlive/web-room/v1/index/getRoomBaseInfo"

    # URL 模式
    PATTERNS = {
        BilibiliContentType.VIDEO: [
            r'bilibili\.com/video/(BV[0-9A-Za-z]{10})',
            r'bilibili\.com/video/av(\d+)',
            r'b23\.tv/(BV[0-9A-Za-z]{10})',
            r'b23\.tv/av(\d+)',
        ],
        BilibiliContentType.ARTICLE: [
            r'bilibili\.com/read/cv(\d+)',
        ],
        BilibiliContentType.DYNAMIC: [
            r'bilibili\.com/opus/(\d+)',
            r't\.bilibili\.com/(\d+)',
        ],
        BilibiliContentType.BANGUMI: [
            r'bilibili\.com/bangumi/play/(ss\d+)',
            r'bilibili\.com/bangumi/play/(ep\d+)',
        ],
        BilibiliContentType.AUDIO: [
            r'bilibili\.com/audio/au(\d+)',
        ],
        BilibiliContentType.LIVE: [
            r'live\.bilibili\.com/(\d+)',
        ],
        BilibiliContentType.CHEESE: [
            r'bilibili\.com/cheese/(ss\d+)',
            r'bilibili\.com/cheese/(ep\d+)',
        ],
    }
    
    def __init__(self, cookies: Optional[Dict[str, str]] = None):
        """
        初始化
        
        Args:
            cookies: B站cookies（可选，用于访问需要登录的内容）
        """
        self.cookies = cookies or {}
        self.headers = {
            'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
            'Referer': 'https://www.bilibili.com',
        }

    def _format_request_error(self, e: Exception) -> str:
        # httpx 的异常在某些情况下 str(e) 为空；这里补齐类型与 repr，便于排查。
        msg = str(e).strip()
        if msg:
            return msg
        return f"{type(e).__name__}: {e!r}"

    def _clean_text(self, text: Any) -> str:
        """清洗文本（用于私有存档）。

        - HTML 反转义
        - 去除零宽字符
        - 统一换行并压缩多余空白
        """
        if text is None:
            return ""
        if not isinstance(text, str):
            text = str(text)

        val = _html.unescape(text)
        # 常见零宽/不可见字符
        val = val.replace("\u200b", "").replace("\ufeff", "")
        # 统一换行
        val = val.replace("\r\n", "\n").replace("\r", "\n")
        # 去掉行尾空白
        val = "\n".join([ln.strip() for ln in val.split("\n")])
        # 压缩连续空行（最多保留 1 个空行）
        val = re.sub(r"\n{3,}", "\n\n", val)
        return val.strip()

    def _prune_metadata(self, item: Dict[str, Any]) -> Dict[str, Any]:
        """裁剪冗余的大型元数据字段（如合辑列表、番剧章节列表等），防止数据库膨胀和接口响应过慢"""
        if not item or not isinstance(item, dict):
            return item
            
        # 1) UGC 合辑处理 (ugc_season)
        # B站某些长视频属于合辑，ugc_season 包含了合辑中所有（可能几百个）视频的详细元数据
        if 'ugc_season' in item and isinstance(item['ugc_season'], dict):
            season = item.get('ugc_season')
            if 'sections' in season and isinstance(season['sections'], list):
                for section in season['sections']:
                    if isinstance(section, dict) and 'episodes' in section and isinstance(section['episodes'], list):
                        # 记录数量并清空详细列表，防止数据过载
                        section['ep_count'] = len(section['episodes'])
                        section['episodes'] = [] # 清空集数详情
        
        # 2) PGC 番剧处理 (episodes) - 针对番剧、电影等
        if 'episodes' in item and isinstance(item['episodes'], list):
            # 番剧详情接口会返回所有剧集列表
            item['ep_count'] = len(item['episodes'])
            item['episodes'] = [] # 清空剧集列表

        # 3) 分P处理 (pages) - 针对多P视频
        if 'pages' in item and isinstance(item['pages'], list):
             # 分P通常包含每个分P的标题、时长等，如果太多也进行裁剪
             if len(item['pages']) > 10:
                 item['page_count'] = len(item['pages'])
                 item['pages'] = item['pages'][:10] # 仅保留前10个预览
             
        # 4) PGC 章节处理 (sections)
        if 'sections' in item and isinstance(item['sections'], list):
            # 针对一些 PGC 内容的章节信息
            for section in item['sections']:
                if isinstance(section, dict) and 'episodes' in section and isinstance(section['episodes'], list):
                    section['ep_count'] = len(section['episodes'])
                    section['episodes'] = []
                    
        return item

    def _safe_url(self, url: Any) -> Optional[str]:
        if not url or not isinstance(url, str):
            return None
        u = url.strip()
        if not u:
            return None
        # 允许 //i0.hdslb.com 这类协议相对
        if u.startswith("//"):
            return "https:" + u
        return u

    def _render_markdown(self, blocks: list[dict[str, Any]]) -> str:
        """将 blocks 渲染为 Markdown（用于私有存档预览/搜索）。"""
        parts: list[str] = []
        for b in blocks:
            b_type = b.get("type")
            if b_type == "title":
                t = self._clean_text(b.get("text"))
                if t:
                    parts.append(f"# {t}")
            elif b_type == "heading":
                t = self._clean_text(b.get("text"))
                level = b.get("level")
                try:
                    level_i = int(level) if level is not None else 2
                except Exception:
                    level_i = 2
                level_i = min(max(level_i, 2), 6)
                if t:
                    parts.append(f"{'#' * level_i} {t}")
            elif b_type == "text":
                t = self._clean_text(b.get("text"))
                if t:
                    parts.append(t)
            elif b_type == "quote":
                t = self._clean_text(b.get("text"))
                if t:
                    parts.append("\n".join([f"> {ln}" for ln in t.split("\n") if ln.strip()]))
            elif b_type == "separator":
                parts.append("---")
            elif b_type == "image":
                u = self._safe_url(b.get("url"))
                if u:
                    alt = self._clean_text(b.get("alt") or "image")
                    parts.append(f"![{alt}]({u})")
            elif b_type == "link":
                u = self._safe_url(b.get("url"))
                t = self._clean_text(b.get("text"))
                if u:
                    parts.append(f"[{t or u}]({u})")
        return "\n\n".join([p for p in parts if p]).strip()

    def _parse_opus_text_nodes(
        self,
        nodes: Any,
        links: list[dict[str, Any]],
        mentions: list[dict[str, Any]],
        topics: list[str],
    ) -> tuple[str, str]:
        """解析 module_content.text.nodes 结构，返回 (plain, markdown_inline)。

        该结构来自 opus/detail，形如：
        - TEXT_NODE_TYPE_WORD: node['word']['words'] + style
        - TEXT_NODE_TYPE_RICH: node['rich'] (web/topic/at 等)
        """
        if not isinstance(nodes, list):
            return "", ""

        plain_parts: list[str] = []
        md_parts: list[str] = []

        def apply_style(md: str, style: Any) -> str:
            if not md:
                return md
            if not isinstance(style, dict):
                return md
            if style.get("strikethrough"):
                md = f"~~{md}~~"
            if style.get("italic"):
                md = f"*{md}*"
            if style.get("bold"):
                md = f"**{md}**"
            return md

        for n in nodes:
            if not isinstance(n, dict):
                continue
            n_type = n.get("type")

            if n_type == "TEXT_NODE_TYPE_WORD":
                word = n.get("word") or {}
                text = self._clean_text(word.get("words") or "")
                if not text:
                    continue
                plain_parts.append(text)
                md_parts.append(apply_style(text, word.get("style")))
                continue

            if n_type == "TEXT_NODE_TYPE_RICH":
                rich = n.get("rich") or {}
                rich_type = rich.get("type") or ""
                text = self._clean_text(rich.get("text") or rich.get("orig_text") or "")
                jump_url = self._safe_url(rich.get("jump_url") or rich.get("url"))
                if jump_url and jump_url.startswith("//"):
                    jump_url = "https:" + jump_url

                # Web 链接
                if jump_url or rich_type == "RICH_TEXT_NODE_TYPE_WEB":
                    if jump_url:
                        links.append({"url": jump_url, "text": text})
                        plain_parts.append(text or jump_url)
                        md_parts.append(f"[{text or jump_url}]({jump_url})")
                    elif text:
                        plain_parts.append(text)
                        md_parts.append(text)
                    continue

                # @ 提及
                if rich_type in ("RICH_TEXT_NODE_TYPE_AT", "RICH_TEXT_NODE_TYPE_MENTION"):
                    rid = rich.get("rid") or rich.get("mid") or rich.get("id")
                    name = text
                    mentions.append({"mid": str(rid) if rid is not None else None, "name": name})
                    if name:
                        plain_parts.append(name)
                        md_parts.append(name)
                    continue

                # 话题
                if rich_type in ("RICH_TEXT_NODE_TYPE_TOPIC", "RICH_TEXT_NODE_TYPE_TAG"):
                    if text:
                        topics.append(text)
                        plain_parts.append(text)
                        md_parts.append(text)
                    continue

                # 兜底：当作普通文本
                if text:
                    plain_parts.append(text)
                    md_parts.append(text)

        return "".join(plain_parts), "".join(md_parts)
    
    async def detect_content_type(self, url: str) -> Optional[str]:
        """检测B站内容类型"""
        # b23.tv 的通用短链无法直接用正则识别类型，需要先还原
        if 'b23.tv' in url:
            url = await self._resolve_short_url(url)
        for content_type, patterns in self.PATTERNS.items():
            for pattern in patterns:
                if re.search(pattern, url):
                    return content_type.value
        return None
    
    async def clean_url(self, url: str) -> str:
        """净化URL"""
        # 处理短链
        if 'b23.tv' in url:
            url = await self._resolve_short_url(url)
        
        # 移除追踪参数
        parsed = urlparse(url)
        clean_url = f"{parsed.scheme}://{parsed.netloc}{parsed.path}"
        
        # 保留必要的查询参数（如视频的p参数）
        if parsed.query:
            query_params = parse_qs(parsed.query)
            essential_params = {}
            if 'p' in query_params:  # 视频分P
                essential_params['p'] = query_params['p'][0]
            if essential_params:
                from urllib.parse import urlencode
                clean_url += '?' + urlencode(essential_params)
        
        return clean_url
    
    async def _resolve_short_url(self, short_url: str) -> str:
        """解析短链"""
        try:
            async with httpx.AsyncClient(follow_redirects=True, timeout=10.0) as client:
                response = await client.get(short_url, headers=self.headers)
                return str(response.url)
        except Exception as e:
            logger.error(f"解析短链失败: {short_url}, 错误: {e}")
            return short_url
    
    def _extract_id(self, url: str, content_type: str) -> Optional[str]:
        """从URL中提取ID"""
        patterns = self.PATTERNS.get(BilibiliContentType(content_type), [])
        for pattern in patterns:
            match = re.search(pattern, url)
            if match:
                return match.group(1)
        return None
    
    async def parse(self, url: str) -> ParsedContent:
        """解析B站内容"""
        # 先净化再识别：确保通用 b23.tv 短链也能解析
        clean_url = await self.clean_url(url)

        content_type = await self.detect_content_type(clean_url)
        if not content_type:
            raise NonRetryableAdapterError(f"不支持的B站URL: {url}")
        
        if content_type == BilibiliContentType.VIDEO.value:
            return await self._parse_video(clean_url)
        elif content_type == BilibiliContentType.ARTICLE.value:
            return await self._parse_article(clean_url)
        elif content_type == BilibiliContentType.BANGUMI.value:
            return await self._parse_bangumi(clean_url)
        elif content_type == BilibiliContentType.LIVE.value:
            return await self._parse_live(clean_url)
        elif content_type == BilibiliContentType.DYNAMIC.value:
            return await self._parse_dynamic(clean_url)
            
        raise NonRetryableAdapterError(f"尚未实现 {content_type} 的解析")

    async def _parse_video(self, url: str) -> ParsedContent:
        """解析视频"""
        # 提取 bvid 或 aid
        bvid = None
        aid = None
        
        bv_match = re.search(r'video/(BV[0-9A-Za-z]{10})', url)
        if bv_match:
            bvid = bv_match.group(1)
        else:
            av_match = re.search(r'video/av(\d+)', url)
            if av_match:
                aid = av_match.group(1)
        
        if not bvid and not aid:
            raise NonRetryableAdapterError(f"无法从URL提取视频ID: {url}")
            
        params = {'bvid': bvid} if bvid else {'aid': aid}
        
        async with httpx.AsyncClient(headers=self.headers, cookies=self.cookies, timeout=10.0) as client:
            try:
                response = await client.get(self.API_VIDEO_INFO, params=params)
                data = response.json()
            except httpx.RequestError as e:
                raise RetryableAdapterError(f"B站请求失败: {self._format_request_error(e)}")
            
            if data.get('code') != 0:
                code = data.get('code')
                msg = data.get('message')
                # 403/权限不足通常需要登录
                if code in (-403, 62002, 62012):
                    raise AuthRequiredAdapterError(f"B站权限不足: {msg}", details={"code": code})
                if code in (-400, -404, 62004):
                    raise NonRetryableAdapterError(f"B站资源不可用: {msg}", details={"code": code})
                raise RetryableAdapterError(f"B站API错误: {msg}", details={"code": code})
            
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

            # 构建 Archive 结构 (用于媒体存档)
            archive = {
                "version": 2,
                "type": "bilibili_video",
                "title": item.get('title', ''),
                "plain_text": item.get('desc', ''),
                "markdown": item.get('desc', ''),
                "images": [{"url": item.get('pic')}] if item.get('pic') else [],
                "videos": [], # TODO: 支持视频下载
                "links": [],
                "stored_images": [],
                "stored_videos": []
            }
            # 保留原始元数据并附加 archive
            raw_metadata = self._prune_metadata(item)
            raw_metadata['archive'] = archive
            
            return ParsedContent(
                platform='bilibili',
                content_type=BilibiliContentType.VIDEO.value,
                content_id=bvid or f"av{aid}",
                clean_url=url,
                title=item.get('title'),
                description=item.get('desc'),
                author_name=item.get('owner', {}).get('name'),
                author_id=str(item.get('owner', {}).get('mid')),
                cover_url=item.get('pic'),
                media_urls=[item.get('pic')] if item.get('pic') else [],
                published_at=datetime.fromtimestamp(item.get('pubdate')),
                raw_metadata=raw_metadata,
                stats=stats
            )

    async def _parse_article(self, url: str) -> ParsedContent:
        """解析专栏文章"""
        cvid = self._extract_id(url, BilibiliContentType.ARTICLE.value)
        if not cvid:
            raise NonRetryableAdapterError(f"无法从URL提取文章ID: {url}")
            
        async with httpx.AsyncClient(headers=self.headers, cookies=self.cookies, timeout=10.0) as client:
            try:
                response = await client.get(self.API_ARTICLE_INFO, params={'id': cvid})
                data = response.json()
            except httpx.RequestError as e:
                raise RetryableAdapterError(f"B站请求失败: {self._format_request_error(e)}")
            
            if data.get('code') != 0:
                code = data.get('code')
                msg = data.get('message')
                if code in (-403,):
                    raise AuthRequiredAdapterError(f"B站权限不足: {msg}", details={"code": code})
                if code in (-400, -404):
                    raise NonRetryableAdapterError(f"B站资源不可用: {msg}", details={"code": code})
                raise RetryableAdapterError(f"B站API错误: {msg}", details={"code": code})
            
            item = data['data']
            stats = {
                'view': item.get('stats', {}).get('view', 0),
                'like': item.get('stats', {}).get('like', 0),
                'favorite': item.get('stats', {}).get('favorite', 0),
                'coin': item.get('stats', {}).get('coin', 0),
                'reply': item.get('stats', {}).get('reply', 0),
                'share': item.get('stats', {}).get('share', 0),
            }

            # 构建 Archive 结构
            image_urls = item.get('image_urls', [])
            archive = {
                "version": 2,
                "type": "bilibili_article",
                "title": item.get('title', ''),
                "plain_text": item.get('summary', ''),
                "markdown": item.get('summary', ''), # 暂无全文 Markdown，仅摘要
                "images": [{"url": u} for u in image_urls],
                "links": [],
                "stored_images": []
            }
            # 保留原始元数据并附加 archive
            raw_metadata = dict(item)
            raw_metadata['archive'] = archive
            
            return ParsedContent(
                platform='bilibili',
                content_type=BilibiliContentType.ARTICLE.value,
                content_id=f"cv{cvid}",
                clean_url=url,
                title=item.get('title'),
                description=item.get('summary'),
                author_name=item.get('author_name'),
                author_id=str(item.get('mid')),
                cover_url=item.get('banner_url') or (image_urls[0] if image_urls else None),
                media_urls=image_urls,
                published_at=datetime.fromtimestamp(item.get('publish_time')) if item.get('publish_time') else None,
                raw_metadata=raw_metadata,
                stats=stats
            )

    async def _parse_bangumi(self, url: str) -> ParsedContent:
        """解析番剧/电影 (PGC)"""
        id_val = self._extract_id(url, BilibiliContentType.BANGUMI.value)
        if not id_val:
            raise NonRetryableAdapterError(f"无法从URL提取番剧ID: {url}")
            
        params = {}
        if id_val.startswith('ss'):
            params['season_id'] = id_val[2:]
        elif id_val.startswith('ep'):
            params['ep_id'] = id_val[2:]
            
        async with httpx.AsyncClient(headers=self.headers, cookies=self.cookies, timeout=10.0) as client:
            try:
                response = await client.get(self.API_BANGUMI_INFO, params=params)
                data = response.json()
            except httpx.RequestError as e:
                raise RetryableAdapterError(f"B站请求失败: {self._format_request_error(e)}")
            
            if data.get('code') != 0:
                code = data.get('code')
                msg = data.get('message')
                if code in (-403,):
                    raise AuthRequiredAdapterError(f"B站权限不足: {msg}", details={"code": code})
                if code in (-400, -404):
                    raise NonRetryableAdapterError(f"B站资源不可用: {msg}", details={"code": code})
                raise RetryableAdapterError(f"B站API错误: {msg}", details={"code": code})
            
            item = data['result']
            stat = item.get('stat', {})
            stats = {
                'view': stat.get('views', 0),
                'like': stat.get('likes', 0),
                'favorite': stat.get('favorites', 0),
                'coin': stat.get('coins', 0),
                'reply': stat.get('reply', 0),
                'share': stat.get('share', 0),
                'danmaku': stat.get('danmakus', 0)
            }
            
            return ParsedContent(
                platform='bilibili',
                content_type=BilibiliContentType.BANGUMI.value,
                content_id=id_val,
                clean_url=url,
                title=item.get('title'),
                description=item.get('evaluate'),
                author_name="Bilibili Bangumi",
                author_id="0",
                cover_url=item.get('cover'),
                media_urls=[item.get('cover')],
                published_at=None,
                raw_metadata=self._prune_metadata(item),
                stats=stats
            )

    async def _parse_live(self, url: str) -> ParsedContent:
        """解析直播间"""
        room_id = self._extract_id(url, BilibiliContentType.LIVE.value)
        if not room_id:
            raise NonRetryableAdapterError(f"无法从URL提取直播间ID: {url}")
            
        async with httpx.AsyncClient(headers=self.headers, cookies=self.cookies, timeout=10.0) as client:
            # 使用 getRoomBaseInfo 接口，该接口支持短号且返回数据较全
            params = {
                'req_biz': 'web_room_componet',
                'room_ids': room_id
            }
            try:
                response = await client.get(self.API_LIVE_INFO, params=params)
                data = response.json()
            except httpx.RequestError as e:
                raise RetryableAdapterError(f"B站请求失败: {self._format_request_error(e)}")
            
            if data.get('code') != 0:
                code = data.get('code')
                msg = data.get('message')
                if code in (-403,):
                    raise AuthRequiredAdapterError(f"B站权限不足: {msg}", details={"code": code})
                if code in (-400, -404):
                    raise NonRetryableAdapterError(f"B站资源不可用: {msg}", details={"code": code})
                raise RetryableAdapterError(f"B站API错误: {msg}", details={"code": code})
            
            # 该接口返回的是字典，key 是长号 ID
            by_room_ids = data.get('data', {}).get('by_room_ids', {})
            if not by_room_ids:
                raise Exception("未找到直播间信息")
            
            # 获取第一个（也是唯一一个）直播间信息
            room_info = next(iter(by_room_ids.values()))
            
            # 直播间统计数据
            stats = {
                'view': room_info.get('online', 0),  # 人气值
                'live_status': room_info.get('live_status', 0), # 0:未开播, 1:直播中, 2:轮播中
            }
            
            return ParsedContent(
                platform='bilibili',
                content_type=BilibiliContentType.LIVE.value,
                content_id=str(room_info.get('room_id')),
                clean_url=url,
                title=room_info.get('title'),
                description=room_info.get('description'),
                author_name=room_info.get('uname'),
                author_id=str(room_info.get('uid')),
                cover_url=room_info.get('cover'),
                media_urls=[room_info.get('cover')] if room_info.get('cover') else [],
                published_at=None,
                raw_metadata=room_info,
                stats=stats
            )

    def _build_opus_archive(self, item: Dict[str, Any]) -> Dict[str, Any]:
        """从 Polymer 动态详情中提取可存档的完整图文内容。

        目标：用于个人浏览记录存档（raw_metadata 内），不影响对外分享字段。

        Returns:
            dict: 可 JSON 序列化的存档结构。
        """
        archive: Dict[str, Any] = {
            "version": 2,
            "type": "bilibili_opus",
            # 归档（私有）字段：不对外输出
            "title": "",
            "plain_text": "",
            "markdown": "",
            "blocks": [],
            "images": [],
            "links": [],
            "mentions": [],
            "topics": [],
        }

        modules = (item or {}).get("modules")
        modules_map: Dict[str, Any] = {}
        if isinstance(modules, list):
            for m in modules:
                m_type = (m.get("module_type") or "").lower().replace("_type_", "_")
                if m_type:
                    modules_map[m_type] = m.get(m_type, {})
        elif isinstance(modules, dict):
            modules_map = modules

        module_dynamic = modules_map.get("module_dynamic", {})
        module_content = modules_map.get("module_content", {})
        module_title = modules_map.get("module_title", {})

        major = (module_dynamic or {}).get("major", {})
        opus = (major or {}).get("opus", {})

        # 1) 标题
        title_val = opus.get("title") or module_title.get("text") or item.get("basic", {}).get("title") or ""
        archive["title"] = self._clean_text(title_val)

        # 2) 结构化正文 paragraphs
        # opus/detail 对于“文章式 Opus”常见结构为 module_content.paragraphs
        paragraphs = (
            (module_content.get("paragraphs") if isinstance(module_content, dict) else None)
            or ((opus.get("content") or {}).get("paragraphs") or [])
            or []
        )
        blocks: list[dict[str, Any]] = []
        text_chunks: list[str] = []
        images: list[dict[str, Any]] = []
        links: list[dict[str, Any]] = []
        for p in paragraphs:
            if not isinstance(p, dict):
                continue

            # 常见结构：{"para_type": 1, "text": {"nodes": [...]}}
            para_type = p.get("para_type")

            # Heading
            heading = p.get("heading")
            if isinstance(heading, dict):
                level = heading.get("level")
                nodes = heading.get("nodes")
                plain, md_inline = self._parse_opus_text_nodes(nodes, links, archive["mentions"], archive["topics"])
                cleaned = self._clean_text(plain)
                if cleaned:
                    blocks.append({"type": "heading", "level": level, "text": cleaned, "para_type": para_type})
                    text_chunks.append(cleaned)
                continue

            # Separator line
            if para_type == 3 and isinstance(p.get("line"), dict):
                blocks.append({"type": "separator", "para_type": para_type})
                continue

            # Text paragraph / quote
            text_obj = p.get("text") or {}
            nodes = text_obj.get("nodes")
            p_text = text_obj.get("content")
            if nodes is not None:
                plain, md_inline = self._parse_opus_text_nodes(nodes, links, archive["mentions"], archive["topics"])
                cleaned_plain = self._clean_text(plain)
                if cleaned_plain:
                    block_type = "quote" if para_type == 4 else "text"
                    blocks.append({"type": block_type, "text": cleaned_plain, "para_type": para_type})
                    text_chunks.append(cleaned_plain)
            elif p_text:
                cleaned = self._clean_text(p_text)
                if cleaned:
                    block_type = "quote" if para_type == 4 else "text"
                    blocks.append({"type": block_type, "text": cleaned, "para_type": para_type})
                    text_chunks.append(cleaned)

            # 图片：para_type=2 常见为 pic.pics 列表；也可能是 pic.url
            pic = p.get("pic") or {}
            if isinstance(pic, dict):
                pic_list = pic.get("pics")
                if isinstance(pic_list, list):
                    for one in pic_list:
                        if not isinstance(one, dict):
                            continue
                        url = self._safe_url(one.get("url"))
                        if not url:
                            continue
                        img = {
                            "url": url,
                            "width": one.get("width"),
                            "height": one.get("height"),
                            "size": one.get("size"),
                        }
                        blocks.append({"type": "image", **img, "para_type": para_type})
                        images.append(img)
                else:
                    url = self._safe_url(pic.get("url") or pic.get("src"))
                    if url:
                        img = {
                            "url": url,
                            "width": pic.get("width"),
                            "height": pic.get("height"),
                            "size": pic.get("size"),
                            "image_type": pic.get("image_type") or pic.get("type"),
                        }
                        blocks.append({"type": "image", **img, "para_type": para_type})
                        images.append(img)

            # link 信息（若存在）
            link = p.get("link")
            if isinstance(link, dict):
                href = self._safe_url(link.get("url") or link.get("href"))
                if href:
                    links.append({"url": href, "text": self._clean_text(link.get("text") or "")})

        # 3) 顶层 pics
        pics = opus.get("pics") or []
        for pic in pics:
            if not isinstance(pic, dict):
                continue
            url = self._safe_url(pic.get("url"))
            if not url:
                continue
            img = {
                "url": url,
                "width": pic.get("width"),
                "height": pic.get("height"),
                "size": pic.get("size"),
                "image_type": pic.get("image_type"),
            }
            images.append(img)
            blocks.append({"type": "image", **img})

        # 4) 兜底：如果没有 paragraphs，也尽量从可能存在的字段拿到文本
        if not text_chunks:
            fallback_text = opus.get("summary") or opus.get("text") or opus.get("content")
            if isinstance(fallback_text, str) and fallback_text.strip():
                cleaned = self._clean_text(fallback_text)
                if cleaned:
                    blocks.append({"type": "text", "text": cleaned})
                    text_chunks.append(cleaned)

        # 5) 额外附件/外链（如果存在，旧结构兼容）
        rich_text_nodes = (opus.get("rich_text") or {}).get("nodes")
        if isinstance(rich_text_nodes, list):
            for n in rich_text_nodes:
                if not isinstance(n, dict):
                    continue
                n_type = (n.get("type") or "").lower()
                if n_type in ("link", "url"):
                    href = self._safe_url(n.get("href") or n.get("url"))
                    if href:
                        links.append({"url": href, "text": self._clean_text(n.get("text") or "")})
                        blocks.append({"type": "link", "url": href, "text": self._clean_text(n.get("text") or "")})
                elif n_type in ("at", "mention"):
                    mid = n.get("rid") or n.get("mid") or n.get("id")
                    name = n.get("text") or n.get("uname") or ""
                    archive["mentions"].append({"mid": str(mid) if mid is not None else None, "name": self._clean_text(name)})
                elif n_type in ("topic", "tag"):
                    topic = n.get("text") or n.get("topic") or ""
                    topic = self._clean_text(topic)
                    if topic:
                        archive["topics"].append(topic)

        # 标题作为首 block（便于 markdown/搜索）
        if archive.get("title"):
            blocks = [{"type": "title", "text": archive["title"]}] + blocks

        # 去重 links/images
        seen_urls: set[str] = set()
        uniq_links: list[dict[str, Any]] = []
        for l in links:
            u = self._safe_url(l.get("url"))
            if not u or u in seen_urls:
                continue
            seen_urls.add(u)
            uniq_links.append({"url": u, "text": self._clean_text(l.get("text") or "")})

        seen_img: set[str] = set()
        uniq_images: list[dict[str, Any]] = []
        for img in images:
            u = self._safe_url(img.get("url"))
            if not u or u in seen_img:
                continue
            seen_img.add(u)
            uniq_images.append({**img, "url": u})

        archive["blocks"] = blocks
        archive["images"] = uniq_images
        archive["links"] = uniq_links
        archive["plain_text"] = self._clean_text("\n\n".join([t for t in text_chunks if t]))
        archive["markdown"] = self._render_markdown(blocks)

        # 日志：用于确认存档内容是否构建成功（避免打印全文）
        logger.debug(
            "Opus archive built: title_len={}, text_len={}, blocks={}, images={}, links={}, mentions={}, topics={}",
            len(str(archive.get("title") or "")),
            len(str(archive.get("plain_text") or "")),
            len(archive.get("blocks") or []),
            len(archive.get("images") or []),
            len(archive.get("links") or []),
            len(archive.get("mentions") or []),
            len(archive.get("topics") or []),
        )

        return archive

    async def _parse_dynamic(self, url: str) -> ParsedContent:
        """解析动态/图文 (Opus)"""
        dynamic_id = self._extract_id(url, BilibiliContentType.DYNAMIC.value)
        if not dynamic_id:
            raise NonRetryableAdapterError(f"无法从URL提取动态ID: {url}")
            
        # 动态解析需要特定的 features 参数和 buvid3 cookie 才能稳定返回
        params = {
            'id': dynamic_id,
            'features': 'itemOpusStyle,opusBigCover,onlyfansVote,endFooterHidden,decorationCard,onlyfansAssetsV2,ugcDelete,onlyfansQaCard,commentsNewVersion'
        }
        
        cookies = self.cookies.copy()
        if 'buvid3' not in cookies:
            cookies['buvid3'] = 'awa'
            
        async with httpx.AsyncClient(headers=self.headers, cookies=cookies, timeout=15.0) as client:
            try:
                response = await client.get(self.API_DYNAMIC_INFO, params=params)
                data = response.json()
            except httpx.RequestError as e:
                raise RetryableAdapterError(f"B站请求失败: {self._format_request_error(e)}")
            
            if data.get('code') != 0:
                # opus/detail 偶发不稳定：兜底尝试标准 detail 接口
                try:
                    response2 = await client.get(
                        self.API_DYNAMIC_DETAIL,
                        params={
                            "id": dynamic_id,
                            "features": params.get("features"),
                            "platform": "web",
                            "gaia_source": "main_web",
                        },
                    )
                    data2 = response2.json()
                    if data2.get("code") == 0:
                        data = data2
                    else:
                        raise Exception(data2.get("message"))
                except Exception as e:
                    code = data.get('code')
                    msg = data.get('message')
                    if code in (-352,):
                        raise RetryableAdapterError(f"B站风控/校验失败: {msg}", details={"code": code})
                    if code in (-403,):
                        raise AuthRequiredAdapterError(f"B站权限不足: {msg}", details={"code": code})
                    raise RetryableAdapterError(f"B站API错误: {msg}", details={"code": code, "fallback_error": str(e)})
            
            item = data['data']['item']

            # 构建存档数据（完整图文），放进 raw_metadata 里
            try:
                archive = self._build_opus_archive(item)
                logger.info(
                    "Opus archive ready: dynamic_id={}, text_len={}, images={}",
                    dynamic_id,
                    len(str(archive.get("plain_text") or "")),
                    len(archive.get("images") or []),
                )
            except Exception as e:
                logger.warning(f"构建 Opus 存档失败: {e}")
                archive = {"version": 2, "type": "bilibili_opus", "error": str(e)}

            modules = item.get('modules', [])

            # 兼容列表结构的 modules (Polymer API 特点)
            modules_map = {}
            if isinstance(modules, list):
                for m in modules:
                    # 修正映射逻辑：MODULE_TYPE_AUTHOR -> module_author
                    m_type = m.get('module_type', '').lower().replace('_type_', '_')
                    if m_type:
                        modules_map[m_type] = m.get(m_type, {})
            else:
                modules_map = modules

            module_author = modules_map.get('module_author', {})
            module_dynamic = modules_map.get('module_dynamic', {})
            module_stat = modules_map.get('module_stat', {})
            module_title = modules_map.get('module_title', {})

            # 处理 Opus 图文内容
            major = module_dynamic.get('major', {})
            opus = major.get('opus', {})

            # 标题回退机制（分享用：保持现状）
            title = opus.get('title') or module_title.get('text') or item.get('basic', {}).get('title') or "动态"

            # 提取正文（分享用：优先使用 archive 中的完整纯文本）
            summary = archive.get("plain_text") or ""
            if not summary and opus.get('content', {}).get('paragraphs'):
                summary = "\n".join([p.get('text', {}).get('content', '') 
                                   for p in opus['content']['paragraphs'] 
                                   if p.get('text', {}).get('content')])

            summary = self._clean_text(summary)

            # 提取图片（分享用：优先使用 archive 中的图片列表）
            pics = [img.get("url") for img in archive.get("images", []) if img.get("url")]
            if not pics:
                pics = [self._safe_url(p.get('url')) for p in opus.get('pics', []) if self._safe_url(p.get('url'))]

            # 提取互动数据
            stats = {
                'view': 0,
                'like': module_stat.get('like', {}).get('count', 0) if isinstance(module_stat.get('like'), dict) else 0,
                'reply': module_stat.get('comment', {}).get('count', 0) if isinstance(module_stat.get('comment'), dict) else 0,
                'share': module_stat.get('forward', {}).get('count', 0) if isinstance(module_stat.get('forward'), dict) else 0,
            }

            # 作者 ID 回退
            author_id = str(module_author.get('mid') or item.get('basic', {}).get('uid') or "")

            # raw_metadata：保留原始 item，并附加 archive（便于后续浏览功能开发）
            raw_metadata = dict(item) if isinstance(item, dict) else {"item": item}
            raw_metadata.setdefault("archive", {})
            raw_metadata["archive"] = archive

            logger.info(
                "Dynamic parsed with archive attached: dynamic_id={}, has_archive={}, archive_keys={}",
                dynamic_id,
                bool(raw_metadata.get("archive")),
                list((raw_metadata.get("archive") or {}).keys()),
            )

            return ParsedContent(
                platform='bilibili',
                content_type=BilibiliContentType.DYNAMIC.value,
                content_id=dynamic_id,
                clean_url=url,
                title=title,
                description=summary,
                author_name=module_author.get('name') or "未知用户",
                author_id=author_id,
                cover_url=pics[0] if pics else None,
                media_urls=pics,
                published_at=datetime.fromtimestamp(module_author.get('pub_ts')) if module_author.get('pub_ts') else None,
                raw_metadata=raw_metadata,
                stats=stats
            )