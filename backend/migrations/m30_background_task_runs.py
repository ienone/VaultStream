"""M30: create and backfill the persistent background task run ledger."""

import asyncio

from app.core.database import migrate_background_task_runs
from app.core.db_adapter import engine
from app.core.schema_gate import record_schema_version
from app.models import BackgroundTaskRun


async def migrate() -> None:
    async with engine.begin() as conn:
        await conn.run_sync(BackgroundTaskRun.__table__.create, checkfirst=True)
        await migrate_background_task_runs(conn)
        await record_schema_version(conn, 30)
    print("Migration complete: m30_background_task_runs")


if __name__ == "__main__":
    asyncio.run(migrate())
