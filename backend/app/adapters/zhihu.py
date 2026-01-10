import re
import json
import logging
import requests
from typing import Optional, List, Dict, Any
from app.adapters.base import PlatformAdapter, ParsedContent
from app.adapters.errors import NonRetryableAdapterError, RetryableAdapterError
from app.config import settings
from datetime import datetime

logger = logging.getLogger(__name__)

class ZhihuAdapter(PlatformAdapter):
    """
    知乎内容解析适配器
    
    支持:
    - 回答: https://www.zhihu.com/question/123/answer/456
    - 文章: https://zhuanlan.zhihu.com/p/123
    - 问题: https://www.zhihu.com/question/123 (仅提取问题本身)
    
    依赖:
    - settings.zhihu_cookie (可选，但推荐以获取完整内容)
    """
    
    # URL Patterns
    ANSWER_PATTERN = re.compile(r"zhihu\.com/question/(\d+)/answer/(\d+)")
    ARTICLE_PATTERN = re.compile(r"zhuanlan\.zhihu\.com/p/(\d+)")
    QUESTION_PATTERN = re.compile(r"zhihu\.com/question/(\d+)$") # 必须结尾，避免匹配到 answer

    async def detect_content_type(self, url: str) -> Optional[str]:
        if self.ANSWER_PATTERN.search(url):
            return "answer"
        if self.ARTICLE_PATTERN.search(url):
            return "article"
        if self.QUESTION_PATTERN.search(url):
            return "question"
        return None

    async def clean_url(self, url: str) -> str:
        # 移除参数
        base = url.split("?")[0]
        return base

    async def parse(self, url: str) -> ParsedContent:
        cookie = settings.zhihu_cookie.get_secret_value() if settings.zhihu_cookie else None
        
        headers = {
            "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36",
            "Referer": "https://www.zhihu.com/",
        }
        if cookie:
            headers["Cookie"] = cookie

        try:
            response = requests.get(url, headers=headers, timeout=10)
            if response.status_code == 404:
                raise NonRetryableAdapterError(f"Content not found: {url}")
            if response.status_code != 200:
                raise RetryableAdapterError(f"Failed to fetch page: {response.status_code}")
            
            html = response.text
            
            # 提取 js-initialData
            data_match = re.search(r'<script id="js-initialData" type="text/json">(.*?)</script>', html, re.DOTALL)
            if not data_match:
                # 尝试旧版
                data_match = re.search(r"window\.initialState\s*=\s*({.*?});", html, re.DOTALL)
            
            if not data_match:
                if "security_verification" in response.url:
                     raise RetryableAdapterError("Triggered Zhihu security check. Please update cookie.")
                raise NonRetryableAdapterError("Failed to extract initial data from Zhihu page")
            
            json_str = data_match.group(1)
            try:
                data = json.loads(json_str)
            except json.JSONDecodeError:
                raise NonRetryableAdapterError("Failed to decode Zhihu JSON")
            
            # initialData.initialState -> entities -> ...
            initial_state = data.get("initialState", {})
            entities = initial_state.get("entities", {})
            
            content_type = await self.detect_content_type(url)
            
            if content_type == "answer":
                return self._parse_answer(url, entities)
            elif content_type == "article":
                return self._parse_article(url, entities)
            elif content_type == "question":
                return self._parse_question(url, entities)
            else:
                raise NonRetryableAdapterError("Unknown content type")

        except requests.RequestException as e:
            raise RetryableAdapterError(f"Network error: {str(e)}")
        except Exception as e:
            logger.exception("Error parsing Zhihu content")
            raise NonRetryableAdapterError(f"Unexpected error: {str(e)}")

    def _parse_answer(self, url, entities):
        match = self.ANSWER_PATTERN.search(url)
        answer_id = match.group(2)
        question_id = match.group(1)
        
        answers = entities.get("answers", {})
        answer_data = answers.get(answer_id)
        
        if not answer_data:
            # 有时 ID 是 int
            answer_data = answers.get(int(answer_id))
            
        if not answer_data:
             raise NonRetryableAdapterError(f"Answer data {answer_id} not found in state")
             
        # 获取关联的问题标题
        questions = entities.get("questions", {})
        question_data = questions.get(question_id) or questions.get(int(question_id))
        question_title = question_data.get("title", "") if question_data else ""
        
        author = answer_data.get("author", {})
        content_html = answer_data.get("content", "")
        excerpt = answer_data.get("excerpt", "")
        
        # 提取图片
        media_urls = self._extract_images_from_html(content_html)
        cover_url = media_urls[0] if media_urls else ""
        
        # 统计
        voteup_count = answer_data.get("voteupCount", 0)
        comment_count = answer_data.get("commentCount", 0)
        
        created_time = answer_data.get("createdTime")
        published_at = datetime.fromtimestamp(created_time) if created_time else None
        
        return ParsedContent(
            platform="zhihu",
            title=question_title or excerpt[:50],  # 回答通常用问题标题
            description=excerpt,
            author_name=author.get("name", "Unknown"),
            author_id=author.get("id", ""),
            cover_url=cover_url,
            media_urls=media_urls,
            platform_id=answer_id,
            content_type="answer",
            published_at=published_at,
            tags=[], 
            raw_metadata=answer_data,
            extra_stats={
                "voteup_count": voteup_count,
                "comment_count": comment_count
            }
        )

    def _parse_article(self, url, entities):
        match = self.ARTICLE_PATTERN.search(url)
        article_id = match.group(1)
        
        articles = entities.get("articles", {})
        article_data = articles.get(article_id) or articles.get(int(article_id))
        
        if not article_data:
             raise NonRetryableAdapterError(f"Article data {article_id} not found in state")
             
        title = article_data.get("title", "")
        content_html = article_data.get("content", "")
        excerpt = article_data.get("excerpt", "")
        author = article_data.get("author", {})
        
        media_urls = self._extract_images_from_html(content_html)
        cover_url = article_data.get("imageUrl", "") or (media_urls[0] if media_urls else "")
        
        voteup_count = article_data.get("voteupCount", 0)
        comment_count = article_data.get("commentCount", 0)
        
        created_time = article_data.get("created")
        published_at = datetime.fromtimestamp(created_time) if created_time else None
        
        return ParsedContent(
            platform="zhihu",
            title=title,
            description=excerpt,
            author_name=author.get("name", "Unknown"),
            author_id=author.get("id", ""),
            cover_url=cover_url,
            media_urls=media_urls,
            platform_id=article_id,
            content_type="article",
            published_at=published_at,
            tags=[],
            raw_metadata=article_data,
            extra_stats={
                "voteup_count": voteup_count,
                "comment_count": comment_count
            }
        )

    def _parse_question(self, url, entities):
        match = self.QUESTION_PATTERN.search(url)
        qid = match.group(1)
        questions = entities.get("questions", {})
        q_data = questions.get(qid) or questions.get(int(qid))
        
        if not q_data:
            raise NonRetryableAdapterError(f"Question data {qid} not found")
            
        title = q_data.get("title", "")
        detail = q_data.get("detail", "") # HTML
        
        media_urls = self._extract_images_from_html(detail)
        
        created_time = q_data.get("created")
        published_at = datetime.fromtimestamp(created_time) if created_time else None
        
        return ParsedContent(
            platform="zhihu",
            title=title,
            description=detail[:200], # 简略
            author_name="Unknown", # 问题通常不强调作者
            author_id="",
            cover_url="",
            media_urls=media_urls,
            platform_id=qid,
            content_type="question",
            published_at=published_at,
            tags=[t.get("name") for t in q_data.get("topics", [])],
            raw_metadata=q_data,
            extra_stats={}
        )

    def _extract_images_from_html(self, html_content: str) -> List[str]:
        # 简单提取 data-original 或 src
        # 知乎通常用 data-original 存高清图
        if not html_content:
            return []
        imgs = re.findall(r'data-original="([^"]+)"', html_content)
        if not imgs:
             imgs = re.findall(r'src="([^"]+)"', html_content)
        # 过滤掉头像等小图? 暂时全留
        return list(set(imgs))