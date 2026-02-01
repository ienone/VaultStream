"""
通用适配器 (Universal Adapter)

使用 Crawl4AI 爬取 + LLM 元数据提取的两阶段架构：
1. 第一阶段：使用 Crawl4AI 获取页面 Markdown 内容和图片
2. 第二阶段：使用 LLM 从 Markdown 中提取元数据（标题、作者、日期、互动数据等）

这种分离架构的优势：
- 正文内容稳定可靠（直接从 HTML 转换）
- LLM 仅处理元数据提取，成本低、速度快
- 即使 LLM 失败，仍有完整的正文内容
"""
import os
import sys
import json
import asyncio
import hashlib
import re
import concurrent.futures
from typing import Optional, Dict, Any, List
from loguru import logger

from crawl4ai import AsyncWebCrawler, BrowserConfig, CrawlerRunConfig, CacheMode
from crawl4ai.markdown_generation_strategy import DefaultMarkdownGenerator
from crawl4ai.content_filter_strategy import PruningContentFilter

from app.adapters.base import PlatformAdapter, ParsedContent, LAYOUT_ARTICLE, LAYOUT_VIDEO, LAYOUT_GALLERY, LAYOUT_AUDIO
from app.adapters.errors import RetryableAdapterError
from app.core.llm_factory import LLMFactory
from app.core.crawler_config import get_delay_for_url_sync


# LLM 元数据提取 Schema（不包含正文，正文从 Markdown 获取）
METADATA_SCHEMA = {
    "type": "object",
    "properties": {
        "title": {"type": "string", "description": "The main title of the article or post."},
        "author": {"type": "string", "description": "Name of the author or publisher."},
        "summary": {"type": "string", "description": "A concise summary of the content (2-3 sentences)."},
        "publish_date": {"type": "string", "description": "Publication date if available (YYYY-MM-DD HH:MM format preferred)."},
        "tags": {"type": "array", "items": {"type": "string"}, "description": "Relevant topics or tags."},
        "video_url": {"type": "string", "description": "URL of main video content if present."},
        "audio_url": {"type": "string", "description": "URL of main audio/podcast if present."},
        "cover_image_url": {"type": "string", "description": "URL of the most representative image (cover/hero image)."},
        "detected_type": {
            "type": "string",
            "enum": ["article", "video", "gallery", "audio"],
            "description": "Detected content type."
        },
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
    "required": ["title"]
}

# LLM 提取提示词
EXTRACTION_PROMPT = """
Analyze the web page content and extract metadata.

IMPORTANT:
1. Extract the title, author, and publish date if visible.
2. Look for interaction metrics (views, likes, comments, shares) - often found near the post header or footer.
3. Generate a brief 2-3 sentence summary of the main content.
4. Detect the content type based on what the page primarily shows.
5. Extract relevant tags or topics.
6. If there's a main video or audio element, extract its URL.
7. Identify the most suitable cover image URL.

Do NOT extract the full content text - only metadata.
Return valid JSON matching the schema.
"""

# 爬取配置常量
EXCLUDED_TAGS = [
    "nav", "header", "footer", "aside",
    "form", "iframe", "noscript", "script", "style",
    "svg", "canvas",
]

EXCLUDED_SELECTOR = ",".join([
    ".navbar", ".nav", ".navigation", ".menu", ".breadcrumb",
    "[role='navigation']", "[role='banner']",
    ".sidebar", ".toc", ".table-of-contents",
    ".header", ".footer", "[role='contentinfo']",
    ".comments", ".comment-section", ".social-share", ".share-buttons",
    ".ad", ".ads", ".advertisement", ".advert",
    ".widget", ".popup", ".modal", ".cookie-notice",
    ".subscribe", ".newsletter", ".related-posts",
])

EXCLUDED_DOMAINS = [
    "facebook.com", "instagram.com",
    "linkedin.com", "pinterest.com", "tiktok.com",
    "youtube.com", "reddit.com", "discord.com",
]


def _run_crawl_in_process(url: str, cookies: dict, llm_config: dict, user_data_dir: str, max_retries: int, prompt: str) -> ParsedContent:
    """
    在独立进程中运行爬取。
    必须是顶层函数才能被 pickle 序列化。
    """
    if sys.platform == 'win32':
        asyncio.set_event_loop_policy(asyncio.WindowsProactorEventLoopPolicy())
    
    loop = asyncio.new_event_loop()
    asyncio.set_event_loop(loop)
    try:
        adapter = UniversalAdapter(cookies=cookies)
        adapter.llm_config = llm_config
        adapter.user_data_dir = user_data_dir
        adapter.max_retries = max_retries
        adapter._prompt = prompt
        return loop.run_until_complete(adapter._do_parse(url))
    finally:
        loop.close()


def infer_layout_type(metadata: dict, content: str, media_urls: list) -> str:
    """
    推断内容的布局类型
    
    规则优先 + LLM 兜底
    """
    video_url = metadata.get("video_url")
    audio_url = metadata.get("audio_url")
    llm_type = metadata.get("detected_type", "").lower()
    
    # 规则1: 有视频URL
    if video_url and video_url.strip():
        return LAYOUT_VIDEO
    
    # 规则2: 有音频URL
    if audio_url and audio_url.strip():
        return LAYOUT_AUDIO
    
    # 规则3: 图片多且正文短 -> Gallery
    content_len = len(content or "")
    num_images = len(media_urls)
    
    if num_images >= 2 and content_len < 500:
        return LAYOUT_GALLERY
    
    # 规则4: 正文长 -> Article
    if content_len > 1000:
        return LAYOUT_ARTICLE
    
    # 规则5: 参考LLM检测结果
    if llm_type == "video":
        return LAYOUT_VIDEO
    if llm_type == "audio":
        return LAYOUT_AUDIO
    if llm_type == "gallery":
        return LAYOUT_GALLERY
    
    return LAYOUT_ARTICLE


def extract_images_from_markdown(markdown: str) -> list:
    """从 Markdown 中提取图片 URL"""
    return re.findall(r'!\[.*?\]\((.*?)\)', markdown)


class UniversalAdapter(PlatformAdapter):
    """
    通用适配器
    
    两阶段提取架构：
    1. Crawl4AI 爬取 -> Markdown 正文 + 图片列表
    2. LLM 提取 -> 元数据（标题、作者、互动数据等）
    """

    def __init__(self, **kwargs):
        self.cookies = kwargs.get("cookies", {})
        self.llm_config = LLMFactory.get_crawl4ai_config("text")
        self.user_data_dir = os.getenv("CHROME_USER_DATA_DIR")
        self.max_retries = 3
        
        if not self.llm_config:
            logger.warning("UniversalAdapter: No LLM config. Metadata extraction will be skipped.")

    async def detect_content_type(self, url: str) -> Optional[str]:
        return "webpage"

    async def clean_url(self, url: str) -> str:
        return url

    async def parse(self, url: str) -> ParsedContent:
        """解析任意 URL 并返回结构化数据"""
        logger.info(f"UniversalAdapter: Starting crawl for {url}")
        
        # Windows 需要在独立进程中运行
        if sys.platform == 'win32':
            return await self._parse_in_thread(url)
        else:
            return await self._do_parse(url)
    
    async def _parse_in_thread(self, url: str) -> ParsedContent:
        """在独立进程中运行爬取（Windows 兼容）"""
        from app.services.settings_service import get_setting_value
        prompt = await get_setting_value("universal_adapter_prompt", EXTRACTION_PROMPT)
        
        loop = asyncio.get_event_loop()
        with concurrent.futures.ProcessPoolExecutor(max_workers=1) as executor:
            return await loop.run_in_executor(
                executor, 
                _run_crawl_in_process, 
                url, 
                self.cookies, 
                self.llm_config, 
                self.user_data_dir,
                self.max_retries,
                prompt
            )
    
    async def _do_parse(self, url: str) -> ParsedContent:
        """实际的解析逻辑（两阶段提取）"""
        
        # ========== 阶段1: 爬取页面获取 Markdown ==========
        markdown_content, fit_markdown, images, crawl_metadata = await self._crawl_page(url)
        
        if not markdown_content:
            raise RetryableAdapterError(
                "Failed to crawl page content",
                details={"url": url}
            )
        
        # ========== 阶段2: LLM 提取元数据 ==========
        metadata = {}
        if self.llm_config:
            # 使用更干净的 fit_markdown（如果有）
            content_for_llm = fit_markdown if fit_markdown else markdown_content
            metadata = await self._extract_metadata_with_llm(content_for_llm)
        
        # ========== 构建结果 ==========
        # 使用 fit_markdown 作为正文（更干净），fallback 到 raw_markdown
        description = fit_markdown if fit_markdown else markdown_content
        
        # 推断布局类型
        layout_type = infer_layout_type(metadata, description, images)
        
        # 映射 metrics
        metrics = metadata.get("metrics", {})
        
        # 确定封面图
        cover_url = metadata.get("cover_image_url")
        if not cover_url and images:
            # Fallback: 使用第一张图片作为封面
            cover_url = images[0]
        
        # 构建 archive 结构供 worker 下载图片
        archive_images = [{"url": img} for img in images]
        
        # 确保封面图也在下载列表中
        if cover_url and cover_url not in images:
            archive_images.insert(0, {"url": cover_url})

        archive = {
            "markdown": description,
            "images": archive_images,
            "videos": [],
        }

        if metadata.get("video_url"):
             archive["videos"].append({"url": metadata.get("video_url")})
        
        return ParsedContent(
            platform="universal",
            content_type="webpage",
            content_id=hashlib.md5(url.encode()).hexdigest(),
            clean_url=url,
            layout_type=layout_type,
            title=metadata.get("title") or self._extract_title_fallback(markdown_content) or "Untitled",
            description=description,
            author_name=metadata.get("author"),
            cover_url=cover_url,
            media_urls=images,
            source_tags=metadata.get("tags", []),
            stats={
                "view_count": metrics.get("view_count", 0),
                "like_count": metrics.get("like_count", 0),
                "comment_count": metrics.get("comment_count", 0),
                "share_count": metrics.get("share_count", 0),
            },
            raw_metadata={
                "llm_extracted": bool(metadata),
                "summary": metadata.get("summary"),
                "publish_date": metadata.get("publish_date"),
                "detected_type": metadata.get("detected_type"),
                "video_url": metadata.get("video_url"),
                "audio_url": metadata.get("audio_url"),
                "cover_image_url": metadata.get("cover_image_url"),
                "crawl_metadata": crawl_metadata,
                "archive": archive,
            }
        )
    
    async def _crawl_page(self, url: str) -> tuple[str, str, list, dict]:
        """
        阶段1: 爬取页面
        
        Returns:
            (raw_markdown, fit_markdown, images, metadata)
        """
        # 浏览器配置
        headless = True
        if self.user_data_dir and os.path.exists(self.user_data_dir):
            headless = False
            logger.info(f"UniversalAdapter: Using Chrome profile at {self.user_data_dir}")
        
        browser_config = BrowserConfig(
            headless=headless,
            verbose=False,
            user_agent="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36",
            user_data_dir=self.user_data_dir if self.user_data_dir else None,
        )
        
        # 内容过滤器 - 使用固定阈值保证稳定性
        content_filter = PruningContentFilter(
            threshold=0.45,
            threshold_type="fixed",
            min_word_threshold=0,
        )
        
        # Markdown 生成器
        md_generator = DefaultMarkdownGenerator(
            content_filter=content_filter,
            options={
                "ignore_links": False,
                "ignore_images": False,
                "escape_html": True,
                "body_width": 0,
                "skip_internal_links": False,
            }
        )
        
        # 根据 URL 获取等待时间
        delay_time = get_delay_for_url_sync(url)
        logger.debug(f"UniversalAdapter: Using delay {delay_time}s for {url}")
        
        # 爬取配置
        run_config = CrawlerRunConfig(
            cache_mode=CacheMode.BYPASS,
            wait_for="body",
            delay_before_return_html=delay_time,
            
            markdown_generator=md_generator,
            
            word_count_threshold=5,
            excluded_tags=EXCLUDED_TAGS,
            excluded_selector=EXCLUDED_SELECTOR,
            
            exclude_external_links=False,
            exclude_social_media_links=False,
            exclude_domains=EXCLUDED_DOMAINS,
            
            exclude_external_images=False,
            
            process_iframes=False,
            remove_overlay_elements=False,  # 必须禁用！会误删 SPA 页面内容
            magic=True,
        )
        
        last_exception = None
        
        for attempt in range(self.max_retries):
            try:
                if attempt > 0:
                    logger.info(f"UniversalAdapter: Retry {attempt + 1}/{self.max_retries} for {url}")
                    await asyncio.sleep(2 * attempt)
                
                async with AsyncWebCrawler(config=browser_config) as crawler:
                    result = await crawler.arun(url=url, config=run_config)
                    
                    if not result.success:
                        raise Exception(f"Crawl failed: {result.error_message}")
                    
                    # 获取 Markdown
                    if hasattr(result.markdown, 'raw_markdown'):
                        raw_markdown = result.markdown.raw_markdown
                        fit_markdown = result.markdown.fit_markdown
                    else:
                        raw_markdown = str(result.markdown) if result.markdown else ""
                        fit_markdown = None
                    
                    # 提取图片
                    images = extract_images_from_markdown(raw_markdown)
                    
                    metadata = {
                        "status_code": result.status_code,
                        "raw_markdown_len": len(raw_markdown),
                        "fit_markdown_len": len(fit_markdown) if fit_markdown else 0,
                        "image_count": len(images),
                        "crawl_attempt": attempt + 1,
                    }
                    
                    logger.info(f"UniversalAdapter: Crawl success - {len(raw_markdown)} chars, {len(images)} images")
                    
                    return raw_markdown, fit_markdown, images, metadata
                    
            except Exception as e:
                logger.error(f"UniversalAdapter: Crawl error attempt {attempt + 1} - {e}")
                last_exception = e
        
        logger.error(f"UniversalAdapter: All {self.max_retries} crawl attempts failed for {url}")
        raise RetryableAdapterError(
            f"Crawl failed after {self.max_retries} attempts",
            details={"last_error": str(last_exception)}
        )
    
    async def _extract_metadata_with_llm(self, markdown_content: str) -> dict:
        """
        阶段2: 使用 LLM 提取元数据
        """
        from langchain_openai import ChatOpenAI
        
        logger.debug("UniversalAdapter: Starting LLM metadata extraction")
        
        try:
            # 获取提示词
            if hasattr(self, '_prompt') and self._prompt:
                prompt_template = self._prompt
            else:
                from app.services.settings_service import get_setting_value
                prompt_template = await get_setting_value("universal_adapter_prompt", EXTRACTION_PROMPT)
            
            llm = ChatOpenAI(
                model=self.llm_config["provider"].split("/")[-1],
                api_key=self.llm_config["api_token"],
                base_url=self.llm_config["base_url"],
                temperature=0.1,
            )
            
            # 构建提示
            prompt = f"""{prompt_template}

Schema:
```json
{json.dumps(METADATA_SCHEMA, indent=2)}
```

Content to analyze (first 8000 chars):
```
{markdown_content[:8000]}
```

Respond with valid JSON only, no markdown code blocks:"""

            response = await llm.ainvoke(prompt)
            response_text = response.content.strip()
            
            # 清理 JSON
            if response_text.startswith("```"):
                response_text = re.sub(r'^```(?:json)?\n?', '', response_text)
                response_text = re.sub(r'\n?```$', '', response_text)
            
            metadata = json.loads(response_text)
            logger.info(f"UniversalAdapter: LLM extracted metadata - title: {metadata.get('title', 'N/A')[:50]}")
            
            return metadata
            
        except json.JSONDecodeError as e:
            logger.warning(f"UniversalAdapter: LLM JSON parse error - {e}")
            return {}
        except Exception as e:
            logger.warning(f"UniversalAdapter: LLM extraction failed - {e}")
            return {}
    
    def _extract_title_fallback(self, markdown: str) -> Optional[str]:
        """从 Markdown 中尝试提取标题（作为 fallback）"""
        # 查找第一个 # 标题
        match = re.search(r'^#\s+(.+)$', markdown, re.MULTILINE)
        if match:
            return match.group(1).strip()
        
        # 查找第一行非空内容
        for line in markdown.split('\n'):
            line = line.strip()
            if line and not line.startswith('!') and not line.startswith('['):
                return line[:100]
        
        return None
