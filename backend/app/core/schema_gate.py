from __future__ import annotations

from typing import Any

from sqlalchemy import text
from sqlalchemy.ext.asyncio import AsyncConnection


REQUIRED_SCHEMA_VERSION = 33
SCHEMA_METADATA_TABLE = "schema_metadata"
REQUIRED_FTS_TRIGGERS = frozenset(
    {"contents_fts_ai", "contents_fts_au", "contents_fts_ad"}
)
REQUIRED_TABLE_COLUMNS = {
    "schema_metadata": {"key", "value", "updated_at"},
    "contents": {"manual_edit_fields", "parse_candidate", "rich_payload"},
    "content_embeddings": {
        "chunk_index",
        "chunk_title",
        "embedding_model_signature",
        "index_status",
        "failure_reason",
        "retry_count",
        "last_attempted_at",
        "last_indexed_at",
    },
    "background_task_runs": {
        "run_id",
        "task",
        "status",
        "metadata",
        "result",
        "started_at",
        "finished_at",
    },
    "notification_messages": {
        "dedupe_key",
        "category",
        "severity",
        "source_type",
        "payload",
        "read_at",
        "muted_at",
        "snoozed_until",
        "dismissed_at",
    },
    "knowledge_events": {"id", "title", "description", "status", "updated_at"},
    "knowledge_event_members": {
        "event_id",
        "content_id",
        "role",
        "evidence_state",
        "note",
        "added_by",
    },
    "media_bookmarks": {
        "id",
        "content_id",
        "media_asset_id",
        "position_ms",
        "note",
    },
    "agent_context_summaries": {
        "id",
        "session_id",
        "run_id",
        "summary",
        "covered_message_count",
        "token_estimate",
    },
}
REQUIRED_INDEXES = frozenset(
    {
        "ix_content_embeddings_signature",
        "ix_background_task_runs_task_started",
        "ix_notification_messages_category_state",
        "ix_knowledge_event_members_event_added",
        "ix_media_bookmarks_content_asset_position",
        "ix_agent_context_summaries_session_created",
    }
)


async def ensure_schema_metadata(conn: AsyncConnection) -> None:
    """Create the metadata table without claiming that a migration completed."""
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


async def record_schema_version(conn: AsyncConnection, version: int) -> None:
    """Record one explicitly completed migration without downgrading newer data."""
    if version <= 0:
        raise ValueError("schema version must be positive")
    await ensure_schema_metadata(conn)
    current = await _read_schema_version(conn)
    recorded = max(current, version)
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
        {"version": str(recorded)},
    )


async def validate_database_schema(conn: AsyncConnection) -> dict[str, Any]:
    """Run structural checks that CI and health endpoints can rely on."""
    integrity = (await conn.execute(text("PRAGMA integrity_check"))).scalar() or "unknown"
    foreign_key_rows = (await conn.execute(text("PRAGMA foreign_key_check"))).all()
    schema_version = await _read_schema_version(conn)
    core_schema = await _validate_core_schema(conn)
    fts = await _validate_fts(conn)
    background_task_runs = await _validate_background_task_runs(conn)
    notification_messages = await _validate_notification_messages(conn)
    knowledge_events = await _validate_knowledge_events(conn)
    media_bookmarks = await _validate_media_bookmarks(conn)

    ok = (
        integrity == "ok"
        and not foreign_key_rows
        and schema_version >= REQUIRED_SCHEMA_VERSION
        and core_schema["available"]
        and fts["available"]
        and background_task_runs["available"]
        and notification_messages["available"]
        and knowledge_events["available"]
        and media_bookmarks["available"]
    )
    return {
        "status": "ok" if ok else "degraded",
        "required_schema_version": REQUIRED_SCHEMA_VERSION,
        "schema_version": schema_version,
        "integrity_check": integrity,
        "foreign_key_issues": len(foreign_key_rows),
        "core_schema": core_schema,
        "fts": fts,
        "background_task_runs": background_task_runs,
        "notification_messages": notification_messages,
        "knowledge_events": knowledge_events,
        "media_bookmarks": media_bookmarks,
    }


def schema_structures_ready(result: dict[str, Any]) -> bool:
    """Return whether startup may safely advance the managed schema version."""
    return bool(
        result.get("integrity_check") == "ok"
        and result.get("foreign_key_issues") == 0
        and result.get("core_schema", {}).get("available")
        and result.get("fts", {}).get("available")
        and result.get("background_task_runs", {}).get("available")
        and result.get("notification_messages", {}).get("available")
        and result.get("knowledge_events", {}).get("available")
        and result.get("media_bookmarks", {}).get("available")
    )


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


async def _validate_core_schema(conn: AsyncConnection) -> dict[str, Any]:
    table_names = set(
        (
            await conn.execute(
                text(
                    """
                    SELECT name
                    FROM sqlite_master
                    WHERE type = 'table'
                    """
                )
            )
        ).scalars()
    )
    missing_tables = sorted(set(REQUIRED_TABLE_COLUMNS) - table_names)
    missing_columns: dict[str, list[str]] = {}
    for table_name, required_columns in REQUIRED_TABLE_COLUMNS.items():
        if table_name not in table_names:
            continue
        rows = await conn.execute(text(f'PRAGMA table_info("{table_name}")'))
        present_columns = {str(row[1]) for row in rows}
        missing = sorted(required_columns - present_columns)
        if missing:
            missing_columns[table_name] = missing

    index_names = set(
        (
            await conn.execute(
                text(
                    """
                    SELECT name
                    FROM sqlite_master
                    WHERE type = 'index'
                    """
                )
            )
        ).scalars()
    )
    missing_indexes = sorted(REQUIRED_INDEXES - index_names)
    available = not missing_tables and not missing_columns and not missing_indexes
    return {
        "status": "ok" if available else "degraded",
        "available": available,
        "missing_tables": missing_tables,
        "missing_columns": missing_columns,
        "missing_indexes": missing_indexes,
    }


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


async def _validate_background_task_runs(conn: AsyncConnection) -> dict[str, Any]:
    table_exists = (
        await conn.execute(
            text(
                """
                SELECT 1
                FROM sqlite_master
                WHERE type = 'table' AND name = 'background_task_runs'
                """
            )
        )
    ).scalar_one_or_none()
    if not table_exists:
        return {"status": "missing", "available": False, "rows": 0}
    rows = (
        await conn.execute(text("SELECT count(*) FROM background_task_runs"))
    ).scalar() or 0
    return {"status": "ok", "available": True, "rows": int(rows)}


async def _validate_notification_messages(conn: AsyncConnection) -> dict[str, Any]:
    table_exists = (
        await conn.execute(
            text(
                """
                SELECT 1
                FROM sqlite_master
                WHERE type = 'table' AND name = 'notification_messages'
                """
            )
        )
    ).scalar_one_or_none()
    if not table_exists:
        return {"status": "missing", "available": False, "rows": 0}
    rows = (
        await conn.execute(text("SELECT count(*) FROM notification_messages"))
    ).scalar() or 0
    return {"status": "ok", "available": True, "rows": int(rows)}


async def _validate_knowledge_events(conn: AsyncConnection) -> dict[str, Any]:
    table_names = set(
        (
            await conn.execute(
                text(
                    """
                    SELECT name
                    FROM sqlite_master
                    WHERE type = 'table'
                      AND name IN ('knowledge_events', 'knowledge_event_members')
                    """
                )
            )
        ).scalars()
    )
    missing = sorted(
        {"knowledge_events", "knowledge_event_members"} - table_names
    )
    available = not missing
    rows = 0
    if available:
        rows = int(
            (await conn.execute(text("SELECT count(*) FROM knowledge_events"))).scalar()
            or 0
        )
    return {
        "status": "ok" if available else "missing",
        "available": available,
        "rows": rows,
        "missing_tables": missing,
    }


async def _validate_media_bookmarks(conn: AsyncConnection) -> dict[str, Any]:
    table_exists = (
        await conn.execute(
            text(
                """
                SELECT 1
                FROM sqlite_master
                WHERE type = 'table' AND name = 'media_bookmarks'
                """
            )
        )
    ).scalar_one_or_none()
    if not table_exists:
        return {"status": "missing", "available": False, "rows": 0}
    rows = (
        await conn.execute(text("SELECT count(*) FROM media_bookmarks"))
    ).scalar() or 0
    return {"status": "ok", "available": True, "rows": int(rows)}
