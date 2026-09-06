"""Validated user bookmarks for persisted audio and video assets."""

from dataclasses import dataclass
from typing import Any

from sqlalchemy.exc import IntegrityError
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.time_utils import utcnow
from app.models import MediaBookmark, MediaType
from app.repositories.media_bookmark_repository import MediaBookmarkRepository
from app.schemas.media import MediaBookmarkCreate, MediaBookmarkUpdate


@dataclass(slots=True)
class MediaBookmarkError(Exception):
    message: str
    code: str
    status_code: int

    def __str__(self) -> str:
        return self.message


class MediaBookmarkService:
    def __init__(self, db: AsyncSession):
        self.db = db
        self.repository = MediaBookmarkRepository(db)

    async def list_bookmarks(
        self,
        *,
        content_id: int,
        media_asset_id: int,
    ) -> dict[str, Any]:
        await self._require_asset(content_id, media_asset_id)
        bookmarks = await self.repository.list_for_asset(
            content_id=content_id,
            media_asset_id=media_asset_id,
        )
        return {"items": [self._serialize(item) for item in bookmarks]}

    async def create_bookmark(
        self,
        *,
        content_id: int,
        request: MediaBookmarkCreate,
    ) -> dict[str, Any]:
        asset = await self._require_asset(content_id, request.media_asset_id)
        position_ms = self._position_ms(request.position_seconds)
        self._validate_position(position_ms, asset.duration_ms)
        bookmark = MediaBookmark(
            content_id=content_id,
            media_asset_id=asset.id,
            position_ms=position_ms,
            note=self._optional_note(request.note),
        )
        self.db.add(bookmark)
        try:
            await self.db.commit()
        except IntegrityError as error:
            await self.db.rollback()
            raise MediaBookmarkError(
                "A bookmark already exists at this position",
                "media_bookmark_exists",
                409,
            ) from error
        await self.db.refresh(bookmark)
        return self._serialize(bookmark)

    async def update_bookmark(
        self,
        *,
        content_id: int,
        bookmark_id: int,
        request: MediaBookmarkUpdate,
    ) -> dict[str, Any]:
        bookmark = await self._require_bookmark(content_id, bookmark_id)
        if "note" in request.model_fields_set:
            bookmark.note = self._optional_note(request.note)
        bookmark.updated_at = utcnow()
        await self.db.commit()
        await self.db.refresh(bookmark)
        return self._serialize(bookmark)

    async def delete_bookmark(
        self,
        *,
        content_id: int,
        bookmark_id: int,
    ) -> dict[str, Any]:
        bookmark = await self._require_bookmark(content_id, bookmark_id)
        await self.db.delete(bookmark)
        await self.db.commit()
        return {
            "deleted": True,
            "bookmark_id": bookmark_id,
            "content_id": content_id,
        }

    async def _require_asset(self, content_id: int, media_asset_id: int):
        if await self.repository.get_content(content_id) is None:
            raise MediaBookmarkError(
                "Content not found",
                "media_bookmark_content_not_found",
                404,
            )
        asset = await self.repository.get_asset(media_asset_id)
        if asset is None or asset.content_id != content_id:
            raise MediaBookmarkError(
                "Media asset does not belong to this content",
                "media_bookmark_asset_mismatch",
                409,
            )
        if asset.media_type not in {MediaType.AUDIO, MediaType.VIDEO}:
            raise MediaBookmarkError(
                "Bookmarks require an audio or video asset",
                "media_bookmark_asset_not_playable",
                409,
            )
        return asset

    async def _require_bookmark(
        self,
        content_id: int,
        bookmark_id: int,
    ) -> MediaBookmark:
        bookmark = await self.repository.get(
            bookmark_id=bookmark_id,
            content_id=content_id,
        )
        if bookmark is None:
            raise MediaBookmarkError(
                "Media bookmark not found",
                "media_bookmark_not_found",
                404,
            )
        return bookmark

    @staticmethod
    def _position_ms(position_seconds: float) -> int:
        return round(position_seconds * 1000)

    @staticmethod
    def _validate_position(position_ms: int, duration_ms: int | None) -> None:
        if position_ms < 0 or (duration_ms is not None and position_ms > duration_ms):
            raise MediaBookmarkError(
                "Bookmark position is outside the media duration",
                "media_bookmark_position_out_of_range",
                422,
            )

    @staticmethod
    def _optional_note(value: str | None) -> str | None:
        normalized = (value or "").strip()
        return normalized or None

    @staticmethod
    def _serialize(bookmark: MediaBookmark) -> dict[str, Any]:
        return {
            "id": bookmark.id,
            "content_id": bookmark.content_id,
            "media_asset_id": bookmark.media_asset_id,
            "position_seconds": bookmark.position_ms / 1000,
            "note": bookmark.note,
            "created_at": bookmark.created_at,
            "updated_at": bookmark.updated_at,
        }
