"""M33: create validated user bookmarks for persisted audio and video."""

import asyncio

from app.core.db_adapter import engine
from app.core.schema_gate import record_schema_version
from app.models import MediaBookmark


async def migrate() -> None:
    async with engine.begin() as conn:
        await conn.run_sync(MediaBookmark.__table__.create, checkfirst=True)
        await record_schema_version(conn, 33)
    print("Migration complete: m33_media_bookmarks")


if __name__ == "__main__":
    asyncio.run(migrate())
