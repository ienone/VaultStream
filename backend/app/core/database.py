"""
数据库连接管理
"""
import json
from datetime import datetime, timezone
from typing import Any

from sqlalchemy import text
from sqlalchemy.ext.asyncio import AsyncConnection

from app.core.db_adapter import AsyncSessionLocal, engine
from app.core.schema_gate import (
    REQUIRED_SCHEMA_VERSION,
    ensure_schema_metadata,
    record_schema_version,
    schema_structures_ready,
    validate_database_schema,
)
from app.models import Base


async def init_db():
    """初始化数据库基础结构。"""
    async with engine.begin() as conn:
        await conn.run_sync(Base.metadata.create_all)
        await ensure_content_edit_schema(conn)
        await ensure_media_schema(conn)
        await migrate_agent_tool_messages(conn)
        await migrate_background_task_runs(conn)
        # Embedding is an individual run, not an independent worker. Retire its
        # duplicate last-result projection; the durable run ledger remains.
        await conn.execute(text("DELETE FROM system_settings WHERE key = 'background_task_state:embedding_index'"))
        await migrate_notification_inbox(conn)
        await ensure_content_embeddings_schema(conn)
        await ensure_content_fts(conn)
        await ensure_schema_metadata(conn)
        inspection = await validate_database_schema(conn)
        if schema_structures_ready(inspection):
            await record_schema_version(conn, REQUIRED_SCHEMA_VERSION)


async def migrate_agent_tool_messages(conn: AsyncConnection) -> int:
    """Finish the old JSON/text message format once, preserving message content."""
    marker = "_migration:agent_tool_message_payload"
    if (await conn.execute(text("SELECT 1 FROM system_settings WHERE key = :key"), {"key": marker})).scalar():
        return 0
    rows = (await conn.execute(text(
        "SELECT id, content, payload FROM agent_messages WHERE role = 'tool'"
    ))).mappings().all()
    changed = 0
    for row in rows:
        payload = json.loads(row["payload"]) if row["payload"] else {}
        if not isinstance(payload, dict):
            payload = {}
        if "result" in payload or "error" in payload:
            continue
        try:
            decoded = json.loads(row["content"] or "")
        except (ValueError, TypeError):
            decoded = None
        if isinstance(decoded, dict):
            payload.update(decoded if "result" in decoded or "error" in decoded else {"result": decoded})
        else:
            payload["result"] = {"message": row["content"] or ""}
        await conn.execute(text("UPDATE agent_messages SET payload = :payload WHERE id = :id"),
                           {"id": row["id"], "payload": json.dumps(payload, ensure_ascii=False)})
        changed += 1
    await conn.execute(text(
        "INSERT INTO system_settings (key, value, category, description, updated_at) "
        "VALUES (:key, 'true', 'migrations', 'Normalize stored tool messages', CURRENT_TIMESTAMP)"
    ), {"key": marker})
    return changed


async def ensure_content_edit_schema(conn: AsyncConnection) -> None:
    """Ensure existing SQLite content rows can preserve manual revisions."""
    rows = await conn.execute(text("PRAGMA table_info(contents)"))
    columns = {row[1] for row in rows.fetchall()}
    additions = {
        "manual_edit_fields": "JSON DEFAULT '[]'",
        "parse_candidate": "JSON DEFAULT NULL",
    }
    for name, ddl in additions.items():
        if name not in columns:
            await conn.execute(text(f"ALTER TABLE contents ADD COLUMN {name} {ddl}"))

    await conn.execute(
        text(
            """
            UPDATE contents
            SET manual_edit_fields = '[]'
            WHERE manual_edit_fields IS NULL
            """
        )
    )


async def ensure_content_embeddings_schema(conn: AsyncConnection) -> None:
    """Ensure existing SQLite databases have the current semantic index columns."""
    rows = await conn.execute(text("PRAGMA table_info(content_embeddings)"))
    columns = {row[1] for row in rows.fetchall()}
    additions = {
        "chunk_index": "INTEGER DEFAULT -1",
        "chunk_title": "TEXT DEFAULT NULL",
        "embedding_model_signature": "VARCHAR(240) DEFAULT NULL",
        "index_status": "VARCHAR(40) DEFAULT 'indexed'",
        "failure_reason": "TEXT DEFAULT NULL",
        "retry_count": "INTEGER DEFAULT 0",
        "last_attempted_at": "DATETIME DEFAULT NULL",
        "last_indexed_at": "DATETIME DEFAULT NULL",
    }
    for name, ddl in additions.items():
        if name not in columns:
            await conn.execute(text(f"ALTER TABLE content_embeddings ADD COLUMN {name} {ddl}"))

    await conn.execute(
        text(
            """
            UPDATE content_embeddings
            SET chunk_index = -1
            WHERE chunk_index IS NULL
            """
        )
    )
    await conn.execute(
        text(
            """
            UPDATE content_embeddings
            SET index_status = 'indexed'
            WHERE index_status IS NULL OR index_status = ''
            """
        )
    )
    await conn.execute(
        text(
            """
            UPDATE content_embeddings
            SET last_indexed_at = indexed_at
            WHERE last_indexed_at IS NULL AND indexed_at IS NOT NULL
            """
        )
    )
    await conn.execute(
        text(
            """
            UPDATE content_embeddings
            SET last_attempted_at = last_indexed_at
            WHERE last_attempted_at IS NULL AND last_indexed_at IS NOT NULL
            """
        )
    )
    await conn.execute(
        text(
            "CREATE INDEX IF NOT EXISTS ix_content_embeddings_signature "
            "ON content_embeddings (embedding_model_signature)"
        )
    )
    await conn.execute(
        text(
            "CREATE INDEX IF NOT EXISTS ix_content_embeddings_status "
            "ON content_embeddings (index_status)"
        )
    )
    await conn.execute(
        text(
            "CREATE INDEX IF NOT EXISTS ix_content_embeddings_attempted_at "
            "ON content_embeddings (last_attempted_at)"
        )
    )


async def ensure_media_schema(conn: AsyncConnection) -> None:
    """Ensure existing databases enforce stable media asset identities."""
    await conn.execute(
        text(
            "CREATE UNIQUE INDEX IF NOT EXISTS uq_media_asset_content_role_position "
            "ON media_assets (content_id, media_type, role, position)"
        )
    )


async def migrate_background_task_runs(conn: AsyncConnection) -> None:
    """Move legacy per-task JSON run lists into the persistent run ledger."""
    rows = await conn.execute(
        text(
            """
            SELECT key, value
            FROM system_settings
            WHERE key LIKE 'background_task_runs:%'
            """
        )
    )
    legacy_rows = rows.fetchall()
    if not legacy_rows:
        return

    migrated_keys: list[str] = []
    for key, raw_value in legacy_rows:
        task_name = str(key).split(":", 1)[-1]
        try:
            parsed = json.loads(raw_value) if isinstance(raw_value, str) else raw_value
        except (TypeError, ValueError):
            parsed = None
        if not isinstance(parsed, list):
            continue

        if any(
            not isinstance(item, dict)
            or not str(item.get("run_id") or "").strip()
            for item in parsed
        ):
            continue

        for item in parsed:
            run_id = str(item["run_id"]).strip()
            started_at = _parse_legacy_run_datetime(item.get("started_at")) or datetime.now(
                timezone.utc
            ).replace(tzinfo=None)
            finished_at = _parse_legacy_run_datetime(item.get("finished_at"))
            known = {
                "run_id",
                "task",
                "status",
                "started_at",
                "finished_at",
                "error",
                "result",
            }
            metadata = {name: value for name, value in item.items() if name not in known}
            await conn.execute(
                text(
                    """
                    INSERT INTO background_task_runs (
                        run_id, task, status, started_at, finished_at, error,
                        metadata, result, created_at, updated_at
                    ) VALUES (
                        :run_id, :task, :status, :started_at, :finished_at, :error,
                        :metadata, :result, :created_at, :updated_at
                    )
                    ON CONFLICT(run_id) DO NOTHING
                    """
                ),
                {
                    "run_id": run_id,
                    "task": str(item.get("task") or task_name),
                    "status": str(item.get("status") or "unknown"),
                    "started_at": started_at,
                    "finished_at": finished_at,
                    "error": item.get("error"),
                    "metadata": json.dumps(metadata, ensure_ascii=False),
                    "result": json.dumps(item.get("result"), ensure_ascii=False),
                    "created_at": started_at,
                    "updated_at": finished_at or started_at,
                },
            )
        migrated_keys.append(str(key))

    for key in migrated_keys:
        await conn.execute(
            text("DELETE FROM system_settings WHERE key = :key"),
            {"key": key},
        )


async def migrate_notification_inbox(conn: AsyncConnection) -> int:
    """Backfill the notification inbox once from the persistent run ledger."""
    marker_key = "_migration:m31_notification_inbox"
    marker = (
        await conn.execute(
            text("SELECT 1 FROM system_settings WHERE key = :key"),
            {"key": marker_key},
        )
    ).scalar_one_or_none()
    if marker is not None:
        return 0

    existing = (
        await conn.execute(text("SELECT count(*) FROM notification_messages"))
    ).scalar() or 0
    backfilled = 0
    if int(existing) == 0:
        from app.services.notification_inbox import build_task_run_notification

        rows = (
            await conn.execute(
                text(
                    """
                    SELECT run_id, task, status, started_at, finished_at,
                           error, metadata, result
                    FROM background_task_runs
                    ORDER BY started_at DESC
                    LIMIT 200
                    """
                )
            )
        ).mappings().all()
        for row in reversed(rows):
            metadata = _decode_json_object(row["metadata"])
            run = {
                **metadata,
                "run_id": row["run_id"],
                "task": row["task"],
                "status": row["status"],
                "started_at": row["started_at"],
                "finished_at": row["finished_at"],
                "error": row["error"],
                "result": _decode_json_object(row["result"]),
            }
            notification = build_task_run_notification(run)
            if notification is None:
                continue
            occurred_at = notification["occurred_at"]
            await conn.execute(
                text(
                    """
                    INSERT INTO notification_messages (
                        dedupe_key, category, severity, title, body, route,
                        source_type, source_id, payload, occurrence_count,
                        first_occurred_at, last_occurred_at, expires_at,
                        created_at, updated_at
                    ) VALUES (
                        :dedupe_key, :category, :severity, :title, :body, :route,
                        :source_type, :source_id, :payload, 1,
                        :occurred_at, :occurred_at, :expires_at,
                        :occurred_at, :occurred_at
                    )
                    ON CONFLICT(dedupe_key) DO UPDATE SET
                        severity = excluded.severity,
                        title = excluded.title,
                        body = excluded.body,
                        route = excluded.route,
                        source_id = excluded.source_id,
                        payload = excluded.payload,
                        occurrence_count = notification_messages.occurrence_count + 1,
                        last_occurred_at = excluded.last_occurred_at,
                        read_at = NULL,
                        expires_at = excluded.expires_at,
                        dismissed_at = NULL,
                        updated_at = excluded.updated_at
                    """
                ),
                {
                    **notification,
                    "payload": json.dumps(notification["payload"], ensure_ascii=False),
                    "occurred_at": occurred_at,
                },
            )
            backfilled += 1

    await conn.execute(
        text(
            """
            INSERT INTO system_settings (key, value, category, description, updated_at)
            VALUES (:key, 'true', 'migrations', :description, CURRENT_TIMESTAMP)
            ON CONFLICT(key) DO UPDATE SET
                value = excluded.value,
                category = excluded.category,
                description = excluded.description,
                updated_at = CURRENT_TIMESTAMP
            """
        ),
        {
            "key": marker_key,
            "description": "M31 notification inbox backfill completed",
        },
    )
    return backfilled


def _decode_json_object(value: Any) -> dict[str, Any]:
    if isinstance(value, dict):
        return value
    if isinstance(value, str):
        try:
            parsed = json.loads(value)
        except (TypeError, ValueError):
            return {}
        return parsed if isinstance(parsed, dict) else {}
    return {}


def _parse_legacy_run_datetime(value: Any) -> datetime | None:
    if isinstance(value, datetime):
        parsed = value
    elif isinstance(value, str) and value.strip():
        try:
            parsed = datetime.fromisoformat(value.strip().replace("Z", "+00:00"))
        except ValueError:
            return None
    else:
        return None
    if parsed.tzinfo is not None:
        parsed = parsed.astimezone(timezone.utc).replace(tzinfo=None)
    return parsed


async def ensure_content_fts(conn: AsyncConnection) -> None:
    """Ensure SQLite FTS schema exists and is synchronized from contents."""
    await conn.execute(
        text(
            """
            CREATE VIRTUAL TABLE IF NOT EXISTS contents_fts
            USING fts5(content_id UNINDEXED, title, body, summary)
            """
        )
    )
    await conn.execute(
        text(
            """
            CREATE TRIGGER IF NOT EXISTS contents_fts_ai
            AFTER INSERT ON contents
            BEGIN
                INSERT INTO contents_fts(rowid, content_id, title, body, summary)
                VALUES (
                    new.id,
                    new.id,
                    COALESCE(new.title, ''),
                    COALESCE(new.body, ''),
                    COALESCE(new.summary, '')
                );
            END
            """
        )
    )
    await conn.execute(
        text(
            """
            CREATE TRIGGER IF NOT EXISTS contents_fts_au
            AFTER UPDATE OF title, body, summary ON contents
            BEGIN
                DELETE FROM contents_fts WHERE rowid = old.id;
                INSERT INTO contents_fts(rowid, content_id, title, body, summary)
                VALUES (
                    new.id,
                    new.id,
                    COALESCE(new.title, ''),
                    COALESCE(new.body, ''),
                    COALESCE(new.summary, '')
                );
            END
            """
        )
    )
    await conn.execute(
        text(
            """
            CREATE TRIGGER IF NOT EXISTS contents_fts_ad
            AFTER DELETE ON contents
            BEGIN
                DELETE FROM contents_fts WHERE rowid = old.id;
            END
            """
        )
    )
    await conn.execute(
        text(
            """
            INSERT INTO contents_fts(rowid, content_id, title, body, summary)
            SELECT
                c.id,
                c.id,
                COALESCE(c.title, ''),
                COALESCE(c.body, ''),
                COALESCE(c.summary, '')
            FROM contents AS c
            WHERE NOT EXISTS (
                SELECT 1 FROM contents_fts AS f WHERE f.rowid = c.id
            )
            """
        )
    )


async def get_content_fts_health() -> dict[str, Any]:
    """Return FTS health without raising from the health endpoint."""
    async with AsyncSessionLocal() as session:
        try:
            table_exists = (
                await session.execute(
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
                return {"status": "missing", "available": False}

            indexed_rows = (await session.execute(text("SELECT count(*) FROM contents_fts"))).scalar() or 0
            content_rows = (await session.execute(text("SELECT count(*) FROM contents"))).scalar() or 0
            trigger_rows = (
                (
                    await session.execute(
                        text(
                            """
                            SELECT count(*)
                            FROM sqlite_master
                            WHERE type = 'trigger'
                              AND name IN ('contents_fts_ai', 'contents_fts_au', 'contents_fts_ad')
                            """
                        )
                    )
                ).scalar()
                or 0
            )
            return {
                "status": "ok" if trigger_rows == 3 else "degraded",
                "available": trigger_rows == 3,
                "indexed_rows": int(indexed_rows),
                "content_rows": int(content_rows),
                "triggers": int(trigger_rows),
            }
        except Exception as exc:
            return {"status": "error", "available": False, "error": str(exc)}


async def get_database_health() -> dict[str, Any]:
    """Return lightweight DB and search-index diagnostics."""
    ping_ok = await db_ping()
    details: dict[str, Any] = {"status": "ok" if ping_ok else "error", "ping": ping_ok}
    if ping_ok:
        details["fts"] = await get_content_fts_health()
        async with engine.connect() as conn:
            details["schema"] = await validate_database_schema(conn)
    else:
        details["fts"] = {"status": "unknown", "available": False}
        details["schema"] = {"status": "unknown"}
    return details


async def db_ping() -> bool:
    """数据库健康检查"""
    try:
        async with engine.connect() as conn:
            await conn.execute(text("SELECT 1"))
        return True
    except Exception:
        return False


async def get_db():
    """获取数据库会话"""
    async with AsyncSessionLocal() as session:
        yield session
