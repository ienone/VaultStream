import os
import sys
import asyncio
import json
import re
from pathlib import Path
from datetime import datetime
from dotenv import load_dotenv

# 添加项目路径以导入 app 模块
sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), "..")))

# 加载环境变量
load_dotenv(os.path.join(os.path.dirname(__file__), "..", ".env"))

from app.adapters.universal_adapter import UniversalAdapter
from app.adapters.base import ParsedContent
from crawl4ai import AsyncWebCrawler, BrowserConfig, CrawlerRunConfig, CacheMode

# 测试 URL 列表
TEST_URLS = {
    "blog_ienone": "https://blog.ienone.top/anime/anime-review-2025-04/",
    "blog_saku": "https://saku.best/archives/dia.html",
    "blog_csdn": "https://csdn.fjh1997.top/2025/10/20/%E7%94%A8python%E6%A8%A1%E6%8B%9F%E7%9A%84MultiByteToWideChar%E7%84%B6%E5%90%8EWideCharToMultiByte%E5%87%BA%E9%94%99%E6%83%85%E5%86%B5/",
    "news_zhibo8": "https://news.zhibo8.com/zuqiu/2026-02-01/697eb97655c98native.htm",
    "news_ithome": "https://www.ithome.com/0/918/106.htm",
    "gallery_bilibili": "https://www.bilibili.com/opus/1164087040949616661",
}

# 输出目录
OUTPUT_BASE = Path(__file__).parent / "universal_debug_output"

async def run_debug_test(name: str, url: str):
    print(f"\n{'='*20} Testing: {name} {'='*20}")
    print(f"URL: {url}")
    
    # 确保保存目录存在
    save_dir = OUTPUT_BASE / name
    save_dir.mkdir(parents=True, exist_ok=True)
    
    adapter = UniversalAdapter()
    
    # 我们不仅使用 adapter.parse，还要手动运行一次以捕获 HTML (Adapter.parse 为了效率不保存 HTML)
    # 逻辑流程模仿 UniversalAdapter
    
    browser_config = BrowserConfig(headless=True, verbose=False)
    run_config = CrawlerRunConfig(
        cache_mode=CacheMode.BYPASS,
        magic=True,
        remove_overlay_elements=False, # 避开误删
    )
    
    try:
        async with AsyncWebCrawler(config=browser_config) as crawler:
            print(f"[{name}] Crawling...")
            result = await crawler.arun(url=url, config=run_config)
            
            if not result.success:
                print(f"[{name}] Crawl failed: {result.error_message}")
                return

            # 保存原始 HTML
            with open(save_dir / "source.html", "w", encoding="utf-8") as f:
                f.write(result.html or "")
            
            # 保存 Markdown
            markdown_content = result.markdown.raw_markdown if hasattr(result.markdown, 'raw_markdown') else str(result.markdown)
            with open(save_dir / "content.md", "w", encoding="utf-8") as f:
                f.write(markdown_content or "")
            
            print(f"[{name}] HTML & Markdown saved.")

            # 调用适配器进行结构化解析 (会进行 LLM 提取)
            print(f"[{name}] Extracting structured metadata with LLM...")
            # 注意：UniversalAdapter.parse 会自己再爬一遍，这里为了简单直接调用
            # 如果想共用 result，需要重构 UniversalAdapter，但作为测试代码，跑两次也行。
            parsed: ParsedContent = await adapter.parse(url)
            
            # 保存结构化 JSON
            debug_info = {
                "platform": parsed.platform,
                "content_type": parsed.content_type,
                "layout_type": parsed.layout_type,
                "title": parsed.title,
                "author": parsed.author_name,
                "author_avatar": parsed.author_avatar_url,
                "cover": parsed.cover_url,
                "media_urls": parsed.media_urls,
                "stats": parsed.stats,
                "raw_metadata": parsed.raw_metadata,
                "description_snippet": (parsed.description[:200] + "...") if parsed.description else None
            }
            
            with open(save_dir / "result.json", "w", encoding="utf-8") as f:
                json.dump(debug_info, f, ensure_ascii=False, indent=2)
            
            print(f"[{name}] Structured JSON saved.")
            print(f"[{name}] Detected Layout: {parsed.layout_type}")
            print(f"[{name}] Title: {parsed.title}")
            
    except Exception as e:
        print(f"[{name}] Error: {e}")
        import traceback
        traceback.print_exc()

async def main():
    print(f"Starting Universal Adapter Debug Test...")
    print(f"Results will be saved to: {OUTPUT_BASE}")
    
    if not os.getenv("TEXT_LLM_API_KEY"):
        print("Warning: TEXT_LLM_API_KEY not set. LLM extraction will fail or skip.")

    for name, url in TEST_URLS.items():
        await run_debug_test(name, url)
        # 适当延迟避免触发反爬
        await asyncio.sleep(2)

if __name__ == "__main__":
    asyncio.run(main())
