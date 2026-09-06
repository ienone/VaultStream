"""M31: create the persistent notification inbox."""

import asyncio

from app.core.database import migrate_notification_inbox
from app.core.db_adapter import engine
from app.core.schema_gate import record_schema_version
from app.models import NotificationMessage


async def migrate() -> None:
    async with engine.begin() as conn:
        await conn.run_sync(NotificationMessage.__table__.create, checkfirst=True)
        backfilled = await migrate_notification_inbox(conn)
        await record_schema_version(conn, 31)
    print(f"Migration complete: m31_notification_inbox (backfilled={backfilled})")


if __name__ == "__main__":
    asyncio.run(migrate())
