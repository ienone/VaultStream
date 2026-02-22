# 通用适配器 (Universal Adapter) - Agentic V3 (Tiered Fetch + 2-Layer Agent)

# 架构升级：
# 1. 获取层 (Tiered Fetcher): Cloudflare MD -> Direct HTTP -> Crawl4AI 降级策略
# 2. 解析层 (Content Agent): Layer 1 (结构扫描) -> Layer 2 (元数据提取/清洗)
# 3. 编排层 (Orchestrator): 统一协调获取与解析流程

import os
import sys
import asyncio
import hashlib
import re
import concurrent.futures
from typing import Optional, Dict, Any, List
from urllib.parse import urljoin
from loguru import logger

from app.adapters.base import PlatformAdapter, ParsedContent, LAYOUT_ARTICLE, LAYOUT_VIDEO, LAYOUT_GALLERY, LAYOUT_AUDIO
from app.adapters.errors import RetryableAdapterError
from app.core.llm_factory import LLMFactory
from app.adapters.utils.tiered_fetcher import tiered_fetch
from app.adapters.utils.content_agent import process_content


def _run_crawl_in_process(url: str, cookies: dict, llm_config: dict, user_data_dir: str, max_retries: int, use_magic: bool = False) -> ParsedContent:
    """在独立进程中运行爬取（Windows 兼容）"""
    if sys.platform == 'win32':
        asyncio.set_event_loop_policy(asyncio.WindowsProactorEventLoopPolicy())
    
    loop = asyncio.new_event_loop()
    asyncio.set_event_loop(loop)
    try:
        adapter = UniversalAdapter(cookies=cookies, use_magic=use_magic)
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
        # magic=True 可能导致 Pjax 站点页面导航错误，默认关闭
        self.use_magic = kwargs.get("use_magic", False)
        
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
                self.max_retries,
                self.use_magic
            )

    async def _do_parse(self, url: str) -> ParsedContent:
        """核心解析流程 - Agentic V3"""
        logger.info(f"UniversalAdapter: Starting parse for {url}")

        # 1. Tiered Fetching (Cloudflare MD -> Direct HTTP -> Crawl4AI)
        try:
            # Skip tiers if needed based on config (optional)
            fetch_result = await tiered_fetch(url, cookies=self.cookies, verbose=True)
        except Exception as e:
            logger.error(f"UniversalAdapter: Fetch failed: {e}")
            raise RetryableAdapterError(f"Fetch failed: {e}")

        # 2. Content Agent Processing (Structure Scan -> Metadata Extraction -> Cleanup)
        try:
            process_result = await process_content(url, fetch_result, self.llm_config, verbose=True)
        except Exception as e:
            logger.error(f"UniversalAdapter: Agent processing failed: {e}")
            # Fallback: simple mapping if agent fails but we have content
            process_result = None
            raise RetryableAdapterError(f"Agent processing failed: {e}")

        # 3. Map Results to ParsedContent
        
        # Meta mapping
        common = process_result.common_fields
        extension = process_result.extension_fields
        
        # Determine layout
        video_url = extension.get("video_url") # If extracted by agent
        # Extract images from markdown for layout inference
        images = re.findall(r'!\[[^\]]*\]\(([^)\s]+)\)', process_result.cleaned_markdown)
        
        layout_type = infer_layout_type({"video_url": video_url}, process_result.cleaned_markdown, images)
        
        # Construct Archive Payload
        all_images = []
        seen_urls = set()
        
        # Cover
        cover_url = common.get("cover_url")
        if cover_url and cover_url not in seen_urls:
            all_images.append({"url": cover_url, "type": "cover"})
            seen_urls.add(cover_url)
            
        # Avatar
        author_avatar_url = common.get("author_avatar_url")
        if author_avatar_url and author_avatar_url not in seen_urls:
            all_images.append({"url": author_avatar_url, "type": "avatar", "is_avatar": True})
            seen_urls.add(author_avatar_url)
        
        # Content Images
        for img_url in images:
            if img_url and img_url not in seen_urls:
                all_images.append({"url": img_url})
                seen_urls.add(img_url)

        # Archive Metadata
        archive_meta = {
            "version": 3,
            "fetch_source": process_result.fetch_source,
            "selector": process_result.selector,
            "llm_calls": process_result.llm_calls,
            "ops_log": process_result.ops_log,
            "extension_fields": extension,
            "original_markdown_len": len(process_result.original_markdown),
            "archive": {
                "markdown": process_result.cleaned_markdown,
                "images": all_images,
                "videos": [], # Agent currently doesn't robustly extract videos, can be added later
            }
        }

        # Stats
        stats = {
            "view_count": common.get("view_count", 0),
            "like_count": common.get("like_count", 0),
            "comment_count": common.get("comment_count", 0),
            "share_count": common.get("share_count", 0),
            "collect_count": common.get("collect_count", 0),
        }

        # Parse published_at string to datetime if possible
        published_at = common.get("published_at")
        if published_at and isinstance(published_at, str):
            try:
                from dateutil import parser
                published_at = parser.parse(published_at)
            except:
                pass

        return ParsedContent(
            platform="universal",
            content_type="webpage",
            content_id=hashlib.md5(url.encode()).hexdigest(),
            clean_url=url,
            layout_type=layout_type,
            title=common.get("title") or "Untitled",
            description=process_result.cleaned_markdown,
            author_name=common.get("author_name"),
            author_avatar_url=common.get("author_avatar_url"),
            cover_url=cover_url,
            media_urls=images,
            source_tags=common.get("source_tags", []),
            stats=stats,
            published_at=published_at,
            archive_metadata=archive_meta
        )
