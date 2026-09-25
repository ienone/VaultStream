"""Anonymous first-party Zhihu pages, with isolated browser contexts."""
from playwright.async_api import Error as BrowserError, TimeoutError as BrowserTimeout

from app.adapters.browser import browser_manager
from app.adapters.base import ParsedContent
from app.adapters.errors import NonRetryableAdapterError, RetryableAdapterError
from app.core.safe_fetch import is_safe_url
from .article_parser import parse_article
from .question_parser import parse_question
from .people_parser import parse_people

_PAGES = {
    "article": ("https://zhuanlan.zhihu.com/p/", "articles", parse_article),
    "question": ("https://www.zhihu.com/question/", "questions", parse_question),
    "user_profile": ("https://www.zhihu.com/people/", "users", parse_people),
}

# Challenge pages also contain js-initialData. Wait for the requested entity,
# not merely for that script tag or for the first navigation's HTTP status.
_TARGET_READY = """([collection, id]) => {
    try {
        const entities = JSON.parse(document.getElementById('js-initialData').textContent)
            .initialState.entities[collection];
        if (collection === 'users') {
            return Object.values(entities).some(e => e.urlToken === id && !!e.name);
        }
        const entity = entities[id];
        return entity && String(entity.id) === id && !!entity.title
            && (collection !== 'articles' || !!entity.content);
    } catch { return false; }
}"""


async def read_public_page(content_type: str, content_id: str, proxy: str | None = None) -> ParsedContent:
    prefix, collection, parser = _PAGES[content_type]
    url = prefix + content_id
    if not is_safe_url(url):
        raise NonRetryableAdapterError("知乎页面地址不可安全访问")

    async def read():
        browser = await browser_manager.get_chromium_browser()
        version = browser.version.split('.')[0]
        ua = ("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 "
              f"(KHTML, like Gecko) Chrome/{version}.0.0.0 Safari/537.36")
        context = await browser.new_context(
            user_agent=ua,
            viewport=browser_manager.fetch_viewport,
            extra_http_headers={"sec-ch-ua": (
                f'"Chromium";v="{version}", "Not_A Brand";v="8", "Google Chrome";v="{version}"'
            )},
            **({"proxy": {"server": proxy}} if proxy else {}),
        )
        try:
            async def guard(route, request):
                if is_safe_url(request.url):
                    await route.continue_()
                else:
                    await route.abort()

            await context.route("**/*", guard)
            page = await context.new_page()
            response = await page.goto(url, wait_until="domcontentloaded", timeout=15000)
            if response and response.status in (404, 410):
                raise NonRetryableAdapterError("知乎内容不存在或已不可访问")
            if response and response.status == 429:
                raise RetryableAdapterError("知乎请求受限，请稍后重试")
            await page.wait_for_function(_TARGET_READY, arg=[collection, content_id], timeout=6000)
            parsed = parser(await page.content(), url)
            if parsed is None:
                raise NonRetryableAdapterError("知乎页面未提供目标内容")
            return parsed
        finally:
            await context.close()

    try:
        return await browser_manager.submit_coro(read())
    except BrowserTimeout as error:
        raise RetryableAdapterError("知乎页面读取超时") from error
    except BrowserError as error:
        raise RetryableAdapterError("知乎页面读取失败") from error
