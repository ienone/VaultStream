# 收藏读取逻辑参考自 ZhihuCollectionsPro:
# https://github.com/ienone/ZhihuCollectionsPro (MIT License)
# 本文件为基于 API 调用模式的原生复刻实现，非原始代码复制。
from __future__ import annotations

import asyncio
import re
from datetime import datetime, timezone
from typing import Optional
from urllib.parse import urlparse

import httpx

from app.adapters.base import PlatformAdapter
from app.adapters.favorites.base import BaseFavoritesFetcher, FavoriteItem
from app.adapters.favorites.errors import FavoritesFetchError
from app.adapters.utils.anti_risk import (
    exponential_backoff,
    merge_response_cookies,
    truncated_gaussian_delay,
)
from app.adapters.zhihu import ZhihuAdapter
from app.core.logging import logger
from app.core.time_utils import utcnow
from app.services.settings_service import get_setting_value


class ZhihuFavoritesFetcher(BaseFavoritesFetcher):
    """知乎收藏夹拉取器（原生 API 调用）。"""

    _MAX_RETRY = 3
    _PAGE_SIZE = 20

    def __init__(self):
        self._zse_refresh_attempted = False

    def platform_name(self) -> str:
        return "zhihu"

    async def _get_cookies(self) -> dict[str, str]:
        cookie_str = await get_setting_value("zhihu_cookie")
        if not cookie_str or not isinstance(cookie_str, str):
            return {}
        return PlatformAdapter.parse_cookie_str(cookie_str)

    async def check_auth(self) -> bool:
        cookies = await self._get_cookies()
        return bool(cookies.get("z_c0"))

    @staticmethod
    def _to_refresh_page_url(target_url: str) -> str:
        """Convert API endpoint URL to a browser page URL for ZSE refresh."""
        fallback = "https://www.zhihu.com/"
        if not target_url:
            return fallback

        try:
            parsed = urlparse(target_url)
        except Exception:
            return fallback

        host = (parsed.netloc or "").lower()
        path = parsed.path or "/"
        if not host.endswith("zhihu.com"):
            return fallback

        if not path.startswith("/api/"):
            normalized = path if path.startswith("/") else f"/{path}"
            return f"https://www.zhihu.com{normalized}"

        if path == "/api/v4/me":
            return fallback

        people_collections_match = re.match(r"^/api/v4/people/([^/]+)/collections", path)
        if people_collections_match:
            user_token = people_collections_match.group(1)
            return f"https://www.zhihu.com/people/{user_token}/collections"

        collection_items_match = re.match(r"^/api/v4/collections/([^/]+)/items", path)
        if collection_items_match:
            collection_id = collection_items_match.group(1)
            return f"https://www.zhihu.com/collection/{collection_id}"

        return fallback

    async def _try_refresh_zhihu_fingerprint(self, target_url: str, cookies: dict[str, str]) -> bool:
        if self._zse_refresh_attempted:
            return False
        self._zse_refresh_attempted = True
        refresh_url = self._to_refresh_page_url(target_url)

        try:
            from app.services.browser_auth_service import browser_auth_service

            ok = await browser_auth_service.refresh_zhihu_zse_cookie(refresh_url)
            if not ok:
                return False

            latest = await self._get_cookies()
            if latest:
                cookies.clear()
                cookies.update(latest)
            logger.info(
                "[zhihu favorites] fingerprint refreshed by page={}, retry request target={}",
                refresh_url,
                target_url,
            )
            return True
        except Exception as e:
            logger.warning("[zhihu favorites] fingerprint refresh failed: {}", e)
            return False

    async def _api_get(self, url: str, cookies: dict[str, str]) -> dict:
        proxy_url = await get_setting_value("http_proxy")

        async with httpx.AsyncClient(
            follow_redirects=True,
            timeout=15.0,
            proxy=proxy_url,
        ) as client:
            for attempt in range(self._MAX_RETRY):
                try:
                    await asyncio.sleep(
                        truncated_gaussian_delay(
                            base_delay=1.0,
                            mean=0.5,
                            sigma=0.2,
                        )
                    )

                    headers = {
                        **ZhihuAdapter.API_HEADERS,
                        "x-xsrftoken": cookies.get("_xsrf", ""),
                    }
                    resp = await client.get(url, headers=headers, cookies=cookies)
                    merge_response_cookies(cookies, resp)

                    if resp.status_code == 200:
                        try:
                            return resp.json()
                        except ValueError as e:
                            raise FavoritesFetchError(
                                code="parse_failed",
                                message="Zhihu API returned invalid JSON",
                                hint="知乎返回数据异常，请稍后重试",
                                retryable=True,
                            ) from e

                    if resp.status_code in (401, 403):
                        refreshed = await self._try_refresh_zhihu_fingerprint(url, cookies)
                        if refreshed and attempt < self._MAX_RETRY - 1:
                            await asyncio.sleep(exponential_backoff(attempt, jitter_max=0.5))
                            continue
                        logger.warning("[zhihu favorites] auth failed, status={}", resp.status_code)
                        raise FavoritesFetchError(
                            code="auth_required",
                            message="Zhihu auth expired or invalid",
                            hint="知乎登录状态失效，请重新登录",
                            auth_required=True,
                        )

                    if resp.status_code == 429 or resp.status_code >= 500:
                        wait = exponential_backoff(attempt)
                        logger.warning(
                            "[zhihu favorites] status={}, retry in {:.1f}s",
                            resp.status_code,
                            wait,
                        )
                        if attempt < self._MAX_RETRY - 1:
                            await asyncio.sleep(wait)
                            continue
                        if resp.status_code == 429:
                            raise FavoritesFetchError(
                                code="rate_limited",
                                message="Zhihu API rate limited",
                                hint="请求过于频繁，请稍后重试或降低同步速率",
                                retryable=True,
                            )
                        raise FavoritesFetchError(
                            code="upstream_error",
                            message=f"Zhihu API returned {resp.status_code}",
                            hint="知乎服务异常，请稍后重试",
                            retryable=True,
                        )

                    logger.warning("[zhihu favorites] request failed, status={}", resp.status_code)
                    raise FavoritesFetchError(
                        code="fetch_failed",
                        message=f"Zhihu API returned {resp.status_code}",
                        hint="请求失败，请检查 Cookie 或网络配置",
                    )
                except httpx.RequestError as e:
                    logger.warning("[zhihu favorites] request error: {}", e)
                    if attempt < self._MAX_RETRY - 1:
                        await asyncio.sleep(exponential_backoff(attempt, jitter_max=0.0))
                        continue
                    raise FavoritesFetchError(
                        code="network_error",
                        message="Zhihu request failed",
                        hint="网络请求失败，请检查代理或网络后重试",
                        retryable=True,
                    ) from e

        raise FavoritesFetchError(
            code="fetch_failed",
            message="Zhihu request failed after retries",
            hint="请求失败，请稍后重试",
            retryable=True,
        )

    async def _fetch_user_collections(self, cookies: dict[str, str]) -> list[dict]:
        me_data = await self._api_get("https://www.zhihu.com/api/v4/me", cookies)
        if "url_token" not in me_data:
            logger.warning("[zhihu favorites] failed to resolve current user")
            raise FavoritesFetchError(
                code="auth_required",
                message="Failed to resolve Zhihu account",
                hint="无法读取知乎账号信息，请重新登录",
                auth_required=True,
            )

        user_id = me_data["url_token"]
        collections: list[dict] = []
        offset = 0

        while True:
            url = (
                f"https://www.zhihu.com/api/v4/people/{user_id}/collections"
                f"?limit={self._PAGE_SIZE}&offset={offset}"
            )
            data = await self._api_get(url, cookies)
            for item in data.get("data", []):
                collections.append(
                    {
                        "id": str(item.get("id", "")),
                        "title": item.get("title", ""),
                        "item_count": int(item.get("item_count", 0) or 0),
                    }
                )

            paging = data.get("paging", {})
            if paging.get("is_end", True):
                break
            offset += self._PAGE_SIZE

        return collections

    @staticmethod
    def _to_datetime(timestamp: object) -> Optional[datetime]:
        if timestamp is None:
            return None
        try:
            return datetime.fromtimestamp(int(timestamp), tz=timezone.utc).replace(tzinfo=None)
        except (TypeError, ValueError, OSError):
            return None

    async def fetch_favorites(
        self,
        *,
        max_items: int = 50,
        cursor: Optional[str] = None,
    ) -> tuple[list[FavoriteItem], Optional[str]]:
        del cursor  # Zhihu collection APIs are offset-based; this phase returns no cursor.
        cookies = await self._get_cookies()
        if not cookies.get("z_c0"):
            raise FavoritesFetchError(
                code="auth_required",
                message="Zhihu auth cookie missing",
                hint="请先在设置中配置知乎 Cookie",
                auth_required=True,
            )

        self._zse_refresh_attempted = False

        collections = await self._fetch_user_collections(cookies)

        items: list[FavoriteItem] = []
        seen_urls: set[str] = set()

        for collection in collections:
            if len(items) >= max_items:
                break

            coll_id = collection.get("id")
            if not coll_id:
                continue

            offset = 0
            while len(items) < max_items:
                url = (
                    f"https://www.zhihu.com/api/v4/collections/{coll_id}/items"
                    f"?limit={self._PAGE_SIZE}&offset={offset}"
                )
                data = await self._api_get(url, cookies)
                for entry in data.get("data", []):
                    if len(items) >= max_items:
                        break

                    content = entry.get("content", {}) or {}
                    content_type = str(content.get("type", "") or "")
                    item_url = str(content.get("url", "") or "")

                    if content_type == "answer":
                        question = content.get("question", {}) or {}
                        qid = question.get("id")
                        aid = content.get("id")
                        if qid and aid:
                            item_url = f"https://www.zhihu.com/question/{qid}/answer/{aid}"
                    elif content_type == "article":
                        aid = content.get("id")
                        if aid:
                            item_url = f"https://zhuanlan.zhihu.com/p/{aid}"
                    elif content_type == "zvideo":
                        zid = content.get("id")
                        if zid:
                            item_url = f"https://www.zhihu.com/zvideo/{zid}"
                    elif not item_url:
                        continue

                    if not item_url or item_url in seen_urls:
                        continue
                    seen_urls.add(item_url)

                    title = content.get("title") or (content.get("question", {}) or {}).get("title")
                    author = content.get("author", {}) or {}
                    favorited_at = self._to_datetime(
                        entry.get("created_time") or entry.get("updated_time")
                    )
                    if favorited_at is None:
                        favorited_at = utcnow()

                    items.append(
                        FavoriteItem(
                            url=item_url,
                            title=title,
                            platform=self.platform_name(),
                            item_id=str(content.get("id", "") or ""),
                            author=author.get("name"),
                            cover_url=content.get("title_image") or content.get("image_url"),
                            content_type=content_type or None,
                            favorited_at=favorited_at,
                        )
                    )

                paging = data.get("paging", {})
                if paging.get("is_end", True):
                    break
                offset += self._PAGE_SIZE

        return items, None
