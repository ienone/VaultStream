"""Alembic CLI and application startup share the configured SQLite connection."""
import asyncio

from alembic import context

from app.core.db_adapter import engine
from app.models import Base


def include_object(obj, name, type_, reflected, compare_to):
    # FTS and SSE use explicit initialization/migration SQL, not ORM tables.
    return not (
        type_ == "table" and reflected
        and (name.startswith("contents_fts") or name == "realtime_events")
    )


def run_migrations(connection):
    # This dedicated migration connection closes after the transaction. Disable
    # FK actions before any DML so SQLite batch DROP cannot cascade into children.
    connection.exec_driver_sql("PRAGMA foreign_keys=OFF")
    if connection.exec_driver_sql("PRAGMA foreign_keys").scalar():
        raise RuntimeError("Migrations require a fresh connection without an active write transaction")
    context.configure(
        connection=connection,
        target_metadata=Base.metadata,
        render_as_batch=True,
        include_object=include_object,
    )
    with context.begin_transaction():
        context.run_migrations()
        violations = connection.exec_driver_sql("PRAGMA foreign_key_check").fetchall()
        if violations:
            raise RuntimeError(f"Migration left foreign key violations: {violations[:10]}")


async def run_async_migrations():
    async with engine.begin() as connection:
        await connection.run_sync(run_migrations)
    await engine.dispose()


if context.is_offline_mode():
    context.configure(url=engine.url, target_metadata=Base.metadata, literal_binds=True)
    with context.begin_transaction():
        context.run_migrations()
elif context.config.attributes.get("connection") is not None:
    run_migrations(context.config.attributes["connection"])
else:
    asyncio.run(run_async_migrations())
