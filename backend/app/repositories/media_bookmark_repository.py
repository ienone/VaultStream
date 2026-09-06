"""Persistence boundary for user-created media bookmarks."""

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models import Content, MediaAsset, MediaBookmark


class MediaBookmarkRepository:
    def __init__(self, db: AsyncSession):
        self.db = db

    async def get_content(self, content_id: int) -> Content | None:
        return await self.db.scalar(
            select(Content).where(
                Content.id == content_id,
                Content.deleted_at.is_(None),
            )
        )

    async def get_asset(self, media_asset_id: int) -> MediaAsset | None:
        return await self.db.get(MediaAsset, media_asset_id)

    async def list_for_asset(
        self,
        *,
        content_id: int,
        media_asset_id: int,
    ) -> list[MediaBookmark]:
        rows = await self.db.scalars(
            select(MediaBookmark)
            .where(
                MediaBookmark.content_id == content_id,
                MediaBookmark.media_asset_id == media_asset_id,
            )
            .order_by(MediaBookmark.position_ms, MediaBookmark.id)
        )
        return list(rows)

    async def get(
        self,
        *,
        bookmark_id: int,
        content_id: int,
    ) -> MediaBookmark | None:
        return await self.db.scalar(
            select(MediaBookmark).where(
                MediaBookmark.id == bookmark_id,
                MediaBookmark.content_id == content_id,
            )
        )
