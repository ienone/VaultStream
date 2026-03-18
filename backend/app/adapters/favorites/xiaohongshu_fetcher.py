# 收藏读取逻辑参考自 xiaohongshu-cli:
# https://github.com/jackwener/xiaohongshu-cli (Apache-2.0 License)
# 本文件为基于 API 调用模式的原生复刻实现，非原始代码复制。
from __future__ import annotations

import asyncio
from typing import Optional

import httpx
from xhshow import SessionManager, Xhshow

from app.adapters.base import PlatformAdapter
from app.adapters.favorites.base import BaseFavoritesFetcher, FavoriteItem
from app.adapters.favorites.errors import FavoritesFetchError
from app.adapters.utils.anti_risk import (
    exponential_backoff,
    merge_response_cookies,
    progressive_captcha_cooldown,
    truncated_gaussian_delay,
)
from app.adapters.xiaohongshu_profile import (
    DEFAULT_XHS_USER_AGENT,
    build_xhs_crypto_config,
)
from app.core.logging import logger
from app.services.settings_service import get_setting_value

_USER_AGENT = DEFAULT_XHS_USER_AGENT
_EDITH_HOST = "https://edith.xiaohongshu.com"
_MAX_RETRY = 3


class XiaohongshuFavoritesFetcher(BaseFavoritesFetcher):
    """小红书收藏拉取器（原生 API 调用）。"""

    def __init__(self):
        config = build_xhs_crypto_config(_USER_AGENT)
        self._xhs_client = Xhshow(config)
        self._session = SessionManager(config)
        self._base_request_delay = 1.0
        self._request_delay = 1.0
        self._verify_count = 0

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
    ) -> dict:
        params = params or {}
        proxy_url = await get_setting_value("http_proxy")
        url = f"{_EDITH_HOST}{uri}"

        for attempt in range(_MAX_RETRY):
            await asyncio.sleep(
                truncated_gaussian_delay(
                    base_delay=self._request_delay,
                    mean=0.3,
                    sigma=0.15,
                    long_pause_probability=0.05,
                    long_pause_range=(2.0, 5.0),
                )
            )

            try:
                sign_headers = self._xhs_client.sign_headers_get(
                    uri=uri,
                    cookies=cookies,
                    params=params,
                    session=self._session,
                )
            except Exception as e:
                logger.warning("[xhs favorites] sign failed: {}", e)
                raise FavoritesFetchError(
                    code="sign_failed",
                    message="Xiaohongshu signature generation failed",
                    hint="签名失败，请重新登录小红书并稍后重试",
                ) from e

            headers = {**self._base_headers(), **sign_headers}

            try:
                async with httpx.AsyncClient(timeout=15.0, proxy=proxy_url) as client:
                    resp = await client.get(url, params=params, headers=headers, cookies=cookies)
            except httpx.RequestError as e:
                if attempt < _MAX_RETRY - 1:
                    await asyncio.sleep(exponential_backoff(attempt, jitter_max=0.0))
                    continue
                logger.warning("[xhs favorites] request error: {}", e)
                raise FavoritesFetchError(
                    code="network_error",
                    message="Xiaohongshu request failed",
                    hint="网络请求失败，请检查代理或网络后重试",
                    retryable=True,
                ) from e

            merge_response_cookies(cookies, resp)

            if resp.status_code == 200:
                self._verify_count = 0
                try:
                    return resp.json()
                except ValueError as e:
                    raise FavoritesFetchError(
                        code="parse_failed",
                        message="Xiaohongshu API returned invalid JSON",
                        hint="接口返回异常，请稍后重试",
                        retryable=True,
                    ) from e

            if resp.status_code in (461, 471):
                self._verify_count += 1
                self._request_delay = max(self._request_delay, self._base_request_delay * 2)
                cooldown = progressive_captcha_cooldown(self._verify_count)
                logger.warning(
                    "[xhs favorites] captcha/risk triggered status={}, cooldown {:.1f}s",
                    resp.status_code,
                    cooldown,
                )
                if attempt < _MAX_RETRY - 1:
                    await asyncio.sleep(cooldown)
                    continue
                raise FavoritesFetchError(
                    code="captcha_required",
                    message="Xiaohongshu risk verification required",
                    hint="触发风控验证，请在网页端完成验证后重试",
                    retryable=True,
                )

            self._verify_count = 0

            if resp.status_code in (429,) or resp.status_code >= 500:
                if attempt < _MAX_RETRY - 1:
                    await asyncio.sleep(exponential_backoff(attempt))
                    continue
                if resp.status_code == 429:
                    raise FavoritesFetchError(
                        code="rate_limited",
                        message="Xiaohongshu API rate limited",
                        hint="请求频率过高，建议稍后重试或降低同步速率",
                        retryable=True,
                    )
                raise FavoritesFetchError(
                    code="upstream_error",
                    message=f"Xiaohongshu API returned {resp.status_code}",
                    hint="平台服务异常，请稍后重试",
                    retryable=True,
                )

            logger.warning("[xhs favorites] http error: {}", resp.status_code)
            raise FavoritesFetchError(
                code="fetch_failed",
                message=f"Xiaohongshu API returned {resp.status_code}",
                hint="请求失败，请检查账号状态和网络配置",
            )

        raise FavoritesFetchError(
            code="fetch_failed",
            message="Xiaohongshu request failed after retries",
            hint="请求失败，请稍后重试",
            retryable=True,
        )

    async def _get_self_user_id(self, cookies: dict[str, str]) -> Optional[str]:
        data = await self._request_signed_get("/api/sns/web/v2/user/me", cookies=cookies)
        if not data.get("success"):
            code = data.get("code")
            if code == -100:
                raise FavoritesFetchError(
                    code="auth_required",
                    message="Xiaohongshu session expired",
                    hint="小红书登录已失效，请重新登录",
                    auth_required=True,
                )
            raise FavoritesFetchError(
                code="fetch_failed",
                message="Failed to resolve current Xiaohongshu user",
                hint="无法读取当前账号信息，请稍后重试",
            )
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
            raise FavoritesFetchError(
                code="auth_required",
                message="Xiaohongshu auth cookie missing",
                hint="请先在设置中配置小红书 Cookie",
                auth_required=True,
            )

        self._request_delay = self._base_request_delay
        self._verify_count = 0

        user_id = await self._get_self_user_id(cookies)
        if not user_id:
            logger.warning("[xhs favorites] failed to resolve current user")
            raise FavoritesFetchError(
                code="auth_required",
                message="Failed to resolve Xiaohongshu user",
                hint="账号信息读取失败，请重新登录后重试",
                auth_required=True,
            )

        items: list[FavoriteItem] = []
        current_cursor = cursor or ""
        seen_ids: set[str] = set()
        session_refresh_attempted = False

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
            if not body.get("success"):
                code = body.get("code")
                if code == -100:
                    logger.warning("[xhs favorites] session expired")
                    if not session_refresh_attempted:
                        latest_cookies = await self._get_cookies()
                        if latest_cookies and latest_cookies != cookies:
                            cookies = latest_cookies
                            session_refresh_attempted = True
                            logger.info("[xhs favorites] refreshed cookies from settings, retry current page")
                            continue
                    raise FavoritesFetchError(
                        code="auth_required",
                        message="Xiaohongshu session expired",
                        hint="小红书登录已过期，请重新登录",
                        auth_required=True,
                    )
                elif code == 300012:
                    logger.warning("[xhs favorites] ip blocked")
                    raise FavoritesFetchError(
                        code="ip_blocked",
                        message="Xiaohongshu request blocked by risk control",
                        hint="IP 已被风控拦截，请更换网络环境后重试",
                        retryable=True,
                    )
                else:
                    logger.warning("[xhs favorites] api failed: code={}", code)
                    raise FavoritesFetchError(
                        code="fetch_failed",
                        message=f"Xiaohongshu API failed with code={code}",
                        hint="接口返回失败，请稍后重试",
                    )

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
