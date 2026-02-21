# 通用适配器 (Universal Adapter) - Agentic V2

# 使用探测、语义定标与本地提取的三阶段架构：
# 1. 探测阶段：使用 Crawl4AI 下载页面并提取原始 HTML 与元数据。
# 2. 定标阶段：提取 DOM 结构概览，利用轻量级 LLM 识别正文容器选择器。
# 3. 提取阶段：在本地利用锁定容器进行 Markdown 转换，补全路径并合并元数据。

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


# LLM 增强版结构化识别 Prompt - 同时识别正文、封面图、作者头像
ENHANCED_TARGETING_PROMPT = """You are an expert at analyzing web page structure for content extraction.

Analyze the HTML structure and identify these elements. Return valid JSON only.

Task: Find CSS selectors for the MAIN article content and key visual elements.

URL: {url}

HTML Structure Summary:
{html_summary}

Important images found (first 20):
{image_summary}

Return JSON with these fields:
{{
  "content_selector": "CSS selector for main article body (e.g., '#article-content', 'article.post')",
  "title": "Article title extracted from h1, .post-title, or similar elements (not from <title> tag)",
  "cover_image": {{
    "selector": "CSS selector for hero/cover/banner image if exists, or null",
    "likely_url": "Direct URL of the cover image if identifiable, or null"
  }},
  "author_avatar": {{
    "selector": "CSS selector for author avatar/profile image if exists, or null", 
    "likely_url": "Direct URL of the avatar image if identifiable, or null"
  }},
  "content_images_selector": "CSS selector for images INSIDE the content area (e.g., '.post-content img'), or null",
  "reasoning": "Brief explanation of how you identified each element"
}}

Rules:
- For content_selector: Choose the tightest container around article text, exclude nav/sidebar/ads/comments
- For cover_image: Look for large hero images, banner images, featured images BEFORE or AT TOP of content
  - Note: Cover images may use CSS background-image instead of <img> tags (check style="background-image: url(...)")
  - Return the container selector (e.g., ".entry-thumbnail") not ".entry-thumbnail img" if using background-image
- For author_avatar: Look for small profile images near author name/byline, often in header or author bio section
- If an element doesn't exist on this page, return null for that field
- Prefer selectors with id/class over tag-only selectors

JSON:"""

# 元数据精炼 Prompt - 主要生成摘要和标签（标题仅在缺失时生成）
METADATA_PROMPT = """
Analyze the content and extract metadata. Return valid JSON only.

Current title: {current_title}

Schema:
{{
  "title": "string or null (ONLY generate if current title is 'Untitled' or empty, otherwise return null)",
  "author": "string or null",
  "summary": "string (2-3 sentences summarizing the main content)",
  "publish_date": "YYYY-MM-DD or null",
  "tags": ["string"] (3-8 relevant tags)
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
        # magic=True 可能导致 Pjax 站点页面导航错误，默认关闭
        self.use_magic = kwargs.get("use_magic", False)
        # 是否启用图片元素识别（封面图、头像等），可选功能
        self.detect_images = kwargs.get("detect_images", True)
        
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
        """补全 Markdown 中的所有相对链接，并对URL进行编码"""
        if not md_text: return ""
        
        from urllib.parse import urlsplit, urlunsplit, quote
        
        def encode_url(raw_url: str) -> str:
            """对URL路径中的特殊字符（空格、中文、括号等）进行编码"""
            # 先处理markdown转义字符：\( -> (, \) -> )
            url = raw_url.strip().replace('\\(', '(').replace('\\)', ')')
            full_url = urljoin(base_url, url)
            try:
                parts = urlsplit(full_url)
                # 编码路径部分，不保留括号（括号也需要编码以避免markdown解析问题）
                encoded_path = quote(parts.path, safe='/')
                encoded_query = quote(parts.query, safe='=&') if parts.query else ''
                return urlunsplit((parts.scheme, parts.netloc, encoded_path, encoded_query, parts.fragment))
            except:
                return full_url
        
        # 匹配URL：支持转义字符和包含空格的URL
        # [^)\\]  匹配除了 ) 和 \ 之外的任意字符（包括空格、中文等）
        # \\.     匹配任何转义序列如 \( \) \[ 等
        url_pattern = r'(?:[^)\\]|\\.)+'
        
        # 1. 修复图片 ![alt](url)
        def img_repl(m):
            alt, url = m.group(1), m.group(2)
            return f"![{alt}]({encode_url(url)})"
        md_text = re.sub(rf"!\[([^\]]*)\]\(({url_pattern})\)", img_repl, md_text)
        
        # 2. 修复普通链接 [text](url)
        def link_repl(m):
            text, url = m.group(1), m.group(2)
            return f"[{text}]({encode_url(url)})"
        md_text = re.sub(rf"(?<!!)\[([^\]]*)\]\(({url_pattern})\)", link_repl, md_text)
        
        return md_text

    def _cleanup_markdown(self, md_text: str) -> str:
        """清理 Markdown 格式问题"""
        if not md_text: return ""
        
        # 1. 移除标题末尾锚点 #
        md_text = re.sub(r'^(#+ .*?)#\s*$', r'\1', md_text, flags=re.MULTILINE)
        
        # 2. 修复错误的引用块格式（> 符号后直接跟内容，应有空格）
        md_text = re.sub(r'^>\s*\*\s+', '- ', md_text, flags=re.MULTILINE)
        
        # 3. 移除独立的 > 行（空引用块）
        md_text = re.sub(r'^>\s*$', '', md_text, flags=re.MULTILINE)
        
        # 4. 修复被错误包裹为引用块的列表项
        md_text = re.sub(r'^>\s+(\d+\.\s+)', r'\1', md_text, flags=re.MULTILINE)
        md_text = re.sub(r'^>\s+(-\s+)', r'\1', md_text, flags=re.MULTILINE)
        
        # 5. 修复代码块内的引用标记（通常是转换错误）
        # 将 > ``` 修复为 ```
        md_text = re.sub(r'^>\s*```', '```', md_text, flags=re.MULTILINE)
        
        # 6. 移除行首多余的 > 标记（连续多个 >）
        md_text = re.sub(r'^>+\s*>', '> ', md_text, flags=re.MULTILINE)
        
        # 7. 清理 HTML 实体残留
        md_text = md_text.replace('&nbsp;', ' ')
        md_text = md_text.replace('&amp;', '&')
        md_text = md_text.replace('&lt;', '<')
        md_text = md_text.replace('&gt;', '>')
        
        # 8. 移除过多的连续空行
        md_text = re.sub(r'\n{3,}', '\n\n', md_text)
        
        # 9. 修复列表项之间的空行（保持列表连续性）
        md_text = re.sub(r'(\n- [^\n]+)\n{2,}(- )', r'\1\n\2', md_text)
        md_text = re.sub(r'(\n\d+\. [^\n]+)\n{2,}(\d+\. )', r'\1\n\2', md_text)
        
        return md_text.strip()

    def _build_html_summary(self, soup: BeautifulSoup, limit: int = 150) -> str:
        """构建 HTML 结构概要，包含预览文本"""
        containers = []
        for t in soup.find_all(['div', 'article', 'section', 'main', 'header', 'figure'], limit=limit):
            tid = t.get('id', '')
            tcls = " ".join(t.get('class', []))
            if tid or tcls:
                preview = t.get_text(strip=True)[:30].replace('\n', ' ')
                containers.append(f"<{t.name} id='{tid}' class='{tcls}'> → \"{preview}...\"")
        return "\n".join(containers)

    def _build_image_summary(self, soup: BeautifulSoup, base_url: str, limit: int = 20) -> str:
        """构建图片信息概要，帮助 LLM 识别封面图和头像"""
        images = []
        for img in soup.find_all('img', limit=limit):
            src = img.get('src') or img.get('data-src') or img.get('data-original') or ''
            if not src or src.startswith('data:'):
                continue
            
            full_url = urljoin(base_url, src)
            alt = img.get('alt', '')[:30]
            classes = " ".join(img.get('class', []))
            
            parent = img.parent
            parent_info = ""
            if parent:
                parent_id = parent.get('id', '')
                parent_cls = " ".join(parent.get('class', []))[:40]
                parent_info = f"parent: <{parent.name} id='{parent_id}' class='{parent_cls}'>"
            
            width = img.get('width', '')
            height = img.get('height', '')
            size_info = f"({width}x{height})" if width or height else ""
            
            images.append(f"- src: {full_url[:100]}... | alt: '{alt}' | class: '{classes}' | {size_info} | {parent_info}")
        
        return "\n".join(images) if images else "(no images found)"

    def _extract_element_url(self, soup: BeautifulSoup, selector: str, base_url: str) -> str:
        """根据选择器提取元素的 URL（图片 src 或 background-image）"""
        if not selector:
            return ""
        
        try:
            elem = soup.select_one(selector)
            if not elem:
                return ""
            
            # 如果是 img 标签
            if elem.name == 'img':
                src = elem.get('src') or elem.get('data-src') or elem.get('data-original')
                if src:
                    return urljoin(base_url, src)
            
            # 如果是包含 img 的容器
            img = elem.find('img')
            if img:
                src = img.get('src') or img.get('data-src') or img.get('data-original')
                if src:
                    return urljoin(base_url, src)
            
            # 检查当前元素的 background-image style
            style = elem.get('style', '')
            bg_match = re.search(r'url\(["\']?([^"\')\s]+)["\']?\)', style)
            if bg_match:
                return urljoin(base_url, bg_match.group(1))
            
            # 递归检查子元素的 background-image（常见于封面图容器）
            for child in elem.find_all(True):
                child_style = child.get('style', '')
                bg_match = re.search(r'url\(["\']?([^"\')\s]+)["\']?\)', child_style)
                if bg_match:
                    return urljoin(base_url, bg_match.group(1))
        except Exception as e:
            logger.warning(f"UniversalAdapter: Failed to extract URL from selector '{selector}': {e}")
        
        return ""

    async def _enhanced_targeting(self, url: str, html: str, detect_images: bool = True) -> dict:
        """增强版 LLM 定位：同时识别正文、封面图、作者头像
        
        Args:
            detect_images: 是否识别封面图和头像（可选，关闭可节省 token）
        """
        if not self.llm_config:
            return {"content_selector": "body"}
        
        soup = BeautifulSoup(html, 'html.parser')
        html_summary = self._build_html_summary(soup)
        
        # 图片识别为可选项
        if detect_images:
            image_summary = self._build_image_summary(soup, url)
        else:
            image_summary = "(image detection disabled)"
        
        from langchain_openai import ChatOpenAI
        llm = ChatOpenAI(
            model=self.llm_config["provider"].split("/")[-1],
            api_key=self.llm_config["api_token"],
            base_url=self.llm_config["base_url"],
            temperature=0
        )
        
        prompt = ENHANCED_TARGETING_PROMPT.format(
            url=url,
            html_summary=html_summary,
            image_summary=image_summary
        )
        
        try:
            res = await llm.ainvoke(prompt)
            content = res.content.strip()
            
            json_match = re.search(r'\{.*\}', content, re.DOTALL)
            if json_match:
                result = json.loads(json_match.group())
                logger.debug(f"UniversalAdapter: Enhanced targeting result: {result.get('reasoning', 'N/A')[:100]}")
                return result
            else:
                logger.warning(f"UniversalAdapter: No JSON in enhanced targeting response")
                return {"content_selector": "body"}
        
        except Exception as e:
            logger.warning(f"UniversalAdapter: Enhanced targeting failed: {e}")
            return {"content_selector": "body"}

    def _extract_title_from_html(self, soup: BeautifulSoup, og_meta: dict, page_meta: dict) -> str:
        """从页面结构中提取标题，优先级：h1 > og:title > <title>"""
        # 1. 优先查找正文区域的 h1
        h1 = soup.find('h1')
        if h1:
            h1_text = h1.get_text(strip=True)
            # 过滤掉太短或太长的 h1（可能是 logo 或导航）
            if 3 < len(h1_text) < 200:
                return h1_text
        
        # 2. 尝试 article/post 标题
        for selector in ['article h1', '.post-title', '.article-title', '.entry-title', 'header h1']:
            title_elem = soup.select_one(selector)
            if title_elem:
                title_text = title_elem.get_text(strip=True)
                if 3 < len(title_text) < 200:
                    return title_text
        
        # 3. OG 标题
        og_title = og_meta.get("og:title", "")
        if og_title and og_title != "Untitled":
            return og_title
        
        # 4. 页面 <title>
        page_title = page_meta.get("title", "")
        if page_title and page_title != "Untitled":
            return page_title
        
        return ""

    async def _refine_metadata(self, content: str, initial_meta: dict) -> dict:
        """利用 LLM 精炼文章元数据（主要生成摘要和标签，标题仅在缺失时生成）"""
        if not self.llm_config: return initial_meta
        
        from langchain_openai import ChatOpenAI
        llm = ChatOpenAI(
            model=self.llm_config["provider"].split("/")[-1],
            api_key=self.llm_config["api_token"],
            base_url=self.llm_config["base_url"],
            temperature=0.1
        )
        
        current_title = initial_meta.get("title", "Untitled")
        prompt = METADATA_PROMPT.format(
            current_title=current_title,
            content_snippet=content[:4000]
        )
        try:
            res = await llm.ainvoke(prompt)
            match = re.search(r'\{.*\}', res.content, re.DOTALL)
            if match:
                llm_meta = json.loads(match.group())
                # 只有当页面标题缺失或为通用标题时才使用 LLM 生成的标题
                if current_title and current_title != "Untitled":
                    llm_meta.pop("title", None)  # 保留页面原标题
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
            magic=self.use_magic  # 默认 False，避免 Pjax 站点导航错误
        )

        async with AsyncWebCrawler(config=browser_config) as crawler:
            result = await crawler.arun(url=url, config=run_config)
            if not result.success:
                raise RetryableAdapterError(f"Crawl failed: {result.error_message}")

            # 2. 增强版定标：同时识别正文、封面图、作者头像（图片识别可选）
            logger.debug(f"UniversalAdapter: Running enhanced targeting for {url}")
            targeting = await self._enhanced_targeting(url, result.html, detect_images=self.detect_images)
            selector = targeting.get("content_selector", "body")
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

            # 4. 后处理：修复路径与清理（URL会被编码，括号等特殊字符会被转义）
            description = self._cleanup_markdown(self._fix_links(description, url))
            # 从已处理的 markdown 中提取图片 URL（已编码，不含裸括号）
            images = re.findall(r'!\[[^\]]*\]\(([^)\s]+)\)', description)

            # 5. 提取封面图和作者头像（来自 LLM 识别，仅当启用时）
            llm_cover_url = ""
            llm_avatar_url = ""
            if self.detect_images:
                cover_info = targeting.get("cover_image") or {}
                avatar_info = targeting.get("author_avatar") or {}
                
                # 优先使用 LLM 直接给出的 URL，否则从选择器提取
                llm_cover_url = cover_info.get("likely_url") or ""
                if not llm_cover_url and cover_info.get("selector"):
                    llm_cover_url = self._extract_element_url(soup, cover_info.get("selector"), url)
                
                llm_avatar_url = avatar_info.get("likely_url") or ""
                if not llm_avatar_url and avatar_info.get("selector"):
                    llm_avatar_url = self._extract_element_url(soup, avatar_info.get("selector"), url)

            # 6. 元数据合并 - 标题优先级：LLM定位识别 > 页面结构提取 > METADATA_PROMPT生成
            og = result.metadata.get("opengraph", {})
            json_ld = result.metadata.get("jsonld", [])
            if isinstance(json_ld, list) and json_ld: json_ld = json_ld[0]
            elif not isinstance(json_ld, dict): json_ld = {}
            
            # 标题来源优先级：
            # 1. LLM 增强定位中识别的标题（最准确）
            # 2. 页面结构提取（h1, .post-title 等）
            # 3. OG/meta 标签
            # 4. METADATA_PROMPT 生成（兜底）
            llm_title = targeting.get("title", "")
            if not llm_title:
                llm_title = self._extract_title_from_html(soup, og, result.metadata)

            meta = {
                "title": llm_title or "Untitled",
                "author": json_ld.get("author", {}).get("name") if isinstance(json_ld.get("author"), dict) else None,
                "publish_date": json_ld.get("datePublished") or og.get("article:published_time"),
                "cover_image_url": og.get("og:image"),
                "summary": og.get("og:description"),
                "tags": []
            }
            
            # 精炼：主要生成摘要和标签，标题仅在缺失时生成
            meta = await self._refine_metadata(description, meta)
            
            # 构建 ParsedContent
            layout_type = infer_layout_type({"video_url": og.get("og:video")}, description, images)
            
            # 封面图优先级：LLM识别 > OG标签 > 正文第一张图
            cover_url = llm_cover_url or urljoin(url, meta.get("cover_image_url") or (images[0] if images else ""))
            # 作者头像：LLM 识别
            author_avatar_url = llm_avatar_url or ""

            # 构建 archive 供 worker 下载图片
            # 收集所有需要下载的图片：正文图片 + 封面 + 头像
            all_images = []
            seen_urls = set()
            
            # 1. 封面图（标记类型）
            if cover_url and cover_url not in seen_urls:
                all_images.append({"url": cover_url, "type": "cover"})
                seen_urls.add(cover_url)
            
            # 2. 作者头像（标记类型）
            if author_avatar_url and author_avatar_url not in seen_urls:
                all_images.append({"url": author_avatar_url, "type": "avatar", "is_avatar": True})
                seen_urls.add(author_avatar_url)
            
            # 3. 正文图片
            for img_url in images:
                if img_url and img_url not in seen_urls:
                    all_images.append({"url": img_url})
                    seen_urls.add(img_url)
            
            archive = {
                "markdown": description,
                "images": all_images,
                "videos": [],
                "llm_selector": selector,
                "llm_targeting": targeting  # 保存完整的 LLM 定位结果供调试
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
                author_avatar_url=author_avatar_url or None,  # 新增：作者头像
                cover_url=cover_url,
                media_urls=images,
                source_tags=meta.get("tags", []),
                stats={
                    "view_count": 0, "like_count": 0, "comment_count": 0, "share_count": 0
                },
                raw_metadata={
                    "summary": meta.get("summary"),
                    "publish_date": meta.get("publish_date"),
                },
                archive_metadata={
                    "version": 2,
                    "archive": archive,
                    "meta": meta
                }
            )