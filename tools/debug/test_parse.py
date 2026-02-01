import os
import sys
import json
import asyncio
import re
import time
from datetime import datetime
from pathlib import Path
from dotenv import load_dotenv

# 添加项目路径以导入 app 模块
sys.path.insert(0, os.path.dirname(__file__))

# Windows 必须在导入 crawl4ai 之前设置
if sys.platform == 'win32':
    asyncio.set_event_loop_policy(asyncio.WindowsProactorEventLoopPolicy())

# 加载环境变量
load_dotenv(os.path.join(os.path.dirname(__file__), '.env'))

from crawl4ai import AsyncWebCrawler, BrowserConfig, CrawlerRunConfig, CacheMode
from crawl4ai.markdown_generation_strategy import DefaultMarkdownGenerator
from crawl4ai.content_filter_strategy import PruningContentFilter

from app.core.crawler_config import get_delay_for_url_sync

# ========== 配置 ==========
TEST_URL = "https://blog.ienone.top/anime/anime-review-2025-07/"
# TEST_URL = "https://x.com/PokeMikuVOLTAGE/status/2006379887943434462"
# TEST_URL= "https://www.bilibili.com/opus/1150580721704763430/?from=readlist"

# 输出目录
OUTPUT_DIR = Path(__file__).parent / "test_output"

# 是否启用 LLM 元数据提取
ENABLE_LLM_EXTRACTION = True

# LLM 元数据提取 Schema（不包含正文和链接，这些从 Markdown 获取）
METADATA_SCHEMA = {
    "type": "object",
    "properties": {
        "title": {"type": "string", "description": "The main title of the article or post."},
        "author": {"type": "string", "description": "Name of the author or publisher."},
        "summary": {"type": "string", "description": "A concise summary of the content (2-3 sentences)."},
        "publish_date": {"type": "string", "description": "Publication date if available (YYYY-MM-DD HH:MM format preferred)."},
        "tags": {"type": "array", "items": {"type": "string"}, "description": "Relevant topics or tags."},
        "detected_type": {
            "type": "string",
            "enum": ["article", "video", "gallery", "audio"],
            "description": "Detected content type: 'article' for long-form text, 'video' for video content, 'gallery' for image-heavy posts, 'audio' for podcasts."
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

Do NOT extract the full content text - only metadata.
Return valid JSON matching the schema.
"""


def save_result(filename: str, content: str):
    """保存结果到文件"""
    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)
    filepath = OUTPUT_DIR / filename
    with open(filepath, 'w', encoding='utf-8') as f:
        f.write(content)
    print(f"✓ 已保存: {filepath}")


def get_llm_config():
    """获取 LLM 配置"""
    api_key = os.getenv("TEXT_LLM_API_KEY")
    base_url = os.getenv("TEXT_LLM_BASE_URL")
    model = os.getenv("TEXT_LLM_MODEL", "deepseek-chat")
    
    if not api_key:
        print("[LLM] 警告: TEXT_LLM_API_KEY 未配置，跳过 LLM 提取")
        return None
    
    return {
        "provider": f"openai/{model}",
        "api_token": api_key,
        "base_url": base_url
    }


async def extract_metadata_with_llm(markdown_content: str, llm_config: dict) -> dict:
    """
    使用 LLM 从 Markdown 内容中提取元数据
    """
    from langchain_openai import ChatOpenAI
    
    print("\n[LLM] 开始元数据提取...")
    start_time = time.time()
    
    try:
        llm = ChatOpenAI(
            model=llm_config["provider"].split("/")[-1],  # 提取模型名
            api_key=llm_config["api_token"],
            base_url=llm_config["base_url"],
            temperature=0.1,
        )
        
        # 构建提示
        prompt = f"""{EXTRACTION_PROMPT}

Schema:
```json
{json.dumps(METADATA_SCHEMA, indent=2)}
```

Content to analyze:
```
{markdown_content[:8000]}  
```

Respond with valid JSON only, no markdown code blocks:"""

        response = await llm.ainvoke(prompt)
        response_text = response.content.strip()
        
        # 尝试清理和解析 JSON
        if response_text.startswith("```"):
            # 移除 markdown 代码块
            response_text = re.sub(r'^```(?:json)?\n?', '', response_text)
            response_text = re.sub(r'\n?```$', '', response_text)
        
        metadata = json.loads(response_text)
        
        elapsed = time.time() - start_time
        print(f"[LLM] 提取完成 (耗时: {elapsed:.2f}s)")
        
        return metadata
        
    except json.JSONDecodeError as e:
        print(f"[LLM] JSON 解析失败: {e}")
        print(f"[LLM] 原始响应: {response_text[:500]}...")
        return {}
    except Exception as e:
        print(f"[LLM] 提取失败: {type(e).__name__}: {e}")
        return {}


async def crawl_and_extract():
    print(f"=" * 60)
    print(f"测试 URL: {TEST_URL}")
    print(f"输出目录: {OUTPUT_DIR}")
    print(f"LLM 提取: {'启用' if ENABLE_LLM_EXTRACTION else '禁用'}")
    print(f"=" * 60)
    
    # 浏览器配置 - 增加伪装以避免 JavaScript 检测
    browser_config = BrowserConfig(
        headless=True,
        verbose=True,
        user_agent="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36",
    )
    
    # 内容过滤器 - 使用固定阈值避免不稳定性
    content_filter = PruningContentFilter(
        threshold=0.45,
        threshold_type="fixed",  # 固定阈值
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
    
    # ========== 核心过滤配置 ==========
    excluded_tags = [
        "nav", "header", "footer", "aside",
        "form", "iframe", "noscript", "script", "style",
        "svg", "canvas",
    ]
    
    excluded_selector = ",".join([
        ".navbar", ".nav", ".navigation", ".menu", ".breadcrumb",
        "[role='navigation']", "[role='banner']",
        ".sidebar", ".toc", ".table-of-contents",
        ".header", ".footer", "[role='contentinfo']",
        ".comments", ".comment-section", ".social-share", ".share-buttons",
        ".ad", ".ads", ".advertisement", ".advert",
        ".widget", ".popup", ".modal", ".cookie-notice",
        ".subscribe", ".newsletter", ".related-posts",
    ])
    
    excluded_domains = [
        "facebook.com", "instagram.com",
        "linkedin.com", "pinterest.com", "tiktok.com",
        "youtube.com", "reddit.com", "discord.com",
    ]
    
    # 根据 URL 自动获取等待时间
    delay_time = get_delay_for_url_sync(TEST_URL)
    print(f"[配置] 根据域名自动设置等待时间: {delay_time}s")
    
    # 爬取配置
    run_config = CrawlerRunConfig(
        cache_mode=CacheMode.BYPASS,
        wait_for="body",
        delay_before_return_html=delay_time,
        
        markdown_generator=md_generator,
        
        word_count_threshold=5,
        excluded_tags=excluded_tags,
        excluded_selector=excluded_selector,
        
        exclude_external_links=False,
        exclude_social_media_links=False,
        exclude_domains=excluded_domains,
        
        exclude_external_images=False,
        
        process_iframes=False,
        remove_overlay_elements=False,  # 必须禁用！会误删 SPA 页面内容
        magic=True,
    )
    
    print(f"\n已配置的过滤规则:")
    print(f"  - excluded_tags: {len(excluded_tags)} 个标签")
    print(f"  - excluded_selector: {len(excluded_selector.split(','))} 个选择器")
    
    print("\n开始爬取...")
    start_time = time.time()
    timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
    
    try:
        async with AsyncWebCrawler(config=browser_config) as crawler:
            result = await crawler.arun(url=TEST_URL, config=run_config)
            
            crawl_elapsed = time.time() - start_time
            
            # 保存原始 HTML（调试用）
            if result.html:
                save_result(f"{timestamp}_debug.html", result.html)
                print(f"[DEBUG] HTML 长度: {len(result.html)} 字符")
            else:
                print("[DEBUG] 警告: HTML 为空!")
            
            if result.cleaned_html:
                print(f"[DEBUG] Cleaned HTML 长度: {len(result.cleaned_html)} 字符")
            
            # 获取 Markdown
            if hasattr(result.markdown, 'raw_markdown'):
                raw_markdown = result.markdown.raw_markdown
                fit_markdown = result.markdown.fit_markdown
            else:
                raw_markdown = str(result.markdown) if result.markdown else ""
                fit_markdown = None
            
            print(f"[DEBUG] Markdown 长度: {len(raw_markdown)} 字符")
            
            # 保存 Markdown
            if raw_markdown:
                save_result(f"{timestamp}_content.md", raw_markdown)
            else:
                print("[DEBUG] 警告: Markdown 为空!")
            
            if fit_markdown and fit_markdown != raw_markdown:
                save_result(f"{timestamp}_fit.md", fit_markdown)
            
            # 提取图片列表
            images = re.findall(r'!\[.*?\]\((.*?)\)', raw_markdown)
            
            # ========== LLM 元数据提取 ==========
            metadata = {}
            if ENABLE_LLM_EXTRACTION and raw_markdown:
                llm_config = get_llm_config()
                if llm_config:
                    # 使用 fit_markdown（更干净）或 raw_markdown
                    content_for_llm = fit_markdown if fit_markdown else raw_markdown
                    metadata = await extract_metadata_with_llm(content_for_llm, llm_config)
            
            # 构建最终结果
            total_elapsed = time.time() - start_time
            
            final_result = {
                "url": TEST_URL,
                "content": fit_markdown or raw_markdown,
                "raw_content": raw_markdown,
                "images": images[:30],
                "metadata": metadata,
                "stats": {
                    "content_length": len(raw_markdown),
                    "fit_content_length": len(fit_markdown) if fit_markdown else 0,
                    "image_count": len(images),
                    "crawl_time": round(crawl_elapsed, 2),
                    "total_time": round(total_elapsed, 2),
                    "llm_extracted": bool(metadata),
                }
            }
            
            save_result(f"{timestamp}_result.json", json.dumps(final_result, ensure_ascii=False, indent=2))
            
            # 打印摘要
            print(f"\n{'=' * 60}")
            print(f"=== 结果摘要 (总耗时: {total_elapsed:.2f}s) ===")
            print(f"{'=' * 60}")
            print(f"成功: {result.success}")
            print(f"状态码: {result.status_code}")
            print(f"Markdown 长度: {len(raw_markdown)} 字符")
            print(f"Fit Markdown 长度: {len(fit_markdown) if fit_markdown else 0} 字符")
            print(f"提取图片数: {len(images)}")
            
            if metadata:
                print(f"\n=== LLM 提取的元数据 ===")
                print(f"标题: {metadata.get('title', 'N/A')}")
                print(f"作者: {metadata.get('author', 'N/A')}")
                print(f"发布日期: {metadata.get('publish_date', 'N/A')}")
                print(f"内容类型: {metadata.get('detected_type', 'N/A')}")
                print(f"摘要: {metadata.get('summary', 'N/A')[:100]}...")
                if metadata.get('metrics'):
                    m = metadata['metrics']
                    print(f"互动数据: 👁 {m.get('view_count', 0)} | ❤ {m.get('like_count', 0)} | 💬 {m.get('comment_count', 0)} | 🔄 {m.get('share_count', 0)}")
                if metadata.get('tags'):
                    print(f"标签: {', '.join(metadata['tags'][:5])}")
            
            # 预览内容
            print(f"\n=== 内容预览 ===")
            preview_content = fit_markdown if fit_markdown else raw_markdown
            print(preview_content[:500])
            print("...")
            
            print(f"\n所有结果已保存到: {OUTPUT_DIR}")
                
    except Exception as e:
        print(f"\n错误: {type(e).__name__}: {e}")
        import traceback
        traceback.print_exc()


if __name__ == "__main__":
    asyncio.run(crawl_and_extract())
