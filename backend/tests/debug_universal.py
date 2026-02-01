import os
import sys
import asyncio
import json
from pathlib import Path
from dotenv import load_dotenv
from loguru import logger

# 添加项目路径以导入 app 模块
sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), "..")))

# 加载环境变量
load_dotenv(os.path.join(os.path.dirname(__file__), "..", ".env"))

from app.adapters.universal_adapter import UniversalAdapter
from app.adapters.base import ParsedContent

# 测试 URL 列表 - 覆盖不同类型的站点
TEST_URLS = {
    "blog_ienone": "https://blog.ienone.top/anime/anime-review-2025-04/",
    "news_ithome": "https://www.ithome.com/0/918/106.htm",
    "news_zhibo8": "https://news.zhibo8.com/zuqiu/2026-02-01/697eb97655c98native.htm",
    "tech_docs": "https://docs.crawl4ai.com/core/fit-markdown/",
    "spa_blog_saku": "https://saku.best/archives/dia.html",
    "bilibili_opus": "https://www.bilibili.com/opus/1164087040949616661"
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
    
    try:
        print(f"[{name}] Starting Agentic V2 Parse...")
        # 直接调用生产接口
        parsed: ParsedContent = await adapter.parse(url)
        
        # 提取中间调试信息
        selector = parsed.raw_metadata.get("archive", {}).get("llm_selector", "Unknown")
        print(f"[{name}] Target Selector Found: {selector}")
        
        # 保存 Markdown 正文
        with open(save_dir / "content.md", "w", encoding="utf-8") as f:
            f.write(parsed.description or "")
        
        # 保存结构化 JSON
        debug_info = {
            "title": parsed.title,
            "author": parsed.author_name,
            "layout_type": parsed.layout_type,
            "selector_used": selector,
            "image_count": len(parsed.media_urls),
            "media_urls_preview": parsed.media_urls[:5],
            "cover": parsed.cover_url,
            "summary": parsed.raw_metadata.get("summary"),
            "tags": parsed.source_tags,
            "publish_date": parsed.raw_metadata.get("publish_date")
        }
        
        with open(save_dir / "result.json", "w", encoding="utf-8") as f:
            json.dump(debug_info, f, ensure_ascii=False, indent=2)
        
        print(f"[{name}] Success! Results saved to {save_dir.name}/\n")
        print(f"[{name}] Title: {parsed.title}")
        print(f"[{name}] Stats: {len(parsed.description or '')} chars, {len(parsed.media_urls)} images")
            
    except Exception as e:
        print(f"[{name}] Error: {e}")
        import traceback
        traceback.print_exc()

async def main():
    print(f"Starting Universal Adapter Debug Suite (Agentic V2)...")
    print(f"Results will be saved to: {OUTPUT_BASE}")
    
    if not os.getenv("TEXT_LLM_API_KEY"):
        print("CRITICAL: TEXT_LLM_API_KEY not set. Agentic targeting will fail.")

    # 清理旧结果
    if OUTPUT_BASE.exists():
        import shutil
        shutil.rmtree(OUTPUT_BASE)
    OUTPUT_BASE.mkdir(parents=True, exist_ok=True)

    for name, url in TEST_URLS.items():
        await run_debug_test(name, url)
        # 适当延迟，尊重反爬
        await asyncio.sleep(2)

if __name__ == "__main__":
    asyncio.run(main())