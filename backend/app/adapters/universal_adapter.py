import os
import json
import asyncio
import hashlib
from typing import Optional, Dict, Any, List
from loguru import logger

from crawl4ai import AsyncWebCrawler, BrowserConfig, CrawlerRunConfig, CacheMode
from crawl4ai.extraction_strategy import LLMExtractionStrategy

from app.adapters.base import PlatformAdapter, ParsedContent
from app.adapters.errors import RetryableAdapterError
from app.core.llm_factory import LLMFactory

# 增强的数据提取 Schema，包含互动数据
EXTENDED_SCHEMA = {
    "type": "object",
    "properties": {
        "title": {"type": "string", "description": "The main title of the article or post."},
        "author": {"type": "string", "description": "Name of the author or publisher."},
        "content": {"type": "string", "description": "The full text content, cleaned of navigation and ads."},
        "summary": {"type": "string", "description": "A concise summary of the content (2-3 sentences)."},
        "publish_date": {"type": "string", "description": "Publication date if available (YYYY-MM-DD HH:MM format preferred)."},
        "tags": {"type": "array", "items": {"type": "string"}, "description": "Relevant topics or tags."},
        "images": {"type": "array", "items": {"type": "string"}, "description": "List of main content image URLs."},
        # 新增互动统计字段
        "metrics": {
            "type": "object",
            "properties": {
                "view_count": {"type": "integer", "description": "Number of views/reads."},
                "like_count": {"type": "integer", "description": "Number of likes/hearts."},
                "comment_count": {"type": "integer", "description": "Number of comments/replies."},
                "share_count": {"type": "integer", "description": "Number of shares/retweets."}
            }
        }
    },
    "required": ["title", "content"]
}

class UniversalAdapter(PlatformAdapter):
    """
    通用适配器 (Universal Adapter)
    
    使用 Crawl4AI + LLM (Text Model) 对未适配的 URL 进行智能解析。
    支持重试机制和丰富的元数据提取。
    """

    def __init__(self):
        self.llm_config = LLMFactory.get_crawl4ai_config("text")
        self.user_data_dir = os.getenv("CHROME_USER_DATA_DIR")
        self.max_retries = 3
        
        if not self.llm_config:
            logger.warning("UniversalAdapter: No valid LLM configuration found. Extraction will degrade to raw Markdown.")

    async def detect_content_type(self, url: str) -> Optional[str]:
        return "webpage"

    async def clean_url(self, url: str) -> str:
        return url

    async def parse(self, url: str) -> ParsedContent:
        """
        解析任意 URL 并返回结构化数据。
        """
        logger.info(f"UniversalAdapter: Starting smart crawl for {url}")
        
        # 配置浏览器
        headless = True
        if self.user_data_dir and os.path.exists(self.user_data_dir):
            headless = False 
            logger.info(f"UniversalAdapter: Using local Chrome profile at {self.user_data_dir}")

        browser_config = BrowserConfig(
            headless=headless,
            verbose=True,
            user_data_dir=self.user_data_dir if self.user_data_dir else None,
        )

        # 准备 LLM 策略 (如果配置了)
        extraction_strategy = None
        if self.llm_config:
            extraction_strategy = LLMExtractionStrategy(
                provider=self.llm_config.get("provider"),
                api_token=self.llm_config.get("api_token"),
                base_url=self.llm_config.get("base_url"),
                schema=EXTENDED_SCHEMA,
                extraction_type="schema",
                instruction="""
                Analyze the web page content. 
                1. Extract the main article/post content, ignoring navigation, sidebars, ads, and footers.
                2. Extract metadata like author, publish date, and tags.
                3. CRITICAL: Look for interaction metrics (views, likes, comments, shares) usually found at the top or bottom of the post.
                4. Keep the 'content' field in clean Markdown format.
                """
            )

        run_config = CrawlerRunConfig(
            cache_mode=CacheMode.BYPASS,
            wait_for="body",
            delay_before_return_html=3.0,
            extraction_strategy=extraction_strategy,
            magic=True,
        )

        last_exception = None
        
        # --- 重试循环 ---
        for attempt in range(self.max_retries):
            try:
                if attempt > 0:
                    logger.info(f"UniversalAdapter: Retry attempt {attempt + 1}/{self.max_retries} for {url}...")
                    # 可以在这里增加指数退避
                    await asyncio.sleep(2 * attempt)

                async with AsyncWebCrawler(config=browser_config) as crawler:
                    result = await crawler.arun(url=url, config=run_config)

                    if not result.success:
                        raise Exception(f"Crawl failed: {result.error_message}")

                    # 尝试解析 LLM 结果
                    data = {}
                    llm_success = False
                    
                    if extraction_strategy and result.extracted_content:
                        try:
                            data = json.loads(result.extracted_content)
                            llm_success = True
                        except json.JSONDecodeError:
                            logger.warning(f"UniversalAdapter: LLM returned invalid JSON on attempt {attempt+1}. Raw: {result.extracted_content[:200]}...")
                            # 如果 JSON 解析失败，这算作一次失败，触发重试
                            raise Exception("LLM JSON Decode Error")

                    # 如果成功获取结构化数据，或者没有配置 LLM (直接用 Markdown)，则退出循环
                    # 映射 metrics
                    metrics = data.get("metrics", {})
                    
                    return ParsedContent(
                        platform="universal",
                        content_type="webpage",
                        content_id=hashlib.md5(url.encode()).hexdigest(),
                        clean_url=url,
                        title=data.get("title") or "Untitled",
                        description=data.get("content") or result.markdown,
                        author_name=data.get("author"),
                        media_urls=data.get("images", []),
                        source_tags=data.get("tags", []),
                        stats={
                            "view_count": metrics.get("view_count", 0),
                            "like_count": metrics.get("like_count", 0),
                            "comment_count": metrics.get("comment_count", 0),
                            "share_count": metrics.get("share_count", 0),
                        },
                        raw_metadata={
                            "llm_extracted": llm_success,
                            "summary": data.get("summary"),
                            "publish_date": data.get("publish_date"),
                            "crawl_attempt": attempt + 1,
                            "original_result": {
                                "status_code": result.status_code,
                                "markdown_len": len(result.markdown)
                            }
                        }
                    )

            except Exception as e:
                logger.error(f"UniversalAdapter: Error on attempt {attempt + 1} - {str(e)}")
                last_exception = e
                # 继续下一次循环

        # 如果重试耗尽，抛出异常以便 Worker 处理
        logger.error(f"UniversalAdapter: All {self.max_retries} attempts failed for {url}.")
        raise RetryableAdapterError(
            f"Failed to parse content after {self.max_retries} attempts.",
            details={"last_error": str(last_exception)}
        )