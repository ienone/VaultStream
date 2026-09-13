"""Read-only Weibo web session shared by login checks and favorites.

Contracts: RSSHub weibo/user-bookmarks (mobile identity), Weibo web
all_fav used by the author's 445022 backup script. Anonymous responses
checked 2026-09-13: mobile config ok=1/login=false, desktop redirects.
"""
from __future__ import annotations

import httpx

from app.adapters.base import PlatformAdapter
from app.adapters.utils.anti_risk import merge_response_cookies
from app.services.config_service import ConfigService


def weibo_error(code: str, message: str):
    from app.adapters.favorites.errors import FavoritesFetchError
    return FavoritesFetchError(code=code, message=message,
        hint="请在账号中心重新登录微博" if code == "auth_required" else "本轮进度未推进，请检查平台状态后重试",
        auth_required=code == "auth_required", retryable=code != "auth_required")


def numeric_id(value) -> str:
    if type(value) not in (str, int) or not str(value).isdigit() or int(value) <= 0:
        raise weibo_error("parse_failed", "微博响应缺少有效账号或内容 ID")
    return str(value)


class WeiboSession:
    def __init__(self, cookies: dict[str, str]):
        self.cookies = dict(cookies)

    @classmethod
    async def from_config(cls):
        raw = await ConfigService().get_platform_cookie_string("weibo", fresh=True)
        return cls(PlatformAdapter.parse_cookie_str(raw or ""))

    async def _get(self, url: str, *, params=None):
        if not self.cookies.get("SUB"):
            raise weibo_error("auth_required", "未配置微博登录")
        try:
            async with httpx.AsyncClient(timeout=20, proxy=await ConfigService().get_http_proxy(),
                headers={"User-Agent": "Mozilla/5.0", "Referer": "https://weibo.com/", "Accept": "application/json"}) as client:
                response = await client.get(url, params=params, cookies=self.cookies, follow_redirects=False)
            if response.status_code in (301, 302, 303, 307, 308, 401):
                raise weibo_error("auth_required", "微博会话需要重新登录")
            if response.status_code in (403, 418):
                raise weibo_error("verification_required", "微博要求访问验证，请在平台网页处理")
            if response.status_code == 429:
                raise weibo_error("rate_limited", "微博请求频率受限")
            if response.status_code != 200:
                raise weibo_error("upstream_error", f"微博返回 HTTP {response.status_code}")
            body = response.json()
        except httpx.HTTPError:
            raise weibo_error("network_error", "微博请求失败") from None
        except ValueError:
            raise weibo_error("parse_failed", "微博未返回 JSON") from None
        if not isinstance(body, dict) or type(body.get("ok")) is not int:
            raise weibo_error("parse_failed", "微博响应缺少明确状态")
        if body["ok"] != 1:
            raise weibo_error("upstream_error", "微博接口未接受当前请求")
        return body, response

    async def _persist(self, response):
        original = dict(self.cookies)
        merge_response_cookies(self.cookies, response)
        await ConfigService().persist_refreshed_platform_cookies("weibo", original, self.cookies)

    async def current_user_id(self) -> str:
        body, response = await self._get("https://m.weibo.cn/api/config")
        data = body.get("data")
        if not isinstance(data, dict) or type(data.get("login")) is not bool:
            raise weibo_error("parse_failed", "微博配置响应缺少登录状态")
        if not data["login"]:
            raise weibo_error("auth_required", "微博登录已失效")
        uid = numeric_id(data.get("uid"))
        await self._persist(response)
        return uid

    async def favorites_page(self, uid: str, page: int) -> list[dict]:
        body, response = await self._get("https://weibo.com/ajax/favorites/all_fav", params={"uid": uid, "page": page})
        data = body.get("data")
        if not isinstance(data, list) or any(not isinstance(item, dict) for item in data):
            raise weibo_error("parse_failed", "微博收藏响应缺少内容列表")
        await self._persist(response)
        return data
