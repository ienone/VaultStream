from __future__ import annotations

from typing import Any

from alembic.migration import MigrationContext
from alembic.script import ScriptDirectory
from sqlalchemy import inspect, text
from sqlalchemy.ext.asyncio import AsyncConnection

from app.core.database import migration_config
from app.models import Base

REQUIRED_FTS_TRIGGERS = frozenset({"contents_fts_ai", "contents_fts_au", "contents_fts_ad"})


async def validate_database_schema(conn: AsyncConnection) -> dict[str, Any]:
    """ORM is the structure contract; only non-ORM FTS needs separate checks."""
    integrity = (await conn.execute(text("PRAGMA integrity_check"))).scalar()
    foreign_keys = (await conn.execute(text("PRAGMA foreign_key_check"))).all()
    revisions = await conn.run_sync(lambda connection: MigrationContext.configure(connection).get_current_heads())
    required = ScriptDirectory.from_config(migration_config()).get_heads()
    core_schema = await conn.run_sync(_validate_core_schema)
    fts = await validate_content_fts(conn)
    result = {
        "required_revisions": required,
        "revisions": list(revisions),
        "integrity_check": integrity,
        "foreign_key_issues": len(foreign_keys),
        "core_schema": core_schema,
        "fts": fts,
    }
    # Preserve the diagnostics response without four independent table validators.
    for name in ("background_task_runs", "notification_messages", "knowledge_events", "media_bookmarks"):
        tables = {name, "knowledge_event_members"} if name == "knowledge_events" else {name}
        missing = sorted(tables.intersection(core_schema["missing_tables"]))
        result[name] = {
            "status": "missing" if missing else "ok",
            "available": not missing,
            "rows": 0 if missing else (await conn.execute(text(f'SELECT count(*) FROM "{name}"'))).scalar_one(),
        }
        if name == "knowledge_events":
            result[name]["missing_tables"] = missing
    ready = (
        integrity == "ok" and not foreign_keys
        and core_schema["available"] and fts["available"]
        and set(revisions) == set(required)
    )
    result["status"] = "ok" if ready else "degraded"
    return result


def _validate_core_schema(conn) -> dict[str, Any]:
    inspector = inspect(conn)
    table_names = set(inspector.get_table_names())
    missing_tables = sorted(set(Base.metadata.tables) - table_names)
    missing_columns = {}
    missing_indexes = []
    for table in Base.metadata.tables.values():
        if table.name not in table_names:
            continue
        columns = {column["name"] for column in inspector.get_columns(table.name)}
        missing = sorted(set(table.columns.keys()) - columns)
        if missing:
            missing_columns[table.name] = missing
        indexes = {index["name"] for index in inspector.get_indexes(table.name)}
        missing_indexes.extend(index.name for index in table.indexes if index.name not in indexes)
    available = not missing_tables and not missing_columns and not missing_indexes
    return {
        "status": "ok" if available else "degraded",
        "available": available,
        "missing_tables": missing_tables,
        "missing_columns": missing_columns,
        "missing_indexes": sorted(missing_indexes),
    }


async def validate_content_fts(conn: AsyncConnection) -> dict[str, Any]:
    exists = (await conn.execute(text(
        "SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = 'contents_fts'"
    ))).scalar_one_or_none()
    if not exists:
        return {"status": "missing", "available": False, "triggers": 0}
    present = set((await conn.execute(text("""
        SELECT name FROM sqlite_master WHERE type = 'trigger'
        AND name IN ('contents_fts_ai', 'contents_fts_au', 'contents_fts_ad')
    """))).scalars())
    missing = sorted(REQUIRED_FTS_TRIGGERS - present)
    content_rows = (await conn.execute(text("SELECT count(*) FROM contents"))).scalar_one()
    indexed_rows = (await conn.execute(text("SELECT count(*) FROM contents_fts"))).scalar_one()
    counts_match = indexed_rows == content_rows
    available = not missing and counts_match
    return {
        "status": "ok" if available else "degraded",
        "available": available,
        "indexed_rows": indexed_rows,
        "content_rows": content_rows,
        "indexed_matches_content": counts_match,
        "triggers": len(present),
        "missing_triggers": missing,
    }
