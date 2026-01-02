"""
B站平台适配器
"""
import re
import httpx
from datetime import datetime
from typing import Optional, Dict, Any
from urllib.parse import urlparse, parse_qs, urljoin
from loguru import logger

from app.adapters.base import PlatformAdapter, ParsedContent
from app.models import BilibiliContentType


class BilibiliAdapter(PlatformAdapter):
    """B站适配器"""
    
    # API 端点
    API_VIDEO_INFO = "https://api.bilibili.com/x/web-interface/view"
    API_ARTICLE_INFO = "https://api.bilibili.com/x/article/view"
    API_DYNAMIC_INFO = "https://api.bilibili.com/x/polymer/web-dynamic/v1/opus/detail"
    API_BANGUMI_INFO = "https://api.bilibili.com/pgc/view/web/season"
    API_AUDIO_INFO = "https://www.bilibili.com/audio/music-service-c/web/song/info"
    API_LIVE_INFO = "https://api.live.bilibili.com/xlive/web-room/v1/index/getRoomBaseInfo"

    # URL 模式
    PATTERNS = {
        BilibiliContentType.VIDEO: [
            r'bilibili\.com/video/(BV[\w]+)',
            r'bilibili\.com/video/av(\d+)',
            r'b23\.tv/(BV[\w]+)',
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
    
    async def detect_content_type(self, url: str) -> Optional[str]:
        """检测B站内容类型"""
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
            async with httpx.AsyncClient(follow_redirects=True) as client:
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
        content_type = await self.detect_content_type(url)
        if not content_type:
            raise ValueError(f"不支持的B站URL: {url}")
        
        clean_url = await self.clean_url(url)
        
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
            
        raise NotImplementedError(f"尚未实现 {content_type} 的解析")

    async def _parse_video(self, url: str) -> ParsedContent:
        """解析视频"""
        # 提取 bvid 或 aid
        bvid = None
        aid = None
        
        bv_match = re.search(r'video/(BV[\w]+)', url)
        if bv_match:
            bvid = bv_match.group(1)
        else:
            av_match = re.search(r'video/av(\d+)', url)
            if av_match:
                aid = av_match.group(1)
        
        if not bvid and not aid:
            raise ValueError(f"无法从URL提取视频ID: {url}")
            
        params = {'bvid': bvid} if bvid else {'aid': aid}
        
        async with httpx.AsyncClient(headers=self.headers, cookies=self.cookies) as client:
            response = await client.get(self.API_VIDEO_INFO, params=params)
            data = response.json()
            
            if data.get('code') != 0:
                raise Exception(f"B站API错误: {data.get('message')}")
            
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
                raw_metadata=item,
                stats=stats
            )

    async def _parse_article(self, url: str) -> ParsedContent:
        """解析专栏文章"""
        cvid = self._extract_id(url, BilibiliContentType.ARTICLE.value)
        if not cvid:
            raise ValueError(f"无法从URL提取文章ID: {url}")
            
        async with httpx.AsyncClient(headers=self.headers, cookies=self.cookies) as client:
            response = await client.get(self.API_ARTICLE_INFO, params={'id': cvid})
            data = response.json()
            
            if data.get('code') != 0:
                raise Exception(f"B站API错误: {data.get('message')}")
            
            item = data['data']
            stats = {
                'view': item.get('stats', {}).get('view', 0),
                'like': item.get('stats', {}).get('like', 0),
                'favorite': item.get('stats', {}).get('favorite', 0),
                'coin': item.get('stats', {}).get('coin', 0),
                'reply': item.get('stats', {}).get('reply', 0),
                'share': item.get('stats', {}).get('share', 0),
            }
            
            return ParsedContent(
                platform='bilibili',
                content_type=BilibiliContentType.ARTICLE.value,
                content_id=f"cv{cvid}",
                clean_url=url,
                title=item.get('title'),
                description=item.get('summary'),
                author_name=item.get('author', {}).get('name'),
                author_id=str(item.get('author', {}).get('mid')),
                cover_url=item.get('banner_url') or (item.get('image_urls')[0] if item.get('image_urls') else None),
                media_urls=item.get('image_urls', []),
                published_at=datetime.fromtimestamp(item.get('publish_time')) if item.get('publish_time') else None,
                raw_metadata=item,
                stats=stats
            )

    async def _parse_bangumi(self, url: str) -> ParsedContent:
        """解析番剧/电影 (PGC)"""
        id_val = self._extract_id(url, BilibiliContentType.BANGUMI.value)
        if not id_val:
            raise ValueError(f"无法从URL提取番剧ID: {url}")
            
        params = {}
        if id_val.startswith('ss'):
            params['season_id'] = id_val[2:]
        elif id_val.startswith('ep'):
            params['ep_id'] = id_val[2:]
            
        async with httpx.AsyncClient(headers=self.headers, cookies=self.cookies) as client:
            response = await client.get(self.API_BANGUMI_INFO, params=params)
            data = response.json()
            
            if data.get('code') != 0:
                raise Exception(f"B站API错误: {data.get('message')}")
            
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
                raw_metadata=item,
                stats=stats
            )

    async def _parse_live(self, url: str) -> ParsedContent:
        """解析直播间"""
        room_id = self._extract_id(url, BilibiliContentType.LIVE.value)
        if not room_id:
            raise ValueError(f"无法从URL提取直播间ID: {url}")
            
        async with httpx.AsyncClient(headers=self.headers, cookies=self.cookies) as client:
            # 使用 getRoomBaseInfo 接口，该接口支持短号且返回数据较全
            params = {
                'req_biz': 'web_room_componet',
                'room_ids': room_id
            }
            response = await client.get(self.API_LIVE_INFO, params=params)
            data = response.json()
            
            if data.get('code') != 0:
                raise Exception(f"B站API错误: {data.get('message')}")
            
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

    async def _parse_dynamic(self, url: str) -> ParsedContent:
        """解析动态/图文 (Opus)"""
        dynamic_id = self._extract_id(url, BilibiliContentType.DYNAMIC.value)
        if not dynamic_id:
            raise ValueError(f"无法从URL提取动态ID: {url}")
            
        # 动态解析需要特定的 features 参数和 buvid3 cookie 才能稳定返回
        params = {
            'id': dynamic_id,
            'features': 'onlyfansVote,onlyfansAssetsV2,decorationCard,htmlNewStyle,ugcDelete,editable,opusPrivateVisible,tribeeEdit,avatarAutoTheme,avatarTypeOpus'
        }
        
        cookies = self.cookies.copy()
        if 'buvid3' not in cookies:
            cookies['buvid3'] = 'awa'
            
        async with httpx.AsyncClient(headers=self.headers, cookies=cookies) as client:
            response = await client.get(self.API_DYNAMIC_INFO, params=params)
            data = response.json()
            
            if data.get('code') != 0:
                raise Exception(f"B站API错误: {data.get('message')}")
            
            item = data['data']['item']
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
            
            # 标题回退机制
            title = opus.get('title') or module_title.get('text') or item.get('basic', {}).get('title') or "动态"
            
            # 提取正文：Opus 的文字在 p['text']['content'] 中
            summary = ""
            if opus.get('content', {}).get('paragraphs'):
                summary = "\n".join([p.get('text', {}).get('content', '') 
                                   for p in opus['content']['paragraphs'] 
                                   if p.get('text', {}).get('content')])
            
            # 提取图片
            pics = [p.get('url') for p in opus.get('pics', []) if p.get('url')]
            
            # 提取互动数据
            stats = {
                'view': 0,
                'like': module_stat.get('like', {}).get('count', 0) if isinstance(module_stat.get('like'), dict) else 0,
                'reply': module_stat.get('comment', {}).get('count', 0) if isinstance(module_stat.get('comment'), dict) else 0,
                'share': module_stat.get('forward', {}).get('count', 0) if isinstance(module_stat.get('forward'), dict) else 0,
            }
            
            # 作者 ID 回退
            author_id = str(module_author.get('mid') or item.get('basic', {}).get('uid') or "")
            
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
                raw_metadata=item,
                stats=stats
            )