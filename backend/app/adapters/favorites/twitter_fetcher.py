"""X bookmarks via the current web app and the saved platform cookie.

The browser loads X's own client, so query IDs/features/request headers stay
with that client. Only the documented Bookmarks GET variables are changed
for pagination. No CLI login, browser-profile extraction or challenge bypass.
"""
from __future__ import annotations

import hashlib
import json

from pydantic import BaseModel, ConfigDict, Field, ValidationError

from app.adapters.base import PlatformAdapter
from app.adapters.favorites.base import BaseFavoritesFetcher, FavoriteItem
from app.adapters.favorites.errors import FavoritesFetchError
from app.services.config_service import ConfigService


def _error(code, message):
    return FavoritesFetchError(code=code, message=message,
        hint="请在 X 网页确认登录，并在账号中心更新登录 Cookie" if code == "auth_required" else "请检查 X 网页状态后重试；未推进收藏游标",
        auth_required=code == "auth_required", retryable=code != "auth_required")


class _Cursor(BaseModel):
    model_config = ConfigDict(strict=True, extra="forbid")
    session_hash: str = Field(pattern=r"^[a-f0-9]{64}$")
    cursor: str | None = None
    offset: int = Field(default=0, ge=0)


def parse_bookmarks(payload: dict) -> tuple[list[FavoriteItem], str | None]:
    """Parse the current Timeline v2 contract; malformed is never empty success."""
    if not isinstance(payload, dict):
        raise _error("parse_failed", "X 书签响应不是对象")
    if payload.get("errors"):
        codes = {entry.get("code") for entry in payload["errors"] if isinstance(entry, dict)}
        if codes & {32, 89, 215}:
            raise _error("auth_required", "X 登录已失效")
        raise _error("upstream_error", "X 未接受书签请求")
    try:
        from app.adapters.twitter_web import timeline_instructions
        instructions = timeline_instructions(payload, "Bookmarks")
        if not isinstance(instructions, list):
            raise TypeError
        entries = []
        for instruction in instructions:
            kind = instruction["type"]
            if kind == "TimelineAddEntries":
                entries.extend(instruction["entries"])
            elif kind == "TimelineReplaceEntry":
                entries.append(instruction["entry"])
            elif kind not in ("TimelineClearCache", "TimelineTerminateTimeline"):
                raise ValueError
        items, bottom = [], None
        for entry in entries:
            content = entry["content"]
            if content.get("entryType") == "TimelineTimelineCursor":
                if content["cursorType"] == "Bottom":
                    bottom = content["value"]
                    if not isinstance(bottom, str) or not bottom:
                        raise ValueError
                continue
            if content.get("entryType") != "TimelineTimelineItem":
                raise ValueError
            result = content["itemContent"]["tweet_results"]["result"]
            if result.get("__typename") == "TweetWithVisibilityResults":
                result = result["tweet"]
            if result.get("__typename") != "Tweet":
                # Do not silently discard unavailable entries with unknown IDs.
                raise ValueError
            tweet_id = result["rest_id"]
            if not isinstance(tweet_id, str) or not tweet_id.isdigit():
                raise ValueError
            text = result["legacy"]["full_text"]
            if not isinstance(text, str):
                raise ValueError
            items.append(FavoriteItem(url=f"https://x.com/i/status/{tweet_id}", platform="twitter",
                item_id=tweet_id, title=text[:200], content_type="tweet"))
        if items and bottom is None:
            # A documented explicit termination is also a valid last page.
            if not any(i.get("type") == "TimelineTerminateTimeline" and i.get("direction") == "Bottom" for i in instructions):
                raise ValueError
        return items, bottom if items else None
    except (KeyError, TypeError, ValueError, AttributeError):
        raise _error("parse_failed", "X 书签响应不符合已核对的时间线结构") from None


class TwitterBookmarksFetcher(BaseFavoritesFetcher):
    def platform_name(self):
        return "twitter"

    async def _cookies(self):
        raw = await ConfigService().get_platform_cookie_string("twitter", fresh=True)
        return PlatformAdapter.parse_cookie_str(raw or "")

    async def check_auth(self):
        cookies = await self._cookies()
        return bool(cookies.get("auth_token") and cookies.get("ct0"))

    async def fetch_favorites(self, *, max_items=50, cursor=None):
        if max_items < 1:
            raise ValueError("max_items must be positive")
        cookies = await self._cookies()
        if not cookies.get("auth_token") or not cookies.get("ct0"):
            raise _error("auth_required", "X 书签需要已登录网页的 auth_token 和 ct0 Cookie")
        session_hash = hashlib.sha256(cookies["auth_token"].encode()).hexdigest()
        try:
            resume = _Cursor.model_validate_json(cursor) if cursor else _Cursor(session_hash=session_hash)
        except ValidationError:
            raise _error("invalid_cursor", "X 收藏游标无效，请重置") from None
        if resume.session_hash != session_hash:
            raise _error("invalid_cursor", "X 登录会话已替换，请重置书签游标")
        # A fixed page count preserves offsets when max_items changes between runs.
        payload, refreshed = await self._read_page(cookies, resume.cursor)
        items, bottom = parse_bookmarks(payload)
        if resume.offset > len(items):
            raise _error("invalid_cursor", "X 书签页发生变化，请重置游标")
        selected = items[resume.offset:resume.offset + max_items]
        end = resume.offset + len(selected)
        if end < len(items):
            next_cursor = _Cursor(session_hash=session_hash, cursor=resume.cursor, offset=end).model_dump_json()
        elif bottom:
            if bottom == resume.cursor:
                raise _error("invalid_pagination", "X 返回了重复书签游标")
            next_cursor = _Cursor(session_hash=session_hash, cursor=bottom).model_dump_json()
        else:
            next_cursor = None
        await ConfigService().persist_refreshed_platform_cookies("twitter", cookies, refreshed)
        return selected, next_cursor

    async def _read_page(self, cookies, cursor):
        from app.adapters.twitter_web import read_x_page
        return await read_x_page(cookies, cursor=cursor)
