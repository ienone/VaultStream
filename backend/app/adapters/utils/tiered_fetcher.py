"""
三级降级获取模块 (Tiered Content Fetcher)

Tier 1: Cloudflare Markdown — Accept: text/markdown (最轻量)
Tier 2: httpx 直接 HTTP GET (中等, 适用服务端渲染页面)
Tier 3: crawl4ai 无头浏览器 (最重, 适用 JS 渲染页面)

每一级尝试后判断内容质量, 不达标则降级到下一级。
"""

import re
import asyncio
from dataclasses import dataclass, field
from typing import Optional
import anyio
from urllib.parse import urlparse
from loguru import logger

import httpx
from bs4 import BeautifulSoup

from app.core.crawler_config import get_delay_for_url_sync


@dataclass
class FetchResult:
    """统一的获取结果"""
    url: str
    content: str  # markdown 或 html
    content_type: str  # "markdown" | "html"
    source: str  # "cloudflare_md" | "direct_http" | "crawl4ai"
    status_code: int = 200
    html: str = ""  # 原始 HTML (Tier 2/3 保留, 供定标使用)
    token_estimate: Optional[int] = None  # Cloudflare x-markdown-tokens
    meta: dict = field(default_factory=dict)  # 附加元信息


# ============================================================
# 内容质量检测
# ============================================================

def _has_sufficient_content(html: str, min_text_length: int = 500) -> bool:
    """
    判断 HTML 是否包含足够的正文内容 (非 JS 渲染的空壳)。
    
    使用文本/标签比率 + 最小文本长度做启发式判断。
    """
    soup = BeautifulSoup(html, "html.parser")

    # 移除 script/style/noscript
    for tag in soup.find_all(["script", "style", "noscript"]):
        tag.decompose()

    text = soup.get_text(separator=" ", strip=True)
    text_len = len(text)

    if text_len < min_text_length:
        return False

    # 检查是否有明显的正文段落 (至少3个超过50字符的文本块)
    paragraphs = soup.find_all(["p", "article", "section"])
    long_paragraphs = [p for p in paragraphs if len(p.get_text(strip=True)) > 50]
    if len(long_paragraphs) < 2:
        # 也检查 div 中的长文本
        divs = soup.find_all("div")
        long_divs = [d for d in divs if len(d.get_text(strip=True)) > 200]
        if not long_divs:
            return False

    return True


def _is_valid_markdown(text: str, min_length: int = 200) -> bool:
    """判断返回内容是否为有效的 Markdown"""
    if len(text.strip()) < min_length:
        return False
    # 至少包含一些 Markdown 特征
    md_patterns = [
        r'^#+\s',       # 标题
        r'^\*\*',       # 粗体
        r'^\- ',        # 列表
        r'\[.*\]\(.*\)',  # 链接
        r'!\[.*\]\(.*\)',  # 图片
    ]
    matches = sum(1 for p in md_patterns if re.search(p, text, re.MULTILINE))
    return matches >= 1


# ============================================================
# Tier 1: Cloudflare Markdown
# ============================================================

async def _try_cloudflare_markdown(url: str, timeout: float = 10.0) -> Optional[FetchResult]:
    """
    尝试通过 Accept: text/markdown 获取 Cloudflare 转换的 Markdown。

    成功条件: 响应 Content-Type 包含 text/markdown, 且内容有效。
    """
    headers = {
        "Accept": "text/markdown, text/html",
        "User-Agent": "Mozilla/5.0 (compatible; VaultStream/1.0; +https://github.com/ienone/vaultstream)",
    }

    try:
        async with httpx.AsyncClient(follow_redirects=True, timeout=timeout) as client:
            resp = await client.get(url, headers=headers)
            content_type = resp.headers.get("content-type", "")

            if "text/markdown" in content_type:
                text = resp.text
                if _is_valid_markdown(text):
                    token_est = resp.headers.get("x-markdown-tokens")
                    return FetchResult(
                        url=url,
                        content=text,
                        content_type="markdown",
                        source="cloudflare_md",
                        status_code=resp.status_code,
                        token_estimate=int(token_est) if token_est else None,
                    )
    except Exception:
        pass

    return None


# ============================================================
# Tier 2: 直接 HTTP GET
# ============================================================

async def _try_direct_http(url: str, cookies: Optional[dict] = None, timeout: float = 15.0) -> Optional[FetchResult]:
    """
    尝试直接 HTTP GET 获取页面 HTML。

    成功条件: 拿到 HTML 且通过内容质量检测 (非 JS 空壳)。
    """
    headers = {
        "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36",
        "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
        "Accept-Language": "en-US,en;q=0.9,zh-CN;q=0.8,zh;q=0.7",
    }

    try:
        async with httpx.AsyncClient(follow_redirects=True, timeout=timeout, cookies=cookies) as client:
            resp = await client.get(url, headers=headers)
            if resp.status_code != 200:
                return None

            html = resp.text
            if not html or len(html) < 500:
                return None

            if _has_sufficient_content(html):
                return FetchResult(
                    url=url,
                    content=html,
                    content_type="html",
                    source="direct_http",
                    status_code=resp.status_code,
                    html=html,
                )
    except Exception:
        pass

    return None


# ============================================================
# Tier 3: crawl4ai 无头浏览器
# ============================================================

async def _try_crawl4ai(url: str, cookies: Optional[dict] = None) -> Optional[FetchResult]:
    """
    使用共享 WebKit 浏览器实例抓取页面（Tier 3 最重量级）。

    将爬取任务打包为协程，通过 browser_manager.submit_coro() 在专门的
    后台 Playwright 事件循环中安全执行并获取结果。
    """
    from app.adapters.browser import browser_manager

    delay = get_delay_for_url_sync(url)

    # 将 dict 格式 Cookie 转为 Playwright 格式
    pw_cookies = []
    if cookies:
        parsed = urlparse(url)
        domain = parsed.hostname or ""
        for k, v in cookies.items():
            pw_cookies.append({"name": k, "value": v, "domain": domain, "path": "/"})

    async def _fetch_coro() -> Optional[str]:
        browser = browser_manager.get_browser()
        context = await browser.new_context(
            viewport=browser_manager.fetch_viewport,
            user_agent=browser_manager.ua
        )
        if pw_cookies:
            await context.add_cookies(pw_cookies)
            
        try:
            page = await context.new_page()
            await page.goto(url, wait_until="domcontentloaded", timeout=30000)

            # 额外等待以确保 JS 渲染完成
            if delay > 0:
                await asyncio.sleep(delay + 1.5)
            else:
                await asyncio.sleep(1.5)

            html = await page.content()
            return html if html and len(html) >= 500 else None
        finally:
            await context.close()

    try:
        html = await browser_manager.submit_coro(_fetch_coro())
        if not html:
            return None
        return FetchResult(
            url=url,
            content=html,
            content_type="html",
            source="crawl4ai",  # 保持 source 标签兼容
            html=html,
        )
    except Exception as e:
        logger.warning(f"Tier 3 (shared browser) failed for {url}: {e}")
        return None


# ============================================================
# 统一入口
# ============================================================

async def tiered_fetch(
    url: str,
    cookies: Optional[dict] = None,
    skip_tiers: list[str] | None = None,
    verbose: bool = True,
) -> FetchResult:
    """
    三级降级获取: Cloudflare MD → Direct HTTP → crawl4ai。

    Args:
        url: 目标 URL
        cookies: 可选的 Cookie 字典
        skip_tiers: 要跳过的层级 (如 ["cloudflare_md", "direct_http"])
        verbose: 是否打印过程日志 (现在使用 logger)

    Returns:
        FetchResult 或在全部失败时抛出异常
    """
    skip = set(skip_tiers or [])

    # Tier 1: Cloudflare Markdown
    if "cloudflare_md" not in skip:
        if verbose:
            logger.debug(f"Tier 1: Trying Cloudflare Markdown for {url}...")
        result = await _try_cloudflare_markdown(url)
        if result:
            if verbose:
                token_info = f", ~{result.token_estimate} tokens" if result.token_estimate else ""
                logger.info(f"Tier 1 Success! Fetched Markdown directly ({len(result.content)} chars{token_info})")
            return result
        if verbose:
            logger.debug(f"Tier 1 Missed (Site may not support Markdown for Agents)")

    # Tier 2: Direct HTTP
    if "direct_http" not in skip:
        if verbose:
            logger.debug(f"Tier 2: Trying Direct HTTP GET for {url}...")
        result = await _try_direct_http(url, cookies=cookies)
        if result:
            if verbose:
                logger.info(f"Tier 2 Success! Fetched HTML directly ({len(result.content):,} chars)")
            return result
        if verbose:
            logger.debug(f"Tier 2 Missed (Insufficient content, likely JS rendered)")

    # Tier 3: crawl4ai
    if "crawl4ai" not in skip:
        if verbose:
            logger.debug(f"Tier 3: Launching crawl4ai headless browser for {url}...")
        result = await _try_crawl4ai(url, cookies=cookies)
        if result:
            if verbose:
                logger.info(f"Tier 3 Success! Browser rendered HTML ({len(result.content):,} chars)")
            return result

    raise RuntimeError(f"All fetch methods failed for: {url}")
