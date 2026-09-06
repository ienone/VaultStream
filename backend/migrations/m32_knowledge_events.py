"""M32: create evidence-backed knowledge events and membership tables."""

import asyncio

from app.core.db_adapter import engine
from app.core.schema_gate import record_schema_version
from app.models import KnowledgeEvent, KnowledgeEventMember


async def migrate() -> None:
    async with engine.begin() as conn:
        await conn.run_sync(KnowledgeEvent.__table__.create, checkfirst=True)
        await conn.run_sync(KnowledgeEventMember.__table__.create, checkfirst=True)
        await record_schema_version(conn, 32)
    print("Migration complete: m32_knowledge_events")


if __name__ == "__main__":
    asyncio.run(migrate())
