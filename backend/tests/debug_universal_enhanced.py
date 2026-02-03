"""
Enhanced Universal Adapter Debug - 增强版大模型识别测试

在原有正文容器识别基础上，新增：
1. 封面图/章首图 (cover/hero image) 识别
2. 作者头像 (author avatar) 识别
3. 文章元素结构化定位
"""

import os
import sys
import asyncio
import json
import re
from pathlib import Path
from typing import Optional, Dict, Any, List
from urllib.parse import urljoin
from dotenv import load_dotenv
from loguru import logger

# 添加项目路径
sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), "..")))
load_dotenv(os.path.join(os.path.dirname(__file__), "..", ".env"))

from bs4 import BeautifulSoup
from crawl4ai import AsyncWebCrawler, BrowserConfig, CrawlerRunConfig, CacheMode
from crawl4ai.markdown_generation_strategy import DefaultMarkdownGenerator
from langchain_openai import ChatOpenAI

from app.core.llm_factory import LLMFactory
from app.core.crawler_config import get_delay_for_url_sync

# 测试 URL - 博客类站点（这些更容易有封面图和作者头像）
TEST_URLS = {
    # "blog_ienone": "https://blog.ienone.top/anime/anime-review-2025-04/",
    # "tech_docs": "https://docs.crawl4ai.com/core/fit-markdown/",
    "spa_blog_saku": "https://saku.best/archives/dia.html",
    # "blog_fjh": "https://csdn.fjh1997.top/2025/12/31/%E4%BD%BF%E7%94%A8wireguard%E6%90%AD%E5%BB%BA%E6%A0%A1%E5%9B%AD%E7%BD%91VPN/",
    # "news_ithome": "https://www.ithome.com/0/918/106.htm",
}

# SPA/Pjax 站点专用配置 - 加长等待
SPA_EXTRA_DELAY = 12.0  # 额外等待秒数（Pjax 需要更长时间）

OUTPUT_BASE = Path(__file__).parent / "enhanced_debug_output"

# 增强版结构化识别 Prompt
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


def build_html_summary(soup: BeautifulSoup, limit: int = 150) -> str:
    """构建 HTML 结构概要，包含预览文本"""
    containers = []
    for t in soup.find_all(['div', 'article', 'section', 'main', 'header', 'figure'], limit=limit):
        tid = t.get('id', '')
        tcls = " ".join(t.get('class', []))
        if tid or tcls:
            preview = t.get_text(strip=True)[:30].replace('\n', ' ')
            containers.append(f"<{t.name} id='{tid}' class='{tcls}'> → \"{preview}...\"")
    return "\n".join(containers)


def build_image_summary(soup: BeautifulSoup, base_url: str, limit: int = 20) -> str:
    """构建图片信息概要，帮助 LLM 识别封面图和头像"""
    images = []
    for img in soup.find_all('img', limit=limit):
        src = img.get('src') or img.get('data-src') or img.get('data-original') or ''
        if not src or src.startswith('data:'):
            continue
        
        full_url = urljoin(base_url, src)
        alt = img.get('alt', '')[:30]
        classes = " ".join(img.get('class', []))
        
        # 获取父元素信息
        parent = img.parent
        parent_info = ""
        if parent:
            parent_id = parent.get('id', '')
            parent_cls = " ".join(parent.get('class', []))[:40]
            parent_info = f"parent: <{parent.name} id='{parent_id}' class='{parent_cls}'>"
        
        # 获取尺寸信息
        width = img.get('width', '')
        height = img.get('height', '')
        size_info = f"({width}x{height})" if width or height else ""
        
        images.append(f"- src: {full_url[:100]}... | alt: '{alt}' | class: '{classes}' | {size_info} | {parent_info}")
    
    return "\n".join(images) if images else "(no images found)"


async def enhanced_targeting(url: str, html: str) -> Dict[str, Any]:
    """增强版大模型定位：同时识别正文、封面图、作者头像"""
    
    llm_config = LLMFactory.get_crawl4ai_config("text")
    if not llm_config:
        return {"content_selector": "body", "error": "No LLM config"}
    
    soup = BeautifulSoup(html, 'html.parser')
    html_summary = build_html_summary(soup)
    image_summary = build_image_summary(soup, url)
    
    prompt = ENHANCED_TARGETING_PROMPT.format(
        url=url,
        html_summary=html_summary,
        image_summary=image_summary
    )
    
    llm = ChatOpenAI(
        model=llm_config["provider"].split("/")[-1],
        api_key=llm_config["api_token"],
        base_url=llm_config["base_url"],
        temperature=0
    )
    
    try:
        res = await llm.ainvoke(prompt)
        content = res.content.strip()
        
        # 提取 JSON
        json_match = re.search(r'\{.*\}', content, re.DOTALL)
        if json_match:
            result = json.loads(json_match.group())
            result["raw_response"] = content
            return result
        else:
            return {"content_selector": "body", "error": "No JSON in response", "raw": content}
    
    except Exception as e:
        logger.error(f"Enhanced targeting failed: {e}")
        return {"content_selector": "body", "error": str(e)}


def extract_element_url(soup: BeautifulSoup, selector: Optional[str], base_url: str) -> Optional[str]:
    """根据选择器提取元素的 URL（如图片 src 或 background-image）"""
    if not selector:
        return None
    
    try:
        elem = soup.select_one(selector)
        if not elem:
            return None
        
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
        for child in elem.find_all(True):  # 所有子元素
            child_style = child.get('style', '')
            bg_match = re.search(r'url\(["\']?([^"\')\s]+)["\']?\)', child_style)
            if bg_match:
                return urljoin(base_url, bg_match.group(1))
    
    except Exception as e:
        logger.warning(f"Failed to extract URL from selector '{selector}': {e}")
    
    return None


async def run_enhanced_test(name: str, url: str):
    """运行增强版测试"""
    print(f"\n{'='*25} Testing: {name} {'='*25}")
    print(f"URL: {url}")
    
    save_dir = OUTPUT_BASE / name
    save_dir.mkdir(parents=True, exist_ok=True)
    
    delay = get_delay_for_url_sync(url)
    
    # SPA 站点加长等待
    is_spa = "saku.best" in url or "spa" in name.lower()
    extra_delay = SPA_EXTRA_DELAY if is_spa else 3.0
    total_delay = delay + extra_delay
    
    print(f"[{name}] Using delay: {total_delay}s (base: {delay}s, extra: {extra_delay}s, SPA: {is_spa})")
    
    browser_config = BrowserConfig(
        headless=True,
        user_agent="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36",
        user_data_dir=os.getenv("CHROME_USER_DATA_DIR")
    )
    
    run_config = CrawlerRunConfig(
        cache_mode=CacheMode.BYPASS,
        wait_until="domcontentloaded",
        page_timeout=30000,
        delay_before_return_html=3.0,
        magic=False  # 禁用 magic 避免 Pjax 导航错误
    )
    
    try:
        async with AsyncWebCrawler(config=browser_config) as crawler:
            result = await crawler.arun(url=url, config=run_config)
            
            if not result.success:
                print(f"[{name}] Crawl failed: {result.error_message}")
                return
            
            # 保存原始 HTML 供调试
            with open(save_dir / "raw.html", "w", encoding="utf-8") as f:
                f.write(result.html)
            
            # 增强版定位
            print(f"[{name}] Running enhanced LLM targeting...")
            targeting_result = await enhanced_targeting(url, result.html)
            
            # 保存 LLM 原始响应
            with open(save_dir / "llm_response.json", "w", encoding="utf-8") as f:
                json.dump(targeting_result, f, ensure_ascii=False, indent=2)
            
            # 解析结果
            soup = BeautifulSoup(result.html, 'html.parser')
            
            content_selector = targeting_result.get("content_selector", "body")
            cover_info = targeting_result.get("cover_image", {}) or {}
            avatar_info = targeting_result.get("author_avatar", {}) or {}
            
            # 提取封面图 URL
            cover_url = cover_info.get("likely_url")
            if not cover_url:
                cover_url = extract_element_url(soup, cover_info.get("selector"), url)
            
            # 提取作者头像 URL
            avatar_url = avatar_info.get("likely_url")
            if not avatar_url:
                avatar_url = extract_element_url(soup, avatar_info.get("selector"), url)
            
            # 提取正文
            md_generator = DefaultMarkdownGenerator(options={"ignore_images": False})
            try:
                target_node = soup.select_one(content_selector) if content_selector != "body" else soup.body
                if not target_node:
                    target_node = soup.body
                local_md = md_generator.generate_markdown(str(target_node))
                content = local_md.raw_markdown if hasattr(local_md, 'raw_markdown') else str(local_md)
            except Exception as e:
                content = result.markdown.raw_markdown
                logger.warning(f"Local conversion failed: {e}")
            
            # 保存 Markdown
            with open(save_dir / "content.md", "w", encoding="utf-8") as f:
                f.write(content or "")
            
            # 保存结构化结果
            final_result = {
                "url": url,
                "content_selector": content_selector,
                "cover_image": {
                    "selector": cover_info.get("selector"),
                    "url": cover_url
                },
                "author_avatar": {
                    "selector": avatar_info.get("selector"),
                    "url": avatar_url
                },
                "content_images_selector": targeting_result.get("content_images_selector"),
                "reasoning": targeting_result.get("reasoning"),
                "stats": {
                    "content_length": len(content or ""),
                    "images_in_content": len(re.findall(r'!\[[^\]]*\]\([^)]+\)', content or ""))
                }
            }
            
            with open(save_dir / "result.json", "w", encoding="utf-8") as f:
                json.dump(final_result, f, ensure_ascii=False, indent=2)
            
            # 打印结果摘要
            print(f"[{name}] ✓ Content Selector: {content_selector}")
            print(f"[{name}] ✓ Cover Image: {cover_url or '(not found)'}")
            print(f"[{name}] ✓ Author Avatar: {avatar_url or '(not found)'}")
            print(f"[{name}] ✓ Content: {len(content or '')} chars, {final_result['stats']['images_in_content']} images")
            print(f"[{name}] ✓ Reasoning: {targeting_result.get('reasoning', 'N/A')[:100]}...")
            
    except Exception as e:
        print(f"[{name}] Error: {e}")
        import traceback
        traceback.print_exc()


async def main():
    print("="*60)
    print("Enhanced Universal Adapter - LLM Multi-Element Targeting Test")
    print("="*60)
    print(f"Output directory: {OUTPUT_BASE}")
    
    if not os.getenv("TEXT_LLM_API_KEY"):
        print("⚠ CRITICAL: TEXT_LLM_API_KEY not set. LLM targeting will fail.")
        return
    
    # 清理旧结果
    if OUTPUT_BASE.exists():
        import shutil
        shutil.rmtree(OUTPUT_BASE)
    OUTPUT_BASE.mkdir(parents=True, exist_ok=True)
    
    for name, url in TEST_URLS.items():
        await run_enhanced_test(name, url)
        await asyncio.sleep(2)
    
    print("\n" + "="*60)
    print("All tests complete. Check output directory for results.")
    print("="*60)


if __name__ == "__main__":
    import sys
    if sys.platform == 'win32':
        asyncio.set_event_loop_policy(asyncio.WindowsProactorEventLoopPolicy())
    asyncio.run(main())
