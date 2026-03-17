# 收藏读取逻辑参考自 xiaohongshu-cli:
# https://github.com/jackwener/xiaohongshu-cli (Apache-2.0 License)
# 本文件为基于 API 调用模式的原生复刻实现，非原始代码复制。

from __future__ import annotations

import asyncio
import random
from typing import Optional

import httpx
from xhshow import CryptoConfig, SessionManager, Xhshow

from app.adapters.base import PlatformAdapter
from app.adapters.favorites.base import BaseFavoritesFetcher, FavoriteItem
from app.core.logging import logger
from app.services.settings_service import get_setting_value

_USER_AGENT = (
    "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) "
    "AppleWebKit/537.36 (KHTML, like Gecko) Chrome/145.0.0.0 Safari/537.36"
)
_EDITH_HOST = "https://edith.xiaohongshu.com"


class XiaohongshuFavoritesFetcher(BaseFavoritesFetcher):
    """小红书收藏拉取器（原生 API 调用）。"""

    def __init__(self):
        config = CryptoConfig().with_overrides(
            PUBLIC_USERAGENT=_USER_AGENT,
            SIGNATURE_DATA_TEMPLATE={
                "x0": "4.2.6",
                "x1": "xhs-pc-web",
                "x2": "macOS",
                "x3": "",
                "x4": "",
            },
            SIGNATURE_XSCOMMON_TEMPLATE={
                "s0": 5,
                "s1": "",
                "x0": "1",
                "x1": "4.2.6",
                "x2": "macOS",
                "x3": "xhs-pc-web",
                "x4": "4.86.0",
                "x5": "",
                "x6": "",
                "x7": "",
                "x8": "",
                "x9": -596800761,
                "x10": 0,
                "x11": "normal",
            },
        )
        self._xhs_client = Xhshow(config)
        self._session = SessionManager(config)

    def platform_name(self) -> str:
        return "xiaohongshu"

    async def _get_cookies(self) -> dict[str, str]:
        cookie_str = await get_setting_value("xiaohongshu_cookie")
        if not cookie_str or not isinstance(cookie_str, str):
            return {}
        return PlatformAdapter.parse_cookie_str(cookie_str)

    async def check_auth(self) -> bool:
        cookies = await self._get_cookies()
        return bool(cookies.get("a1") and cookies.get("web_session"))

    @staticmethod
    def _base_headers() -> dict[str, str]:
        return {
            "user-agent": _USER_AGENT,
            "content-type": "application/json;charset=UTF-8",
            "origin": "https://www.xiaohongshu.com",
            "referer": "https://www.xiaohongshu.com/",
            "sec-ch-ua": '"Not:A-Brand";v="99", "Google Chrome";v="145", "Chromium";v="145"',
            "sec-ch-ua-mobile": "?0",
            "sec-ch-ua-platform": '"macOS"',
            "sec-fetch-dest": "empty",
            "sec-fetch-mode": "cors",
            "sec-fetch-site": "same-site",
            "accept": "application/json, text/plain, */*",
        }

    async def _request_signed_get(
        self,
        uri: str,
        *,
        cookies: dict[str, str],
        params: Optional[dict] = None,
    ) -> Optional[dict]:
        params = params or {}
        headers = {
            **self._base_headers(),
            **self._xhs_client.sign_headers_get(
                uri=uri,
                cookies=cookies,
                params=params,
                session=self._session,
            ),
        }
        proxy_url = await get_setting_value("http_proxy")
        url = f"{_EDITH_HOST}{uri}"

        for attempt in range(3):
            jitter = max(0.0, random.gauss(0.3, 0.15))
            if random.random() < 0.05:
                jitter += random.uniform(2.0, 5.0)
            await asyncio.sleep(1.0 + jitter)

            try:
                async with httpx.AsyncClient(timeout=15.0, proxy=proxy_url) as client:
                    resp = await client.get(url, params=params, headers=headers, cookies=cookies)
            except httpx.RequestError as e:
                if attempt < 2:
                    await asyncio.sleep(2**attempt)
                    continue
                logger.warning("[xhs favorites] request error: {}", e)
                return None

            if resp.status_code == 200:
                return resp.json()
            if resp.status_code in (429, 461, 471) or resp.status_code >= 500:
                if attempt < 2:
                    await asyncio.sleep((2**attempt) + random.uniform(0, 1))
                    continue
            logger.warning("[xhs favorites] http error: {}", resp.status_code)
            return None

        return None

    async def _get_self_user_id(self, cookies: dict[str, str]) -> Optional[str]:
        data = await self._request_signed_get("/api/sns/web/v2/user/me", cookies=cookies)
        if not data or not data.get("success"):
            return None
        return (data.get("data") or {}).get("user_id")

    @staticmethod
    def _extract_cover_url(note: dict) -> Optional[str]:
        cover = note.get("cover")
        if isinstance(cover, dict):
            return cover.get("url_default") or cover.get("url") or cover.get("url_pre")
        if isinstance(cover, str):
            return cover
        return note.get("cover_url")

    async def fetch_favorites(
        self,
        *,
        max_items: int = 50,
        cursor: Optional[str] = None,
    ) -> tuple[list[FavoriteItem], Optional[str]]:
        cookies = await self._get_cookies()
        if not await self.check_auth():
            return [], None

        user_id = await self._get_self_user_id(cookies)
        if not user_id:
            logger.warning("[xhs favorites] failed to resolve current user")
            return [], None

        items: list[FavoriteItem] = []
        current_cursor = cursor or ""
        seen_ids: set[str] = set()

        while len(items) < max_items:
            params = {
                "user_id": user_id,
                "cursor": current_cursor,
                "num": min(30, max_items - len(items)),
            }
            body = await self._request_signed_get(
                "/api/sns/web/v2/note/collect/page",
                cookies=cookies,
                params=params,
            )
            if not body:
                break
            if not body.get("success"):
                code = body.get("code")
                if code == -100:
                    logger.warning("[xhs favorites] session expired")
                elif code == 300012:
                    logger.warning("[xhs favorites] ip blocked")
                else:
                    logger.warning("[xhs favorites] api failed: code={}", code)
                break

            data = body.get("data", {}) or {}
            notes = data.get("notes", []) or []
            for note in notes:
                if len(items) >= max_items:
                    break
                note_id = str(note.get("note_id", "") or "")
                if not note_id or note_id in seen_ids:
                    continue
                seen_ids.add(note_id)

                user = note.get("user", {}) or {}
                items.append(
                    FavoriteItem(
                        url=f"https://www.xiaohongshu.com/explore/{note_id}",
                        title=note.get("display_title") or note.get("title"),
                        platform=self.platform_name(),
                        item_id=note_id,
                        author=user.get("nickname"),
                        cover_url=self._extract_cover_url(note),
                        content_type="note",
                    )
                )

            if not data.get("has_more", False):
                current_cursor = None
                break

            next_cursor = data.get("cursor", "")
            if not next_cursor or next_cursor == current_cursor:
                current_cursor = None
                break
            current_cursor = next_cursor

        return items, current_cursor
