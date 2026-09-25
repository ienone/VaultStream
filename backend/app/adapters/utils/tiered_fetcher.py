"""
分层内容获取模块 (Tiered Content Fetcher)

HTTP：一次内容协商请求，接受 Markdown 或 HTML，不重复请求同一页面。
浏览器：共享 Playwright/WebKit (适用 JS 渲染页面)

每一级尝试后判断内容质量, 不达标则降级到下一级。
"""

import re
import asyncio
from dataclasses import dataclass, field
from typing import Optional
from urllib.parse import urlparse
from loguru import logger

import httpx
from bs4 import BeautifulSoup

from app.adapters.errors import NonRetryableAdapterError, RetryableAdapterError
from app.core.crawler_config import get_delay_for_url_sync
from app.core.safe_fetch import is_safe_url, safe_client_get

_MAX_FETCH_TEXT_BYTES = 5 * 1024 * 1024
_TEXT_CONTENT_TYPES = (
    "text/",
    "application/xhtml+xml",
    "application/xml",
)


@dataclass
class FetchResult:
    """统一的获取结果"""
    url: str
    content: str  # markdown 或 html
    content_type: str  # "markdown" | "html"
    source: str  # "cloudflare_md" | "direct_http" | "browser"
    status_code: int = 200
    html: str = ""  # 原始 HTML，供正文定位使用
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

    title = soup.title.get_text(" ", strip=True).lower() if soup.title else ""
    challenge_title = title in {
        "just a moment", "just a moment...", "verify you are human",
        "attention required! | cloudflare", "sina visitor system", "安全验证", "访问验证",
    }
    login_title = re.match(r"^(?:sign in|log in|登录)(?:\s*[-—|]|$)", title)
    if challenge_title or login_title or soup.select_one('#challenge-form, #captcha, meta#zh-zse-ck'):
        return False

    # 移除 script/style/noscript
    for tag in soup.find_all(["script", "style", "noscript"]):
        tag.decompose()

    text = soup.get_text(separator=" ", strip=True)
    text_len = len(text)

    # A short article can be complete; navigation text cannot establish that.
    bodies = soup.select('[itemprop~="articleBody"]') or soup.select('article')
    if len(bodies) == 1 and len(bodies[0].get_text(strip=True)) >= 120:
        return True

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
# HTTP 内容协商
# ============================================================

async def _try_http(url: str, cookies: Optional[dict] = None, timeout: float = 15.0) -> Optional[FetchResult]:
    """Negotiate Markdown and reuse an HTML response from the same GET."""
    headers = {
        "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/145.0.0.0 Safari/537.36",
        "Accept": "text/markdown, text/html;q=0.9,application/xhtml+xml;q=0.8",
        "Accept-Language": "zh-CN,zh;q=0.9,en;q=0.8",
    }
    try:
        async with httpx.AsyncClient(timeout=timeout, cookies=cookies) as client:
            resp = await safe_client_get(
                client, url, headers=headers, cookies=cookies,
                max_bytes=_MAX_FETCH_TEXT_BYTES,
                allowed_content_type_prefixes=_TEXT_CONTENT_TYPES,
            )
        if resp.status_code in (404, 410):
            raise NonRetryableAdapterError(f"页面不存在或已删除（HTTP {resp.status_code}）")
        if resp.status_code == 429:
            raise RetryableAdapterError("网站限制请求频率，请稍后重试")
        if resp.status_code != 200:
            return None
        content_type = resp.headers.get("content-type", "").lower()
        if "text/markdown" in content_type and _is_valid_markdown(resp.text):
            token_est = resp.headers.get("x-markdown-tokens", "")
            return FetchResult(
                url=resp.url, content=resp.text, content_type="markdown",
                source="cloudflare_md", token_estimate=int(token_est) if token_est.isdigit() else None,
            )
        if "html" in content_type and _has_sufficient_content(resp.text):
            return FetchResult(
                url=resp.url, content=resp.text, html=resp.text,
                content_type="html", source="direct_http",
            )
    except httpx.RequestError:
        return None
    return None


async def _try_browser(url: str, cookies: Optional[dict] = None) -> Optional[FetchResult]:
    """
    使用共享 WebKit 浏览器实例抓取页面。

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

    async def _fetch_coro() -> Optional[tuple[str, str]]:
        if not is_safe_url(url):
            return None

        browser = browser_manager.get_browser()
        context = await browser.new_context(
            viewport=browser_manager.fetch_viewport,
            user_agent=browser_manager.ua
        )
        if pw_cookies:
            await context.add_cookies(pw_cookies)
            
        try:
            async def _route_guard(route, request) -> None:
                if is_safe_url(request.url):
                    await route.continue_()
                else:
                    await route.abort()

            await context.route("**/*", _route_guard)
            page = await context.new_page()
            response = await page.goto(url, wait_until="domcontentloaded", timeout=30000)
            if response is None or response.status != 200:
                return None

            # 额外等待以确保 JS 渲染完成
            if delay > 0:
                await asyncio.sleep(delay + 1.5)
            else:
                await asyncio.sleep(1.5)

            html = await page.content()
            return (page.url, html) if html and _has_sufficient_content(html) else None
        finally:
            await context.close()

    try:
        result = await browser_manager.submit_coro(_fetch_coro())
        if result is None:
            return None
        final_url, html = result
        return FetchResult(
            url=final_url,
            content=html,
            content_type="html",
            source="browser",
            html=html,
        )
    except Exception as e:
        logger.warning(f"Shared browser fetch failed for {url}: {e}")
        return None


# ============================================================
# 统一入口
# ============================================================

async def tiered_fetch(
    url: str,
    cookies: Optional[dict] = None,
) -> FetchResult:
    """One negotiated HTTP request, then browser rendering for unreadable HTML."""
    result = await _try_http(url, cookies=cookies)
    if result is None:
        result = await _try_browser(url, cookies=cookies)
    if result is None:
        raise NonRetryableAdapterError("网页未返回可读取正文")
    return result
