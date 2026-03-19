import re
import httpx
from typing import Optional, Dict, Any
from datetime import datetime
from markdownify import markdownify as md
from bs4 import BeautifulSoup
from loguru import logger
from app.adapters.base import PlatformAdapter, ParsedContent, LAYOUT_ARTICLE, LAYOUT_GALLERY
from app.adapters.errors import NonRetryableAdapterError, RetryableAdapterError, AuthRequiredAdapterError
from app.adapters.zhihu_parser import (
    parse_article,
    parse_question,
    parse_answer,
    parse_pin,
    parse_people
)
from app.adapters.zhihu_parser.base import preprocess_zhihu_html, extract_images
from app.adapters.zhihu_parser.models import ZhihuAuthor
from app.adapters.utils.cookie_utils import normalize_cookie_header_value
from app.core.config import settings


class ZhihuAdapter(PlatformAdapter):
    """知乎平台适配器 - API优先策略，失败时回退HTML解析"""
    
    _UA = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/145.0.0.0 Safari/537.36"
    _CHROME = "145"

    API_HEADERS = {
        "accept": "application/json, text/plain, */*",
        "accept-language": "zh-CN,zh;q=0.9,en-US;q=0.8,en;q=0.7",
        "user-agent": _UA,
        "referer": "https://www.zhihu.com/",
        "sec-ch-ua": f'"Not:A-Brand";v="99", "Google Chrome";v="{_CHROME}", "Chromium";v="{_CHROME}"',
        "sec-ch-ua-mobile": "?0",
        "sec-ch-ua-platform": '"Windows"',
        "sec-fetch-dest": "empty",
        "sec-fetch-mode": "cors",
        "sec-fetch-site": "same-origin",
        "x-api-version": "3.0",
        "x-requested-with": "fetch",
    }

    @staticmethod
    def _make_html_headers(url: str) -> dict:
        """根据目标 URL 动态生成 HTML 页面请求头，模拟真实浏览器指纹。"""
        from urllib.parse import urlparse
        parsed = urlparse(url)
        host = parsed.netloc or "www.zhihu.com"
        origin = f"{parsed.scheme}://{host}"
        return {
            "authority": host,
            "accept": "text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,image/apng,*/*;q=0.8,application/signed-exchange;v=b3;q=0.7",
            "accept-language": "zh-CN,zh;q=0.9,en-US;q=0.8,en;q=0.7",
            "cache-control": "no-cache",
            "pragma": "no-cache",
            "upgrade-insecure-requests": "1",
            "user-agent": ZhihuAdapter._UA,
            "sec-ch-ua": f'"Not:A-Brand";v="99", "Google Chrome";v="{ZhihuAdapter._CHROME}", "Chromium";v="{ZhihuAdapter._CHROME}"',
            "sec-ch-ua-mobile": "?0",
            "sec-ch-ua-platform": '"Windows"',
            "sec-fetch-dest": "document",
            "sec-fetch-mode": "navigate",
            "sec-fetch-site": "none",
            "sec-fetch-user": "?1",
            "referer": origin + "/",
        }

    # API Include 参数配置 (参考 fxzhihu 项目优化)
    API_INCLUDE_PARAMS = {
        # Answer: 公开可用，包含完整统计信息
        "answer": "content,excerpt,voteup_count,comment_count,created_time,updated_time,thanks_count,relationship.is_author,is_thanked,voting",
        
        # Article: 风控严格，通常需要 Cookie
        "article": "content,voteup_count,comment_count,created,updated,excerpt,title_image",
        
        # Question: 风控严格，补充 topics/created_time/updated_time
        "question": "detail,excerpt,content,visit_count,answer_count,follower_count,comment_count,voteup_count,topics,created_time,updated_time",
        
        # User: 公开可用，补充 favorite_count/description/badge
        "user": "allow_message,answer_count,articles_count,follower_count,following_count,voteup_count,thanked_count,favorited_count,favorite_count,pins_count,question_count,following_topic_count,following_question_count,following_favlists_count,following_columns_count,description,badge",
        
        # Column: 基础信息
        "column": "title,intro,articles_count,followers",
        
        # Collection: 基础信息
        "collection": "title,description,item_count,follower_count",
    }
    
    # API端点模板
    API_ENDPOINTS = {
        "answer": "https://www.zhihu.com/api/v4/answers/{id}",
        # 使用 zhuanlan.zhihu.com/api 端点（api.zhihu.com 被风控40362）
        "article": "https://zhuanlan.zhihu.com/api/articles/{id}",
        "question": "https://www.zhihu.com/api/v4/questions/{id}",
        "user": "https://www.zhihu.com/api/v4/members/{id}",
        "column": "https://www.zhihu.com/api/v4/columns/{id}",
        "collection": "https://api.zhihu.com/collections/{id}",
    }

    def __init__(self, cookies: Optional[Dict[str, str]] = None, raw_cookie_str: Optional[str] = None):
        # 保留 DB 中的原始 Cookie 串（含可能影响风控的边界字符），
        # 在请求头直传时优先使用；同时保留 dict 形式用于需要按键读取的逻辑。
        self.raw_cookie_str: Optional[str] = raw_cookie_str
        if not self.raw_cookie_str and settings.zhihu_cookie:
            self.raw_cookie_str = settings.zhihu_cookie.get_secret_value()

        self.cookies = cookies or {}
        if not self.cookies and self.raw_cookie_str:
            self.cookies = self.parse_cookie_str(self.raw_cookie_str)

    @staticmethod
    def _extract_zhihu_error(response: httpx.Response) -> tuple[Optional[int], str]:
        """Try extracting zhihu anti-risk code/message from response JSON."""
        code: Optional[int] = None
        message = ""
        try:
            payload = response.json()
            if isinstance(payload, dict) and isinstance(payload.get("error"), dict):
                err = payload["error"]
                raw_code = err.get("code")
                if isinstance(raw_code, int):
                    code = raw_code
                elif isinstance(raw_code, str) and raw_code.isdigit():
                    code = int(raw_code)
                raw_message = err.get("message")
                if isinstance(raw_message, str):
                    message = raw_message.strip()
        except Exception:
            pass
        return code, message

    @staticmethod
    def _preview_text(text: Optional[str], limit: int = 80) -> str:
        if not text:
            return ""
        normalized = re.sub(r"\s+", " ", text).strip()
        if len(normalized) <= limit:
            return normalized
        return normalized[:limit] + "..."

    @staticmethod
    def _stats_preview(stats: Optional[Dict[str, Any]]) -> str:
        if not stats:
            return "-"
        preferred = [
            "like",
            "reply",
            "favorite",
            "view",
            "follower_count",
            "answer_count",
            "item_count",
        ]
        parts = []
        for key in preferred:
            if key in stats:
                parts.append(f"{key}={stats.get(key)}")
        if not parts:
            for key, value in list(stats.items())[:4]:
                parts.append(f"{key}={value}")
        return ", ".join(parts[:4]) if parts else "-"

    def _log_parse_success(self, *, channel: str, parsed: ParsedContent) -> None:
        logger.info(
            "[zhihu parsed] channel={} type={} id={} author={} media_count={} title_preview={} body_preview={} stats={}",
            channel,
            parsed.content_type,
            parsed.content_id,
            parsed.author_name or "-",
            len(parsed.media_urls or []),
            self._preview_text(parsed.title, 60) or "-",
            self._preview_text(parsed.body, 120) or "-",
            self._stats_preview(parsed.stats),
        )

    async def detect_content_type(self, url: str) -> Optional[str]:
        if "zhuanlan.zhihu.com/p/" in url:
            return "article"
        elif "/column/" in url or "zhuanlan.zhihu.com" in url and "/p/" not in url:
            # 专栏主页: zhuanlan.zhihu.com/column-id 或 zhihu.com/column/xxx
            if re.search(r'zhihu\.com/column/(\w+)', url):
                return "column"
            # zhuanlan.zhihu.com/learning-to-learn 形式
            match = re.search(r'zhuanlan\.zhihu\.com/(\w[\w-]+)$', url)
            if match and match.group(1) != 'p':
                return "column"
        if "/collection/" in url:
            return "collection"
        elif "zhihu.com/question/" in url and "answer" not in url:
            return "question"
        elif "zhihu.com/question/" in url and "answer" in url:
            return "answer"
        elif "zhihu.com/answer/" in url:
            return "answer"
        elif "zhihu.com/pin/" in url:
            return "pin"
        elif "zhihu.com/people/" in url:
            return "user_profile"
        return None

    async def clean_url(self, url: str) -> str:
        return url.split('?')[0]

    async def _get_proxy_url(self) -> Optional[str]:
        from app.services.settings_service import get_setting_value
        proxy_url = await get_setting_value("http_proxy", getattr(settings, 'http_proxy', None))
        
        if proxy_url and proxy_url.startswith("socks://"):
            proxy_url = proxy_url.replace("socks://", "socks5://")
        return proxy_url

    def _extract_id_from_url(self, url: str, content_type: str) -> Optional[str]:
        """从URL中提取内容ID"""
        patterns = {
            "answer": [
                r'zhihu\.com/question/\d+/answer/(\d+)',
                r'zhihu\.com/answer/(\d+)',
            ],
            "article": [
                r'zhuanlan\.zhihu\.com/p/(\d+)',
            ],
            "question": [
                r'zhihu\.com/question/(\d+)',
            ],
            "user_profile": [
                r'zhihu\.com/people/([\w-]+)',
            ],
            "column": [
                r'zhihu\.com/column/([\w-]+)',
                r'zhuanlan\.zhihu\.com/([\w-]+)$',
            ],
            "collection": [
                r'zhihu\.com/collection/(\d+)',
            ],
            "pin": [
                r'zhihu\.com/pin/(\d+)',
            ],
        }
        
        for pattern in patterns.get(content_type, []):
            match = re.search(pattern, url)
            if match:
                return match.group(1)
        return None

    def _build_api_url(self, content_type: str, content_id: str) -> str:
        """构建带有 include 参数的 API URL"""
        base_url = self.API_ENDPOINTS.get(content_type, "").format(id=content_id)
        include_params = self.API_INCLUDE_PARAMS.get(content_type, "")
        
        if include_params:
            separator = "&" if "?" in base_url else "?"
            return f"{base_url}{separator}include={include_params}"
        return base_url
    
    async def _api_request(self, content_type: str, content_id: str, use_cookies: bool = False) -> Optional[Dict[str, Any]]:
        """通用API请求方法"""
        api_url = self._build_api_url(content_type, content_id)
        proxy_url = await self._get_proxy_url()
        request_cookies = self.cookies if use_cookies else {}

        # 动态添加 CSRF token header（某些 API 如 question 需要）
        extra_headers = {}
        if use_cookies and self.cookies.get("_xsrf"):
            extra_headers["x-xsrftoken"] = self.cookies["_xsrf"]
        # article 端点在 zhuanlan.zhihu.com，需要对应的 referer
        if content_type == "article":
            extra_headers["referer"] = f"https://zhuanlan.zhihu.com/p/{content_id}"
        elif content_type == "question":
            extra_headers["referer"] = f"https://www.zhihu.com/question/{content_id}"
        if use_cookies and self.raw_cookie_str:
            extra_headers["cookie"] = normalize_cookie_header_value(
                self.raw_cookie_str,
                ensure_outer_quotes=True,
            )
            request_cookies = None

        headers = {**self.API_HEADERS, **extra_headers}

        async with httpx.AsyncClient(
            headers=headers,
            cookies=request_cookies,
            follow_redirects=True,
            timeout=15.0,
            proxy=proxy_url
        ) as client:
            try:
                response = await client.get(api_url)
                
                if response.status_code == 404:
                    return {"_error": "not_found"}
                if response.status_code in (401, 403):
                    risk_code, risk_message = self._extract_zhihu_error(response)
                    logger.bind(
                        event="zhihu_risk_blocked",
                        stage="api",
                        content_type=content_type,
                        content_id=content_id,
                        status_code=response.status_code,
                        zhihu_error_code=risk_code,
                    ).warning(
                        "Zhihu API blocked: type={} id={} status={} code={} msg={}",
                        content_type,
                        content_id,
                        response.status_code,
                        risk_code,
                        (risk_message or response.text[:160]),
                    )
                    return {"_error": "auth_required", "_status": response.status_code}
                if response.status_code != 200:
                    logger.bind(
                        event="zhihu_api_failed",
                        stage="api",
                        content_type=content_type,
                        content_id=content_id,
                        status_code=response.status_code,
                    ).warning(
                        "Zhihu API request failed: type={} id={} status={}",
                        content_type,
                        content_id,
                        response.status_code,
                    )
                    return {"_error": "request_failed", "_status": response.status_code}
                
                data = response.json()
                if "error" in data:
                    err = data.get("error") if isinstance(data, dict) else {}
                    err_code = err.get("code") if isinstance(err, dict) else None
                    err_msg = err.get("message", "") if isinstance(err, dict) else ""
                    logger.bind(
                        event="zhihu_api_error",
                        stage="api",
                        content_type=content_type,
                        content_id=content_id,
                        zhihu_error_code=err_code,
                    ).warning(
                        "Zhihu API responded with logical error: type={} id={} code={} msg={}",
                        content_type,
                        content_id,
                        err_code,
                        err_msg,
                    )
                    return {"_error": "api_error", "_message": err_msg}
                
                return data
                
            except httpx.RequestError as e:
                logger.warning(f"API请求异常: {e}")
                return None
            except Exception as e:
                logger.warning(f"API解析异常: {e}")
                return None

    # ==================== API解析方法 ====================

    async def _parse_answer_via_api(self, answer_id: str, url: str) -> Optional[ParsedContent]:
        """通过API解析回答"""
        # 优先尝试使用Cookie获取完整内容（知乎对无Cookie请求返回截断的content）
        data = await self._api_request("answer", answer_id, use_cookies=True)
        
        # 如果Cookie请求失败，回退到无Cookie请求（可能内容不完整）
        if not data or "_error" in data:
            data = await self._api_request("answer", answer_id, use_cookies=False)
        
        if not data or "_error" in data:
            return None
        
        return self._build_answer_from_api(data, url)

    async def _parse_article_via_api(self, article_id: str, url: str) -> Optional[ParsedContent]:
        """通过API解析文章"""
        data = await self._api_request("article", article_id, use_cookies=True)
        
        if not data or "_error" in data:
            return None
        
        return self._build_article_from_api(data, url)

    async def _parse_question_via_api(self, question_id: str, url: str) -> Optional[ParsedContent]:
        """通过API解析问题"""
        data = await self._api_request("question", question_id, use_cookies=True)
        
        if not data or "_error" in data:
            return None
        
        return self._build_question_from_api(data, url)

    async def _parse_user_via_api(self, user_id: str, url: str) -> Optional[ParsedContent]:
        """通过API解析用户信息"""
        data = await self._api_request("user", user_id, use_cookies=False)
        
        if not data or "_error" in data:
            return None
        
        return self._build_user_from_api(data, url)

    async def _parse_column_via_api(self, column_id: str, url: str) -> Optional[ParsedContent]:
        """通过API解析专栏"""
        data = await self._api_request("column", column_id, use_cookies=False)
        
        if not data or "_error" in data:
            return None
        
        return self._build_column_from_api(data, url)

    async def _parse_collection_via_api(self, collection_id: str, url: str) -> Optional[ParsedContent]:
        """通过API解析收藏夹"""
        data = await self._api_request("collection", collection_id, use_cookies=False)
        
        if not data or "_error" in data:
            return None
        
        return self._build_collection_from_api(data, url)

    # ==================== 构建ParsedContent ====================

    def _build_answer_from_api(self, data: Dict, url: str) -> ParsedContent:
        """从API响应构建回答ParsedContent"""
        answer_id = str(data.get('id', ''))
        
        question_data = data.get('question', {})
        question_id = question_data.get('id')
        question_title = question_data.get('title', '')
        
        author_data = data.get('author', {})
        author = ZhihuAuthor(
            id=author_data.get('id'),
            urlToken=author_data.get('url_token'),
            name=author_data.get('name', 'Unknown'),
            avatarUrl=author_data.get('avatar_url'),
            headline=author_data.get('headline'),
            gender=author_data.get('gender')
        )
        
        content_html = data.get('content', '')
        processed_html = preprocess_zhihu_html(content_html)
        media_urls = extract_images(processed_html)
        markdown_content = md(processed_html, heading_style="ATX")
        
        created = data.get('created_time')
        published_at = datetime.fromtimestamp(created) if created else None
        
        stats = {
            "like": data.get('voteup_count', 0),
            "reply": data.get('comment_count', 0),
            "thanks_count": data.get('thanks_count', 0),
            "voteup_count": data.get('voteup_count', 0),
            "comment_count": data.get('comment_count', 0),
        }

        # archive_metadata replaces this usage eventually
        archive_metadata = {
            "version": 2,
            "raw_api_response": data,
            "processed_archive": self._build_archive("zhihu_answer", 
                f"回答：{question_title}" if question_title else f"知乎回答 {answer_id}",
                processed_html, markdown_content, media_urls, author.avatar_url)
        }
        
        # Context Data
        context_data = {
            "type": "question",
            "title": question_title,
            "url": f"https://www.zhihu.com/question/{question_id}" if question_id else None,
            "id": str(question_id) if question_id else None,
            "stats": {
                "answer_count": question_data.get('answer_count', 0),
                "follower_count": question_data.get('follower_count', 0),
                "visit_count": question_data.get('visit_count', 0)
            }
        }
        
        return ParsedContent(
            platform="zhihu",
            content_type="answer",
            content_id=answer_id,
            clean_url=url.split('?')[0],
            layout_type=LAYOUT_ARTICLE,  # 知乎回答为长文布局
            title=f"回答：{question_title}" if question_title else f"知乎回答 {answer_id}",
            body=markdown_content,
            author_name=author.name,
            author_id=author.url_token or str(author.id),
            author_avatar_url=author.avatar_url,
            author_url=f"https://www.zhihu.com/people/{author.url_token}" if author.url_token else None,
            cover_url=data.get('thumbnail') or (media_urls[0] if media_urls else None),
            media_urls=media_urls,
            published_at=published_at,
            archive_metadata=archive_metadata,
            stats=stats,
            context_data=context_data,
        )

    def _build_article_from_api(self, data: Dict, url: str) -> ParsedContent:
        """从API响应构建文章ParsedContent"""
        article_id = str(data.get('id', ''))
        title = data.get('title', '')
        
        author_data = data.get('author', {})
        author = ZhihuAuthor(
            id=author_data.get('id'),
            urlToken=author_data.get('url_token'),
            name=author_data.get('name', 'Unknown'),
            avatarUrl=author_data.get('avatar_url'),
            headline=author_data.get('headline'),
            gender=author_data.get('gender')
        )
        
        content_html = data.get('content', '')
        processed_html = preprocess_zhihu_html(content_html)
        media_urls = extract_images(processed_html)
        markdown_content = md(processed_html, heading_style="ATX")
        
        created = data.get('created')
        published_at = datetime.fromtimestamp(created) if created else None
        
        stats = {
            "like": data.get('voteup_count', 0),
            "reply": data.get('comment_count', 0),
            "favorite": data.get('collected_count', 0),
            "voteup_count": data.get('voteup_count', 0),
            "comment_count": data.get('comment_count', 0),
        }
        
        archive_metadata = {
            "version": 2,
            "raw_api_response": data,
            "processed_archive": self._build_archive("zhihu_article", title, 
                processed_html, markdown_content, media_urls, author.avatar_url)
        }
        
        cover_url = data.get('title_image') or data.get('image_url')
        if not cover_url and media_urls:
            cover_url = media_urls[0]
        
        return ParsedContent(
            platform="zhihu",
            content_type="article",
            content_id=article_id,
            clean_url=url.split('?')[0],
            layout_type=LAYOUT_ARTICLE,  # 知乎文章为长文布局
            title=title,
            body=markdown_content,
            author_name=author.name,
            author_id=author.url_token or str(author.id),
            author_avatar_url=author.avatar_url,
            author_url=f"https://www.zhihu.com/people/{author.url_token}" if author.url_token else None,
            cover_url=cover_url,
            media_urls=media_urls,
            published_at=published_at,
            archive_metadata=archive_metadata,
            stats=stats
        )

    def _build_question_from_api(self, data: Dict, url: str) -> ParsedContent:
        """从API响应构建问题ParsedContent"""
        question_id = str(data.get('id', ''))
        title = data.get('title', '')
        
        author_data = data.get('author', {})
        author_name = author_data.get('name', 'Anonymous') if author_data else 'Anonymous'
        author_id = author_data.get('url_token', '') if author_data else ''
        
        detail_html = data.get('detail', '') or data.get('excerpt', '')
        processed_html = preprocess_zhihu_html(detail_html)
        media_urls = extract_images(processed_html)
        markdown_content = md(processed_html, heading_style="ATX")
        
        # 提取话题标签
        topics = data.get('topics', [])
        topic_names = [t.get('name', '') for t in topics if t.get('name')]
        
        created = data.get('created') or data.get('created_time')
        published_at = datetime.fromtimestamp(created) if created else None
        
        stats = {
            "view": data.get('visit_count', 0),
            "reply": data.get('answer_count', 0),
            "favorite": data.get('follower_count', 0),
            "like": data.get('voteup_count', 0) or 0,
            "comment_count": data.get('comment_count', 0),
            "visit_count": data.get('visit_count', 0),
            "answer_count": data.get('answer_count', 0),
            "follower_count": data.get('follower_count', 0),
        }
        
        # Build archive structure for media processing
        archive_images = [{"url": u} for u in media_urls]
        if author_data and author_data.get('avatar_url'):
            archive_images.append({"url": author_data.get('avatar_url'), "type": "avatar"})

        archive_metadata = {
            "version": 2,
            "raw_api_response": data,
            "topics": topic_names,  # 问题话题列表
            "archive": {
                "version": 2,
                "type": "zhihu_question",
                "title": title,
                "plain_text": BeautifulSoup(processed_html, 'html.parser').get_text("\n"),
                "markdown": markdown_content,
                "images": archive_images,
                "links": [],
                "stored_images": [],
            }
        }
        
        return ParsedContent(
            platform="zhihu",
            content_type="question",
            content_id=question_id,
            clean_url=url.split('?')[0],
            layout_type=LAYOUT_GALLERY,  # 知乎问题使用画廊布局（卡片置于右侧）
            title=title,
            body=markdown_content,
            author_name=author_name,
            author_id=author_id,
            author_url=f"https://www.zhihu.com/people/{author_id}" if author_id else None,
            cover_url=media_urls[0] if media_urls else None,
            media_urls=media_urls,
            published_at=published_at,
            archive_metadata=archive_metadata,
            stats=stats
        )

    def _build_user_from_api(self, data: Dict, url: str) -> ParsedContent:
        """从API响应构建用户ParsedContent"""
        user_id = data.get('id', '')
        url_token = data.get('url_token', '')
        name = data.get('name', 'Unknown')
        headline = data.get('headline', '')
        avatar_url = data.get('avatar_url', '')
        
        stats = {
            "view": data.get('follower_count', 0),
            "share": data.get('following_count', 0),
            "like": data.get('thanked_count', 0),
            "favorite": data.get('favorited_count', 0),
            "follower_count": data.get('follower_count', 0),
            "following_count": data.get('following_count', 0),
            "voteup_count": data.get('voteup_count', 0),
            "thanked_count": data.get('thanked_count', 0),
            "favorited_count": data.get('favorited_count', 0),
            "favorite_count": data.get('favorite_count', 0),  # 用户自己收藏的内容数
            "answer_count": data.get('answer_count', 0),
            "articles_count": data.get('articles_count', 0),
            "pins_count": data.get('pins_count', 0),
            "question_count": data.get('question_count', 0),
        }
        
        return ParsedContent(
            platform="zhihu",
            content_type="user_profile",
            content_id=str(user_id),
            clean_url=url.split('?')[0],
            layout_type=LAYOUT_GALLERY,  # 用户主页为Gallery布局
            title=f"{name} 的知乎主页",
            body=headline,
            author_name=name,
            author_id=url_token,
            author_avatar_url=avatar_url,
            author_url=f"https://www.zhihu.com/people/{url_token}" if url_token else None,
            cover_url=avatar_url,
            media_urls=[avatar_url] if avatar_url else [],
            published_at=datetime.now(),
            stats=stats,
            archive_metadata={"raw_api_response": data}
        )

    def _build_column_from_api(self, data: Dict, url: str) -> ParsedContent:
        """从API响应构建专栏ParsedContent"""
        column_id = data.get('id', '')
        title = data.get('title', '')
        intro = data.get('intro', '') or data.get('description', '')
        image_url = data.get('image_url', '')
        
        author_data = data.get('author', {})
        author_name = author_data.get('name', 'Unknown') if author_data else 'Unknown'
        author_id = author_data.get('url_token', '') if author_data else ''
        author_avatar = author_data.get('avatar_url', '') if author_data else ''
        
        stats = {
            "view": data.get('followers', 0),
            "reply": data.get('articles_count', 0) or data.get('items_count', 0),
            "like": data.get('voteup_count', 0),
            "followers": data.get('followers', 0),
            "articles_count": data.get('articles_count', 0) or data.get('items_count', 0),
        }
        
        updated = data.get('updated')
        published_at = datetime.fromtimestamp(updated) if updated else datetime.now()
        
        return ParsedContent(
            platform="zhihu",
            content_type="column",
            content_id=str(column_id),
            clean_url=url.split('?')[0],
            layout_type=LAYOUT_ARTICLE,  # 专栏为文章布局
            title=f"专栏：{title}" if title else f"知乎专栏 {column_id}",
            body=intro,
            author_name=author_name,
            author_id=author_id,
            author_avatar_url=author_avatar,
            author_url=f"https://www.zhihu.com/people/{author_id}" if author_id else None,
            cover_url=image_url,
            media_urls=[image_url] if image_url else [],
            published_at=published_at,
            stats=stats,
            archive_metadata={"raw_api_response": data}
        )

    def _build_collection_from_api(self, data: Dict, url: str) -> ParsedContent:
        """从API响应构建收藏夹ParsedContent"""
        collection_data = data.get('collection', data)
        
        collection_id = collection_data.get('id', '')
        title = collection_data.get('title', '')
        description = collection_data.get('description', '')
        
        creator = collection_data.get('creator', {})
        creator_name = creator.get('name', 'Unknown') if creator else 'Unknown'
        creator_id = creator.get('url_token', '') if creator else ''
        creator_avatar = creator.get('avatar_url', '') if creator else ''
        
        stats = {
            "view": collection_data.get('view_count', 0),
            "reply": collection_data.get('comment_count', 0),
            "like": collection_data.get('like_count', 0),
            "favorite": collection_data.get('follower_count', 0),
            "item_count": collection_data.get('item_count', 0) or collection_data.get('answer_count', 0),
            "follower_count": collection_data.get('follower_count', 0),
        }
        
        created = collection_data.get('created_time')
        published_at = datetime.fromtimestamp(created) if created else datetime.now()
        
        return ParsedContent(
            platform="zhihu",
            content_type="collection",
            content_id=str(collection_id),
            clean_url=url.split('?')[0],
            layout_type=LAYOUT_GALLERY,  # 收藏夹为Gallery布局
            title=f"收藏夹：{title}" if title else f"知乎收藏夹 {collection_id}",
            body=description,
            author_name=creator_name,
            author_id=creator_id,
            author_avatar_url=creator_avatar,
            author_url=f"https://www.zhihu.com/people/{creator_id}" if creator_id else None,
            cover_url=creator_avatar,
            media_urls=[],
            published_at=published_at,
            stats=stats,
            archive_metadata={"raw_api_response": data}
        )

    def _build_archive(self, content_type: str, title: str, processed_html: str, 
                       markdown: str, media_urls: list, avatar_url: Optional[str] = None) -> Dict:
        """构建归档数据"""
        archive_images = [{"url": u} for u in media_urls]
        if avatar_url:
            archive_images.append({"url": avatar_url, "type": "avatar"})
        
        return {
            "version": 2,
            "type": content_type,
            "title": title,
            "plain_text": BeautifulSoup(processed_html, 'html.parser').get_text("\n"),
            "markdown": markdown,
            "images": archive_images,
            "links": [],
            "stored_images": []
        }

    # ==================== 主解析方法 ====================

    async def parse(self, url: str) -> ParsedContent:
        content_type = await self.detect_content_type(url)
        if not content_type:
            raise NonRetryableAdapterError(f"不支持的知乎 URL: {url}")

        clean_url = await self.clean_url(url)
        content_id = self._extract_id_from_url(url, content_type)
        
        # 解析策略：API优先
        # Answer/User/Column/Collection: 公开API，优先使用
        # Article: 带cookie时API可用，先试API再回退HTML
        # Question: 带cookie时API成功率较高，先试API再回退HTML
        # Pin: 仅支持HTML
        
        api_preferred_types = {"answer", "user_profile", "column", "collection", "article", "question"}
        
        if content_id and content_type in api_preferred_types:
            api_parsers = {
                "answer": self._parse_answer_via_api,
                "user_profile": self._parse_user_via_api,
                "column": self._parse_column_via_api,
                "collection": self._parse_collection_via_api,
                "article": self._parse_article_via_api,
                "question": self._parse_question_via_api,
            }
            
            logger.info(f"尝试通过API解析 {content_type}: {content_id}")
            result = await api_parsers[content_type](content_id, url)
            if result:
                logger.info(f"API解析成功: {content_type}/{content_id}")
                self._log_parse_success(channel="api", parsed=result)
                return result
            logger.info(f"API解析失败，回退到HTML解析: {content_type}/{content_id}")
        elif content_type == "pin":
            logger.info(f"Pin 类型仅支持HTML解析: {content_id}")
        
        # HTML解析回退
        html_result = await self._parse_via_html(url, clean_url, content_type)
        self._log_parse_success(channel="html", parsed=html_result)
        return html_result

    async def _parse_via_html(self, url: str, clean_url: str, content_type: str) -> ParsedContent:
        """通过HTML页面解析"""
        proxy_url = await self._get_proxy_url()
        headers = self._make_html_headers(clean_url)
        request_cookies = self.cookies
        if self.raw_cookie_str:
            headers["cookie"] = normalize_cookie_header_value(
                self.raw_cookie_str,
                ensure_outer_quotes=True,
            )
            request_cookies = None

        async with httpx.AsyncClient(
            headers=headers,
            cookies=request_cookies,
            follow_redirects=True,
            timeout=15.0,
            proxy=proxy_url
        ) as client:
            try:
                logger.info(f"[zhihu debug] cookies count={len(self.cookies)}, keys={list(self.cookies.keys())[:5]}")
                response = await client.get(clean_url)
                logger.info(f"[zhihu debug] status={response.status_code}, url={response.url}, resp_head={response.text[:300]}")
                if response.status_code == 404:
                    raise NonRetryableAdapterError(f"内容不存在: {url}")
                if response.status_code in (401, 403):
                    risk_code, risk_message = self._extract_zhihu_error(response)
                    logger.bind(
                        event="zhihu_risk_blocked",
                        stage="html",
                        content_type=content_type,
                        status_code=response.status_code,
                        zhihu_error_code=risk_code,
                        target_url=clean_url,
                    ).warning(
                        "Zhihu HTML blocked: status={} code={} msg={}",
                        response.status_code,
                        risk_code,
                        (risk_message or response.text[:180]),
                    )
                    err_msg = "触发知乎安全验证" if "安全验证" in response.text else "访问知乎需要登录或权限不足"
                    
                    if getattr(self, "_refresh_zse_called", False):
                        raise AuthRequiredAdapterError(f"{err_msg} (已尝试更新指纹)")
                    
                    logger.warning(f"[Zhihu] 碰到 403/401 拦截 ({err_msg})，尝试启动服务端自动更新指纹...")
                    try:
                        from app.services.browser_auth_service import browser_auth_service
                        success = await browser_auth_service.refresh_zhihu_zse_cookie(clean_url)
                        if success:
                            self._refresh_zse_called = True
                            raise RetryableAdapterError(f"{err_msg}，后台已成功提取新指纹，准备重试当前页面")
                        else:
                            logger.warning("[Zhihu] 自动更新指纹失败，可能登录状态已过期")
                    except Exception as e:
                        if isinstance(e, RetryableAdapterError):
                            raise
                        logger.error(f"[Zhihu] 调用指纹更新器异常: {e}")
                    
                    raise AuthRequiredAdapterError(err_msg)
                if response.status_code != 200:
                    raise RetryableAdapterError(f"知乎请求失败: {response.status_code}")
                
                html = response.text
                
                html_parsers = {
                    "article": parse_article,
                    "question": parse_question,
                    "answer": parse_answer,
                    "pin": parse_pin,
                    "user_profile": parse_people,
                }
                
                parser = html_parsers.get(content_type)
                if not parser:
                    raise NonRetryableAdapterError(f"不支持的内容类型: {content_type}")
                
                parsed_content = parser(html, clean_url)

                if not parsed_content:
                    if "登录" in html or "验证" in html:
                        raise AuthRequiredAdapterError("可能需要更新 Cookie")
                    raise NonRetryableAdapterError(f"解析失败，未找到数据: {url}")
                
                return parsed_content

            except httpx.RequestError as e:
                raise RetryableAdapterError(f"网络请求错误: {e}")

    def map_stats_to_content(self, content, parsed: ParsedContent) -> None:
        """知乎统计字段映射"""
        stats = parsed.stats or {}

        if parsed.content_type == "user_profile":
            content.view_count = self._to_int(stats.get("follower_count", 0))
            content.share_count = self._to_int(stats.get("following_count", 0))
            content.like_count = self._to_int(stats.get("voteup_count", 0))
            content.collect_count = self._to_int(stats.get("favorited_count", 0))
            content.comment_count = self._to_int(stats.get("reply", 0))
            content.extra_stats = {
                "follower_count": self._to_int(stats.get("follower_count", 0)),
                "following_count": self._to_int(stats.get("following_count", 0)),
                "voteup_count": self._to_int(stats.get("voteup_count", 0)),
                "thanked_count": self._to_int(stats.get("thanked_count", 0)),
                "favorited_count": self._to_int(stats.get("favorited_count", 0)),
                "favorite_count": self._to_int(stats.get("favorite_count", 0)),  # 用户自己收藏数
                "answer_count": self._to_int(stats.get("answer_count", 0)),
                "articles_count": self._to_int(stats.get("articles_count", 0)),
                "pins_count": self._to_int(stats.get("pins_count", 0)),
                "question_count": self._to_int(stats.get("question_count", 0)),
            }
            return

        self.map_common_stats(content, stats)
        content.extra_stats = {
            "voteup_count": self._to_int(stats.get("voteup_count", 0)),
            "thanks_count": self._to_int(stats.get("thanks_count", 0)),
            "follower_count": self._to_int(stats.get("follower_count", 0)),
        }

        if parsed.content_type == "question":
            content.collect_count = self._to_int(stats.get("follower_count", content.collect_count))
            content.view_count = self._to_int(stats.get("visit_count", content.view_count))
            content.comment_count = self._to_int(stats.get("answer_count", content.comment_count))
        elif parsed.content_type == "pin":
            content.collect_count = self._to_int(stats.get("favorite", 0))
            content.share_count = self._to_int(stats.get("share", 0))
        elif parsed.content_type == "article":
            content.collect_count = self._to_int(stats.get("favorited_count", 0))
