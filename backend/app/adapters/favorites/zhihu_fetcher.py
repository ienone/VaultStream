# 收藏读取逻辑参考自 ZhihuCollectionsPro:
# https://github.com/ienone/ZhihuCollectionsPro (MIT License)
# 本文件为基于 API 调用模式的原生复刻实现，非原始代码复制。

from __future__ import annotations

import asyncio
import random
from datetime import datetime, timezone
from typing import Optional

import httpx

from app.adapters.base import PlatformAdapter
from app.adapters.favorites.base import BaseFavoritesFetcher, FavoriteItem
from app.adapters.zhihu import ZhihuAdapter
from app.core.logging import logger
from app.core.time_utils import utcnow
from app.services.settings_service import get_setting_value


class ZhihuFavoritesFetcher(BaseFavoritesFetcher):
    """知乎收藏夹拉取器（原生 API 调用）。"""

    _MAX_RETRY = 3
    _PAGE_SIZE = 20

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

    async def _api_get(self, url: str, cookies: dict[str, str]) -> Optional[dict]:
        proxy_url = await get_setting_value("http_proxy")
        headers = {
            **ZhihuAdapter.API_HEADERS,
            "x-xsrftoken": cookies.get("_xsrf", ""),
        }

        async with httpx.AsyncClient(
            headers=headers,
            cookies=cookies,
            follow_redirects=True,
            timeout=15.0,
            proxy=proxy_url,
        ) as client:
            for attempt in range(self._MAX_RETRY):
                try:
                    jitter = max(0.0, random.gauss(0.5, 0.2))
                    await asyncio.sleep(1.0 + jitter)

                    resp = await client.get(url)
                    if resp.status_code == 200:
                        return resp.json()
                    if resp.status_code in (401, 403):
                        logger.warning("[zhihu favorites] auth failed, status={}", resp.status_code)
                        return None
                    if resp.status_code == 429 or resp.status_code >= 500:
                        wait = (2**attempt) + random.uniform(0, 1)
                        logger.warning(
                            "[zhihu favorites] status={}, retry in {:.1f}s",
                            resp.status_code,
                            wait,
                        )
                        await asyncio.sleep(wait)
                        continue
                    logger.warning("[zhihu favorites] request failed, status={}", resp.status_code)
                    return None
                except httpx.RequestError as e:
                    logger.warning("[zhihu favorites] request error: {}", e)
                    if attempt < self._MAX_RETRY - 1:
                        await asyncio.sleep(2**attempt)
        return None

    async def _fetch_user_collections(self, cookies: dict[str, str]) -> list[dict]:
        me_data = await self._api_get("https://www.zhihu.com/api/v4/me", cookies)
        if not me_data or "url_token" not in me_data:
            logger.warning("[zhihu favorites] failed to resolve current user")
            return []

        user_id = me_data["url_token"]
        collections: list[dict] = []
        offset = 0

        while True:
            url = (
                f"https://www.zhihu.com/api/v4/people/{user_id}/collections"
                f"?limit={self._PAGE_SIZE}&offset={offset}"
            )
            data = await self._api_get(url, cookies)
            if not data:
                break

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
            return [], None

        collections = await self._fetch_user_collections(cookies)
        if not collections:
            return [], None

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
                if not data:
                    break

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
