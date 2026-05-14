from __future__ import annotations

from typing import Any

from sqlalchemy import text
from sqlalchemy.ext.asyncio import AsyncConnection


REQUIRED_SCHEMA_VERSION = 29
SCHEMA_METADATA_TABLE = "schema_metadata"
REQUIRED_FTS_TRIGGERS = frozenset(
    {"contents_fts_ai", "contents_fts_au", "contents_fts_ad"}
)


async def ensure_schema_metadata(conn: AsyncConnection) -> None:
    """Record the current schema baseline used by app-managed compatibility migrations."""
    await conn.execute(
        text(
            """
            CREATE TABLE IF NOT EXISTS schema_metadata (
                key TEXT PRIMARY KEY,
                value TEXT NOT NULL,
                updated_at DATETIME DEFAULT CURRENT_TIMESTAMP
            )
            """
        )
    )
    await conn.execute(
        text(
            """
            INSERT INTO schema_metadata(key, value, updated_at)
            VALUES ('schema_version', :version, CURRENT_TIMESTAMP)
            ON CONFLICT(key) DO UPDATE SET
                value = excluded.value,
                updated_at = CURRENT_TIMESTAMP
            """
        ),
        {"version": str(REQUIRED_SCHEMA_VERSION)},
    )


async def validate_database_schema(conn: AsyncConnection) -> dict[str, Any]:
    """Run structural checks that CI and health endpoints can rely on."""
    integrity = (await conn.execute(text("PRAGMA integrity_check"))).scalar() or "unknown"
    foreign_key_rows = (await conn.execute(text("PRAGMA foreign_key_check"))).all()
    schema_version = await _read_schema_version(conn)
    fts = await _validate_fts(conn)

    ok = (
        integrity == "ok"
        and not foreign_key_rows
        and schema_version >= REQUIRED_SCHEMA_VERSION
        and fts["available"]
    )
    return {
        "status": "ok" if ok else "degraded",
        "required_schema_version": REQUIRED_SCHEMA_VERSION,
        "schema_version": schema_version,
        "integrity_check": integrity,
        "foreign_key_issues": len(foreign_key_rows),
        "fts": fts,
    }


async def _read_schema_version(conn: AsyncConnection) -> int:
    table_exists = (
        await conn.execute(
            text(
                """
                SELECT 1
                FROM sqlite_master
                WHERE type = 'table' AND name = :table_name
                """
            ),
            {"table_name": SCHEMA_METADATA_TABLE},
        )
    ).scalar_one_or_none()
    if not table_exists:
        return 0
    value = (
        await conn.execute(
            text("SELECT value FROM schema_metadata WHERE key = 'schema_version'")
        )
    ).scalar_one_or_none()
    try:
        return int(value or 0)
    except (TypeError, ValueError):
        return 0


async def _validate_fts(conn: AsyncConnection) -> dict[str, Any]:
    table_exists = (
        await conn.execute(
            text(
                """
                SELECT 1
                FROM sqlite_master
                WHERE type = 'table' AND name = 'contents_fts'
                """
            )
        )
    ).scalar_one_or_none()
    if not table_exists:
        return {"status": "missing", "available": False, "triggers": 0}

    trigger_rows = (
        await conn.execute(
            text(
                """
                SELECT name
                FROM sqlite_master
                WHERE type = 'trigger'
                  AND name IN ('contents_fts_ai', 'contents_fts_au', 'contents_fts_ad')
                """
            )
        )
    ).scalars().all()
    present = set(trigger_rows)
    missing = sorted(REQUIRED_FTS_TRIGGERS - present)
    content_rows = (await conn.execute(text("SELECT count(*) FROM contents"))).scalar() or 0
    indexed_rows = (await conn.execute(text("SELECT count(*) FROM contents_fts"))).scalar() or 0
    counts_match = int(indexed_rows) == int(content_rows)
    available = not missing and counts_match
    return {
        "status": "ok" if available else "degraded",
        "available": available,
        "indexed_rows": int(indexed_rows),
        "content_rows": int(content_rows),
        "indexed_matches_content": counts_match,
        "triggers": len(present),
        "missing_triggers": missing,
    }
