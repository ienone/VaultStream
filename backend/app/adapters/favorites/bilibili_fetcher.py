"""Bilibili personal video folders, using the persisted platform login.

Read contracts: bpi-rs fav/{info,list} and login/login_info/nav;
public folder and resource responses checked on 2026-09-13.
"""
from __future__ import annotations

from datetime import datetime, timezone

import httpx
from pydantic import BaseModel, ConfigDict, Field, ValidationError

from app.adapters.base import PlatformAdapter
from app.adapters.favorites.base import BaseFavoritesFetcher, FavoriteItem
from app.adapters.favorites.errors import FavoritesFetchError
from app.adapters.utils.anti_risk import merge_response_cookies
from app.services.config_service import ConfigService


class _Contract(BaseModel):
    model_config = ConfigDict(strict=True)


class _Account(_Contract):
    isLogin: bool
    mid: int = Field(gt=0)


class _Folder(_Contract):
    id: int = Field(gt=0)
    title: str


class _Folders(_Contract):
    count: int = Field(ge=0)
    list: list[_Folder] | None


class _Author(_Contract):
    name: str


class _Video(_Contract):
    id: int = Field(gt=0)
    type: int
    title: str
    cover: str
    upper: _Author
    fav_time: int = Field(ge=0)
    bvid: str | None = Field(default=None, pattern=r"^(?:BV[0-9A-Za-z]{10})?$")


class _Page(_Contract):
    medias: list[_Video] | None
    has_more: bool


class _Cursor(_Contract):
    mid: int = Field(gt=0)
    folder_id: int = Field(gt=0)
    page: int = Field(ge=1)
    offset: int = Field(ge=0, lt=20)


def _failure(code: str, message: str, *, auth: bool = False) -> FavoritesFetchError:
    return FavoritesFetchError(
        code=code, message=message,
        hint="请重新登录 Bilibili" if auth else "本轮未推进游标，请检查平台状态后重试",
        auth_required=auth, retryable=not auth,
    )


class BilibiliFavoritesFetcher(BaseFavoritesFetcher):
    def platform_name(self) -> str:
        return "bilibili"

    async def _cookies(self) -> dict[str, str]:
        saved = await ConfigService().get_platform_cookie_string("bilibili", fresh=True)
        return PlatformAdapter.parse_cookie_str(saved or "")

    async def check_auth(self) -> bool:
        # Status polling only checks configured credentials; fetching verifies
        # the account with nav before reading private folders.
        return bool((await self._cookies()).get("SESSDATA"))

    async def _get(self, path: str, cookies: dict[str, str], params: dict | None = None) -> dict:
        try:
            async with httpx.AsyncClient(
                timeout=20, proxy=await ConfigService().get_http_proxy(),
                headers={"User-Agent": "Mozilla/5.0", "Referer": "https://www.bilibili.com/"},
            ) as client:
                response = await client.get("https://api.bilibili.com" + path, params=params, cookies=cookies)
            if response.status_code != 200:
                raise _failure("upstream_error", f"Bilibili 返回 HTTP {response.status_code}")
            payload = response.json()
        except httpx.HTTPError:
            raise _failure("network_error", "Bilibili 收藏请求失败") from None
        except ValueError:
            raise _failure("parse_failed", "Bilibili 未返回有效 JSON") from None
        if not isinstance(payload, dict) or type(payload.get("code")) is not int:
            raise _failure("parse_failed", "Bilibili 响应缺少状态码")
        if payload["code"] == -101:
            raise _failure("auth_required", "Bilibili 登录已失效", auth=True)
        if payload["code"] != 0:
            raise _failure("upstream_error", f"Bilibili 收藏接口失败，代码 {payload['code']}")
        if not isinstance(payload.get("data"), dict):
            raise _failure("parse_failed", "Bilibili 响应缺少数据对象")
        original = dict(cookies)
        merge_response_cookies(cookies, response)
        await ConfigService().persist_refreshed_platform_cookies("bilibili", original, cookies)
        return payload["data"]

    async def fetch_favorites(
        self, *, max_items: int = 50, cursor: str | None = None,
    ) -> tuple[list[FavoriteItem], str | None]:
        if max_items < 1:
            raise ValueError("max_items must be positive")
        try:
            resume = _Cursor.model_validate_json(cursor) if cursor else None
        except ValidationError:
            raise _failure("invalid_cursor", "Bilibili 收藏游标无效") from None
        cookies = await self._cookies()
        if not cookies.get("SESSDATA"):
            raise _failure("auth_required", "未配置 Bilibili 登录", auth=True)
        try:
            account = _Account.model_validate(await self._get("/x/web-interface/nav", cookies))
            if not account.isLogin:
                raise _failure("auth_required", "Bilibili 登录已失效", auth=True)
            if resume and resume.mid != account.mid:
                raise _failure("invalid_cursor", "Bilibili 账号已变化，请重置收藏游标")
            folders = _Folders.model_validate(await self._get(
                "/x/v3/fav/folder/created/list-all", cookies, {"up_mid": account.mid},
            ))
            entries = folders.list or []
            if len(entries) != folders.count:
                raise _failure("incomplete_collections", "Bilibili 收藏夹发现结果不完整")
            start = 0
            if resume:
                start = next((i for i, folder in enumerate(entries) if folder.id == resume.folder_id), -1)
                if start < 0:
                    raise _failure("invalid_cursor", "Bilibili 续同步收藏夹已不存在，请重置游标")
            items: list[FavoriteItem] = []
            for folder_index in range(start, len(entries)):
                folder = entries[folder_index]
                page_number = resume.page if resume and folder_index == start else 1
                offset = resume.offset if resume and folder_index == start else 0
                while True:
                    page = _Page.model_validate(await self._get(
                        "/x/v3/fav/resource/list", cookies,
                        {"media_id": folder.id, "pn": page_number, "ps": 20, "platform": "web", "order": "mtime"},
                    ))
                    videos = page.medias or []
                    if (page.has_more and not videos) or offset > len(videos):
                        raise _failure("invalid_pagination", "Bilibili 收藏分页未返回可续接内容")
                    for index in range(offset, len(videos)):
                        video = videos[index]
                        usable = video.type == 2 and bool(video.bvid)
                        items.append(FavoriteItem(
                            url=f"https://www.bilibili.com/video/{video.bvid}/" if usable else "",
                            title=video.title, platform="bilibili", item_id=str(video.id),
                            author=video.upper.name, cover_url=video.cover,
                            favorited_at=datetime.fromtimestamp(video.fav_time, tz=timezone.utc),
                            content_type="video", collection_id=str(folder.id), collection_title=folder.title,
                            skip_reason=None if usable else "平台内容已不可用或不属于支持的视频收藏",
                        ))
                        if len(items) == max_items:
                            if index + 1 < len(videos):
                                position = (folder.id, page_number, index + 1)
                            elif page.has_more:
                                position = (folder.id, page_number + 1, 0)
                            elif folder_index + 1 < len(entries):
                                position = (entries[folder_index + 1].id, 1, 0)
                            else:
                                return items, None
                            return items, _Cursor(mid=account.mid, folder_id=position[0], page=position[1], offset=position[2]).model_dump_json()
                    if not page.has_more:
                        break
                    page_number += 1
                    offset = 0
            return items, None
        except ValidationError:
            raise _failure("parse_failed", "Bilibili 收藏响应不符合已核验契约") from None
