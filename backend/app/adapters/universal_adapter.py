"通用适配器 (Universal Adapter) - Agentic V2

使用探测、语义定标与本地提取的三阶段架构：
1. 探测阶段：使用 Crawl4AI 下载页面并提取原始 HTML 与元数据。
2. 定标阶段：提取 DOM 结构概览，利用轻量级 LLM 识别正文容器选择器。
3. 提取阶段：在本地利用锁定容器进行 Markdown 转换，补全路径并合并元数据。
"
import os
import sys
import json
import asyncio
import hashlib
import re
import concurrent.futures
from typing import Optional, Dict, Any, List
from urllib.parse import urljoin
from loguru import logger
from bs4 import BeautifulSoup

from crawl4ai import AsyncWebCrawler, BrowserConfig, CrawlerRunConfig, CacheMode
from crawl4ai.markdown_generation_strategy import DefaultMarkdownGenerator

from app.adapters.base import PlatformAdapter, ParsedContent, LAYOUT_ARTICLE, LAYOUT_VIDEO, LAYOUT_GALLERY, LAYOUT_AUDIO
from app.adapters.errors import RetryableAdapterError
from app.core.llm_factory import LLMFactory
from app.core.crawler_config import get_delay_for_url_sync


# LLM 提取提示词
TARGETING_PROMPT = """
Identify the SINGLE best CSS selector that contains the main article/content body.
Exclude navigation, sidebars, ads, and comment sections.

URL: {url}
HTML Structure Summary (IDs and Classes):
{html_summary}

Return ONLY the CSS selector (e.g., \"#article-content\" or \"div.post-body\"). If unsure, return \"body\".
Selector:"""

METADATA_PROMPT = """
Analyze the content and extract metadata. Return valid JSON only.
Schema:
{{
  "title": "string",
  "author": "string",
  "summary": "string (2-3 sentences)",
  "publish_date": "YYYY-MM-DD HH:MM",
  "tags": ["string"],
  "cover_image_url": "string"
}}

Content Snippet:
{content_snippet}
"""

def _run_crawl_in_process(url: str, cookies: dict, llm_config: dict, user_data_dir: str, max_retries: int) -> ParsedContent:
    """在独立进程中运行爬取（Windows 兼容）"""
    if sys.platform == 'win32':
        asyncio.set_event_loop_policy(asyncio.WindowsProactorEventLoopPolicy())
    
    loop = asyncio.new_event_loop()
    asyncio.set_event_loop(loop)
    try:
        adapter = UniversalAdapter(cookies=cookies)
        adapter.llm_config = llm_config
        adapter.user_data_dir = user_data_dir
        adapter.max_retries = max_retries
        return loop.run_until_complete(adapter._do_parse(url))
    finally:
        loop.close()


def infer_layout_type(metadata: dict, content: str, media_urls: list) -> str:
    """推断布局类型"""
    # 规则优先
    if metadata.get("video_url"): return LAYOUT_VIDEO
    if metadata.get("audio_url"): return LAYOUT_AUDIO
    
    content_len = len(content or "")
    num_images = len(media_urls)
    
    if num_images >= 2 and content_len < 800:
        return LAYOUT_GALLERY
    
    return LAYOUT_ARTICLE


class UniversalAdapter(PlatformAdapter):
    def __init__(self, **kwargs):
        self.cookies = kwargs.get("cookies", {})
        self.llm_config = LLMFactory.get_crawl4ai_config("text")
        self.user_data_dir = os.getenv("CHROME_USER_DATA_DIR")
        self.max_retries = 2
        
        # 预配置 Markdown 生成器
        self.md_generator = DefaultMarkdownGenerator(
            options={
                "ignore_images": False,
                "escape_html": True,
                "skip_internal_links": True,
                "body_width": 0
            }
        )

    async def detect_content_type(self, url: str) -> Optional[str]:
        return "webpage"

    async def clean_url(self, url: str) -> str:
        return url

    async def parse(self, url: str) -> ParsedContent:
        if sys.platform == 'win32':
            return await self._parse_in_thread(url)
        else:
            return await self._do_parse(url)
    
    async def _parse_in_thread(self, url: str) -> ParsedContent:
        loop = asyncio.get_event_loop()
        with concurrent.futures.ProcessPoolExecutor(max_workers=1) as executor:
            return await loop.run_in_executor(
                executor, 
                _run_crawl_in_process, 
                url, 
                self.cookies, 
                self.llm_config, 
                self.user_data_dir,
                self.max_retries
            )

    def _fix_links(self, md_text: str, base_url: str) -> str:
        """补全 Markdown 中的所有相对链接"""
        if not md_text: return ""
        
        # 1. 修复图片 ![alt](url)
        def img_repl(m):
            alt, url = m.group(1), m.group(2)
            return f"![{alt}]({urljoin(base_url, url)})"
        md_text = re.sub(r"!\\\[(.*?)\\\]\((.*?)\")", img_repl, md_text)
        
        # 2. 修复普通链接 [text](url)
        def link_repl(m):
            text, url = m.group(1), m.group(2)
            return f"[{text}]({urljoin(base_url, url)})"
        md_text = re.sub(r"(?<!!)\\\\[(.*?)\\\]\((.*?)\")", link_repl, md_text)
        
        return md_text

    def _cleanup_markdown(self, md_text: str) -> str:
        """清理冗余字符和空行"""
        if not md_text: return ""
        # 移除标题末尾锚点 #
        md_text = re.sub(r'^(#+ .*?)#\s*$', r'\1', md_text, flags=re.MULTILINE)
        # 移除过多的连续空行
        md_text = re.sub(r'\n{3,}', '\n\n', md_text)
        return md_text.strip()

    async def _get_target_selector(self, url: str, html: str) -> str:
        """利用 LLM 识别正文容器选择器"""
        if not self.llm_config: return "body"
        
        soup = BeautifulSoup(html, 'html.parser')
        containers = []
        for t in soup.find_all(['div', 'article', 'section', 'main'], limit=150):
            tid, tcls = t.get('id', ''), " ".join(t.get('class', []))
            if tid or tcls:
                preview = t.get_text(strip=True)[:25].replace('\n', ' ')
                containers.append(f"<{t.name} id='{tid}' class='{tcls}'> (preview: {preview})")
        
        from langchain_openai import ChatOpenAI
        llm = ChatOpenAI(
            model=self.llm_config["provider"].split("/")[-1],
            api_key=self.llm_config["api_token"],
            base_url=self.llm_config["base_url"],
            temperature=0
        )
        
        prompt = TARGETING_PROMPT.format(url=url, html_summary="\n".join(containers))
        try:
            res = await llm.ainvoke(prompt)
            selector = res.content.strip().strip('`').strip('"')
            return selector if selector else "body"
        except Exception as e:
            logger.warning(f"UniversalAdapter: Targeting failed: {e}")
            return "body"

    async def _refine_metadata(self, content: str, initial_meta: dict) -> dict:
        """利用 LLM 精炼文章元数据"""
        if not self.llm_config: return initial_meta
        
        from langchain_openai import ChatOpenAI
        llm = ChatOpenAI(
            model=self.llm_config["provider"].split("/")[-1],
            api_key=self.llm_config["api_token"],
            base_url=self.llm_config["base_url"],
            temperature=0.1
        )
        
        prompt = METADATA_PROMPT.format(content_snippet=content[:4000])
        try:
            res = await llm.ainvoke(prompt)
            match = re.search(r'\{.*\}', res.content, re.DOTALL)
            if match:
                llm_meta = json.loads(match.group())
                initial_meta.update({k: v for k, v in llm_meta.items() if v})
        except: pass
        return initial_meta

    async def _do_parse(self, url: str) -> ParsedContent:
        """核心解析流程"""
        
        # 1. 唯一的一次下载
        delay = get_delay_for_url_sync(url)
        browser_config = BrowserConfig(
            headless=True,
            user_agent="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36",
            user_data_dir=self.user_data_dir
        )
        run_config = CrawlerRunConfig(
            cache_mode=CacheMode.ENABLED,
            wait_until="domcontentloaded",
            delay_before_return_html=delay + 3.0, # 额外宽限以支持 Pjax
            magic=True
        )

        async with AsyncWebCrawler(config=browser_config) as crawler:
            result = await crawler.arun(url=url, config=run_config)
            if not result.success:
                raise RetryableAdapterError(f"Crawl failed: {result.error_message}")

            # 2. 定标：识别正文容器
            logger.debug(f"UniversalAdapter: Identifying content container for {url}")
            selector = await self._get_target_selector(url, result.html)
            logger.info(f"UniversalAdapter: Targeted selector: {selector}")

            # 3. 提取：本地精准转换
            soup = BeautifulSoup(result.html, 'html.parser')
            try:
                target_node = soup.select_one(selector) if selector != "body" else None
                if not target_node: target_node = soup.body
                
                local_md = self.md_generator.generate_markdown(str(target_node))
                description = local_md.raw_markdown if hasattr(local_md, 'raw_markdown') else str(local_md)
            except Exception as e:
                logger.warning(f"UniversalAdapter: Local conversion failed: {e}")
                description = result.markdown.fit_markdown or result.markdown.raw_markdown

            # 4. 后处理：修复路径与清理
            description = self._cleanup_markdown(self._fix_links(description, url))
            images = [urljoin(url, img) for img in re.findall(r'!\\[.*?\\]\((.*?)\\)`, description)]

            # 5. 元数据合并
            og = result.metadata.get("opengraph", {})
            json_ld = result.metadata.get("jsonld", [])
            if isinstance(json_ld, list) and json_ld: json_ld = json_ld[0]
            elif not isinstance(json_ld, dict): json_ld = {}

            meta = {
                "title": og.get("og:title") or result.metadata.get("title") or "Untitled",
                "author": json_ld.get("author", {}).get("name") if isinstance(json_ld.get("author"), dict) else None,
                "publish_date": json_ld.get("datePublished") or og.get("article:published_time"),
                "cover_image_url": og.get("og:image"),
                "summary": og.get("og:description"),
                "tags": []
            }
            
            # 精炼
            meta = await self._refine_metadata(description, meta)
            
            # 构建 ParsedContent
            layout_type = infer_layout_type({"video_url": og.get("og:video")}, description, images)
            cover_url = urljoin(url, meta.get("cover_image_url") or (images[0] if images else ""))

            # 构建 archive 供 worker 下载图片
            archive = {
                "markdown": description,
                "images": [{"url": img} for img in images],
                "videos": [],
                "llm_selector": selector
            }

            return ParsedContent(
                platform="universal",
                content_type="webpage",
                content_id=hashlib.md5(url.encode()).hexdigest(),
                clean_url=url,
                layout_type=layout_type,
                title=meta.get("title"),
                description=description,
                author_name=meta.get("author"),
                cover_url=cover_url,
                media_urls=images,
                source_tags=meta.get("tags", []),
                stats={
                    "view_count": 0, "like_count": 0, "comment_count": 0, "share_count": 0
                },
                raw_metadata={
                    "summary": meta.get("summary"),
                    "publish_date": meta.get("publish_date"),
                    "archive": archive
                }
            )