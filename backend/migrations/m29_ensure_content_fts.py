"""M29: ensure FTS schema and record the managed schema baseline."""
import asyncio

from app.core.database import ensure_content_fts
from app.core.db_adapter import engine
from app.core.schema_gate import record_schema_version


async def migrate() -> None:
    async with engine.begin() as conn:
        await ensure_content_fts(conn)
        await record_schema_version(conn, 29)
    print("Migration complete: m29_ensure_content_fts")


if __name__ == "__main__":
    asyncio.run(migrate())
