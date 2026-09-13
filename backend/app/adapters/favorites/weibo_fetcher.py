"""Personal Weibo favorites through the same persisted web login."""
from pydantic import BaseModel, ConfigDict, Field, ValidationError

from app.adapters.favorites.base import BaseFavoritesFetcher, FavoriteItem
from app.adapters.weibo_session import WeiboSession, numeric_id, weibo_error
from app.adapters.weibo_parser.base import clean_html_text


class _Cursor(BaseModel):
    model_config = ConfigDict(strict=True, extra="forbid")
    uid: str = Field(pattern=r"^[1-9][0-9]*$")
    page: int = Field(ge=1)
    offset: int = Field(ge=0)


class WeiboFavoritesFetcher(BaseFavoritesFetcher):
    def platform_name(self) -> str:
        return "weibo"

    async def check_auth(self) -> bool:
        return bool((await WeiboSession.from_config()).cookies.get("SUB"))

    async def fetch_favorites(self, *, max_items=50, cursor=None):
        if max_items < 1:
            raise ValueError("max_items must be positive")
        try:
            resume = _Cursor.model_validate_json(cursor) if cursor else None
        except ValidationError:
            raise weibo_error("invalid_cursor", "微博收藏游标无效，请重置") from None
        session = await WeiboSession.from_config()
        uid = await session.current_user_id()
        if resume and resume.uid != uid:
            raise weibo_error("invalid_cursor", "微博账号已变化，请重置收藏游标")
        page = resume.page if resume else 1
        offset = resume.offset if resume else 0
        items = []
        seen_pages = set()
        while len(items) < max_items:
            rows = await session.favorites_page(uid, page)
            if offset > len(rows):
                raise weibo_error("invalid_cursor", "微博收藏页已变化，请重置游标")
            if not rows:
                return items, None
            ids = tuple(numeric_id(row.get("id")) for row in rows)
            if ids in seen_pages:
                raise weibo_error("invalid_pagination", "微博重复返回相同收藏页")
            seen_pages.add(ids)
            for index in range(offset, len(rows)):
                row = rows[index]
                author = row.get("user")
                if not isinstance(author, dict):
                    raise weibo_error("parse_failed", "微博收藏项缺少作者信息")
                items.append(FavoriteItem(url=f"https://m.weibo.cn/detail/{ids[index]}",
                    item_id=ids[index], platform="weibo", content_type="status",
                    title=clean_html_text(row.get("text") or "")[:200], author=author.get("screen_name")))
                if len(items) == max_items:
                    return items, _Cursor(uid=uid, page=page if index + 1 < len(rows) else page + 1,
                        offset=index + 1 if index + 1 < len(rows) else 0).model_dump_json()
            page += 1
            offset = 0
        return items, None
