"""
数据库连接管理
"""
import json
from datetime import datetime
from sqlalchemy import text
from sqlalchemy.exc import SQLAlchemyError
from app.models import Base
from app.core.db_adapter import engine, AsyncSessionLocal
from app.core.logging import logger


async def init_db():
    """初始化数据库"""
    async with engine.begin() as conn:
        await conn.run_sync(Base.metadata.create_all)
        await _migrate_content_embeddings_table(conn)
        await _ensure_content_queue_claim_indexes(conn)

    # 一次性数据更新：ReviewStatus 大写 → 小写
    await _migrate_review_status_lowercase()
    await _migrate_distribution_target_backfill_watermark()
    await _migrate_phase1_distribution_cleanup()


async def _migrate_review_status_lowercase():
    """将 review_status 列中的大写枚举值转换为小写（幂等）"""
    mapping = {
        "PENDING": "pending",
        "APPROVED": "approved",
        "REJECTED": "rejected",
        "AUTO_APPROVED": "auto_approved",
    }
    async with engine.begin() as conn:
        for old_val, new_val in mapping.items():
            await conn.execute(
                text("UPDATE contents SET review_status = :new WHERE review_status = :old"),
                {"old": old_val, "new": new_val},
            )


async def _migrate_distribution_target_backfill_watermark():
    """为旧库补齐 distribution_targets.backfill_watermark 字段（幂等）"""
    async with engine.begin() as conn:
        table_exists = await conn.execute(
            text(
                "SELECT name FROM sqlite_master "
                "WHERE type='table' AND name='distribution_targets'"
            )
        )
        if table_exists.scalar_one_or_none() is None:
            return

        columns = await conn.execute(text("PRAGMA table_info(distribution_targets)"))
        has_watermark = any(row[1] == "backfill_watermark" for row in columns.fetchall())

        if not has_watermark:
            await conn.execute(
                text(
                    "ALTER TABLE distribution_targets "
                    "ADD COLUMN backfill_watermark DATETIME"
                )
            )

        await conn.execute(
            text(
                "UPDATE distribution_targets "
                "SET backfill_watermark = COALESCE(backfill_watermark, created_at, CURRENT_TIMESTAMP)"
            )
        )


async def _table_exists(conn, table_name: str) -> bool:
    result = await conn.execute(
        text(
            "SELECT name FROM sqlite_master "
            "WHERE type='table' AND name=:table_name"
        ),
        {"table_name": table_name},
    )
    return result.scalar_one_or_none() is not None


async def _table_columns(conn, table_name: str) -> set[str]:
    result = await conn.execute(text(f"PRAGMA table_info({table_name})"))
    return {str(row[1]) for row in result.fetchall() if len(row) > 1 and row[1]}


async def _migrate_content_embeddings_table(conn) -> None:
    """
    创建并补齐 content_embeddings 表（幂等）。

    说明：
    - 新库由 metadata.create_all 创建；
    - 旧库走此函数补齐列与索引，避免依赖手工迁移脚本。
    """
    await conn.execute(
        text(
            """
            CREATE TABLE IF NOT EXISTS content_embeddings (
                id INTEGER PRIMARY KEY NOT NULL,
                content_id INTEGER NOT NULL,
                embedding_model VARCHAR(100) NOT NULL DEFAULT 'text-embedding-3-small',
                embedding JSON,
                text_hash VARCHAR(64),
                source_text TEXT,
                indexed_at DATETIME,
                created_at DATETIME,
                updated_at DATETIME,
                FOREIGN KEY(content_id) REFERENCES contents (id) ON DELETE CASCADE
            )
            """
        )
    )

    columns = await _table_columns(conn, "content_embeddings")
    if "source_text" not in columns:
        await conn.execute(text("ALTER TABLE content_embeddings ADD COLUMN source_text TEXT"))
    if "text_hash" not in columns:
        await conn.execute(text("ALTER TABLE content_embeddings ADD COLUMN text_hash VARCHAR(64)"))
    if "embedding_model" not in columns:
        await conn.execute(
            text(
                "ALTER TABLE content_embeddings ADD COLUMN embedding_model VARCHAR(100) "
                "DEFAULT 'text-embedding-3-small'"
            )
        )

    await conn.execute(
        text(
            "CREATE UNIQUE INDEX IF NOT EXISTS uq_content_embeddings_content_id "
            "ON content_embeddings(content_id)"
        )
    )
    await conn.execute(
        text(
            "CREATE INDEX IF NOT EXISTS ix_content_embeddings_indexed_at "
            "ON content_embeddings(indexed_at)"
        )
    )
    await conn.execute(
        text(
            "CREATE INDEX IF NOT EXISTS ix_content_embeddings_model "
            "ON content_embeddings(embedding_model)"
        )
    )
    await conn.execute(
        text(
            "CREATE INDEX IF NOT EXISTS ix_content_embeddings_text_hash "
            "ON content_embeddings(text_hash)"
        )
    )


async def _ensure_content_queue_claim_indexes(conn) -> None:
    """为队列领取热点查询补齐索引（幂等）。"""
    if not await _table_exists(conn, "content_queue_items"):
        return

    index_sql = [
        "CREATE INDEX IF NOT EXISTS ix_queue_claim_scheduled_priority "
        "ON content_queue_items(status, priority DESC, scheduled_at, id)",
        "CREATE INDEX IF NOT EXISTS ix_queue_claim_failed_retry "
        "ON content_queue_items(status, next_attempt_at, priority DESC, scheduled_at, id)",
        "CREATE INDEX IF NOT EXISTS ix_queue_claim_status_lock "
        "ON content_queue_items(status, locked_at)",
    ]
    for sql in index_sql:
        await conn.execute(text(sql))


async def _backup_auto_approve_conditions(conn) -> int:
    if not await _table_exists(conn, "distribution_rules"):
        return 0

    columns = await _table_columns(conn, "distribution_rules")
    if "auto_approve_conditions" not in columns:
        return 0

    rows = (
        await conn.execute(
            text(
                "SELECT id, name, approval_required, auto_approve_conditions "
                "FROM distribution_rules "
                "WHERE auto_approve_conditions IS NOT NULL "
                "AND trim(CAST(auto_approve_conditions AS TEXT)) NOT IN ('', 'null', '{}', '[]')"
            )
        )
    ).mappings().all()
    if not rows:
        return 0

    payload = {
        "migrated_at": datetime.utcnow().isoformat() + "Z",
        "row_count": len(rows),
        "rows": [dict(row) for row in rows],
    }
    await conn.execute(
        text(
            "INSERT INTO system_settings(key, value, category, description, updated_at) "
            "VALUES(:key, :value, :category, :description, CURRENT_TIMESTAMP) "
            "ON CONFLICT(key) DO UPDATE SET "
            "value=excluded.value, category=excluded.category, "
            "description=excluded.description, updated_at=CURRENT_TIMESTAMP"
        ),
        {
            "key": "migration.phase1.auto_approve_conditions_backup",
            "value": json.dumps(payload, ensure_ascii=False),
            "category": "migration",
            "description": "Phase 1 cleanup backup for distribution_rules.auto_approve_conditions",
        },
    )
    return len(rows)


async def _migrate_queue_status_cleanup(conn) -> int:
    if not await _table_exists(conn, "content_queue_items"):
        return 0

    changed = 0

    # 先处理历史大写值
    normalize_mapping = {
        "SCHEDULED": "scheduled",
        "PROCESSING": "processing",
        "SUCCESS": "success",
        "FAILED": "failed",
        "PENDING": "pending",
        "SKIPPED": "skipped",
        "CANCELED": "canceled",
    }
    for old_val, new_val in normalize_mapping.items():
        result = await conn.execute(
            text(
                "UPDATE content_queue_items "
                "SET status = :new_val "
                "WHERE status = :old_val"
            ),
            {"old_val": old_val, "new_val": new_val},
        )
        changed += int(result.rowcount or 0)

    # Phase 1: pending/skipped/canceled 统一收敛到 failed 终态
    migration_rules = {
        "pending": ("legacy_pending_removed", "Legacy pending queue item migrated to filtered"),
        "skipped": ("legacy_skipped_removed", "Legacy skipped queue item migrated to filtered"),
        "canceled": ("manual_canceled", "Legacy canceled queue item migrated to filtered"),
    }
    for old_status, (error_type, message) in migration_rules.items():
        result = await conn.execute(
            text(
                "UPDATE content_queue_items "
                "SET status = 'failed', "
                "next_attempt_at = NULL, "
                "last_error_type = COALESCE(last_error_type, :error_type), "
                "last_error = COALESCE(last_error, :message), "
                "last_error_at = COALESCE(last_error_at, CURRENT_TIMESTAMP) "
                "WHERE status = :old_status"
            ),
            {
                "old_status": old_status,
                "error_type": error_type,
                "message": message,
            },
        )
        changed += int(result.rowcount or 0)

    return changed


async def _drop_queue_legacy_approval_columns(conn) -> bool:
    if not await _table_exists(conn, "content_queue_items"):
        return False

    columns = await _table_columns(conn, "content_queue_items")
    legacy_columns = [col for col in ("needs_approval", "approved_at") if col in columns]
    if not legacy_columns:
        return False

    try:
        for col in legacy_columns:
            await conn.execute(text(f"ALTER TABLE content_queue_items DROP COLUMN {col}"))
    except SQLAlchemyError:
        await _rebuild_content_queue_items_without_legacy_columns(conn)
    return True


async def _drop_rule_auto_approve_column(conn) -> bool:
    if not await _table_exists(conn, "distribution_rules"):
        return False

    columns = await _table_columns(conn, "distribution_rules")
    if "auto_approve_conditions" not in columns:
        return False

    try:
        await conn.execute(text("ALTER TABLE distribution_rules DROP COLUMN auto_approve_conditions"))
    except SQLAlchemyError as exc:
        # 低版本 SQLite 可能不支持 DROP COLUMN，保留列并记录告警，不影响启动。
        logger.warning("Failed to drop distribution_rules.auto_approve_conditions: {}", exc)
        return False
    return True


async def _rebuild_content_queue_items_without_legacy_columns(conn) -> None:
    """
    兼容不支持 DROP COLUMN 的 SQLite 版本：
    重建 content_queue_items 表并移除 needs_approval / approved_at。
    """
    old_table = "content_queue_items__legacy_phase1"
    await conn.execute(text(f"ALTER TABLE content_queue_items RENAME TO {old_table}"))

    await conn.execute(
        text(
            """
            CREATE TABLE content_queue_items (
                id INTEGER NOT NULL PRIMARY KEY,
                content_id INTEGER NOT NULL,
                rule_id INTEGER NOT NULL,
                bot_chat_id INTEGER NOT NULL,
                target_platform VARCHAR(20) NOT NULL,
                target_id VARCHAR(200) NOT NULL,
                status VARCHAR(20) NOT NULL,
                priority INTEGER,
                scheduled_at DATETIME,
                rendered_payload JSON,
                nsfw_routing_result JSON,
                passed_rate_limit BOOLEAN,
                rate_limit_reason VARCHAR(200),
                approved_by VARCHAR(100),
                attempt_count INTEGER,
                max_attempts INTEGER,
                next_attempt_at DATETIME,
                locked_at DATETIME,
                locked_by VARCHAR(100),
                message_id VARCHAR(200),
                last_error TEXT,
                last_error_type VARCHAR(200),
                last_error_at DATETIME,
                started_at DATETIME,
                completed_at DATETIME,
                created_at DATETIME,
                updated_at DATETIME,
                FOREIGN KEY(content_id) REFERENCES contents (id) ON DELETE CASCADE,
                FOREIGN KEY(rule_id) REFERENCES distribution_rules (id) ON DELETE CASCADE,
                FOREIGN KEY(bot_chat_id) REFERENCES bot_chats (id) ON DELETE CASCADE
            )
            """
        )
    )

    await conn.execute(
        text(
            f"""
            INSERT INTO content_queue_items (
                id, content_id, rule_id, bot_chat_id, target_platform, target_id,
                status, priority, scheduled_at, rendered_payload, nsfw_routing_result,
                passed_rate_limit, rate_limit_reason, approved_by, attempt_count, max_attempts,
                next_attempt_at, locked_at, locked_by, message_id, last_error, last_error_type,
                last_error_at, started_at, completed_at, created_at, updated_at
            )
            SELECT
                id, content_id, rule_id, bot_chat_id, target_platform, target_id,
                status, priority, scheduled_at, rendered_payload, nsfw_routing_result,
                passed_rate_limit, rate_limit_reason, approved_by, attempt_count, max_attempts,
                next_attempt_at, locked_at, locked_by, message_id, last_error, last_error_type,
                last_error_at, started_at, completed_at, created_at, updated_at
            FROM {old_table}
            """
        )
    )

    await conn.execute(text(f"DROP TABLE {old_table}"))

    index_sql = [
        "CREATE UNIQUE INDEX IF NOT EXISTS uq_queue_content_rule_chat ON content_queue_items(content_id, rule_id, bot_chat_id)",
        "CREATE INDEX IF NOT EXISTS ix_queue_status_scheduled ON content_queue_items(status, scheduled_at)",
        "CREATE INDEX IF NOT EXISTS ix_queue_content_status ON content_queue_items(content_id, status)",
        "CREATE INDEX IF NOT EXISTS ix_queue_rule_status ON content_queue_items(rule_id, status)",
        "CREATE INDEX IF NOT EXISTS ix_queue_chat_status ON content_queue_items(bot_chat_id, status)",
        "CREATE INDEX IF NOT EXISTS ix_queue_next_attempt ON content_queue_items(status, next_attempt_at)",
        "CREATE INDEX IF NOT EXISTS ix_queue_claim_scheduled_priority ON content_queue_items(status, priority DESC, scheduled_at, id)",
        "CREATE INDEX IF NOT EXISTS ix_queue_claim_failed_retry ON content_queue_items(status, next_attempt_at, priority DESC, scheduled_at, id)",
        "CREATE INDEX IF NOT EXISTS ix_queue_claim_status_lock ON content_queue_items(status, locked_at)",
        "CREATE INDEX IF NOT EXISTS ix_content_queue_items_content_id ON content_queue_items(content_id)",
        "CREATE INDEX IF NOT EXISTS ix_content_queue_items_rule_id ON content_queue_items(rule_id)",
        "CREATE INDEX IF NOT EXISTS ix_content_queue_items_bot_chat_id ON content_queue_items(bot_chat_id)",
        "CREATE INDEX IF NOT EXISTS ix_content_queue_items_status ON content_queue_items(status)",
        "CREATE INDEX IF NOT EXISTS ix_content_queue_items_priority ON content_queue_items(priority)",
        "CREATE INDEX IF NOT EXISTS ix_content_queue_items_scheduled_at ON content_queue_items(scheduled_at)",
    ]
    for sql in index_sql:
        await conn.execute(text(sql))


async def _migrate_phase1_distribution_cleanup() -> None:
    """
    Phase 1 尾项迁移（幂等）：
    1) 收敛旧队列状态枚举到新语义；
    2) 删除 content_queue_items.needs_approval / approved_at；
    3) 备份并删除 distribution_rules.auto_approve_conditions。
    """
    async with engine.begin() as conn:
        queue_changed = await _migrate_queue_status_cleanup(conn)
        queue_columns_dropped = await _drop_queue_legacy_approval_columns(conn)

        backup_count = await _backup_auto_approve_conditions(conn)
        rule_column_dropped = await _drop_rule_auto_approve_column(conn)

    logger.info(
        "Phase 1 DB cleanup completed: queue_status_changed={}, queue_columns_dropped={}, "
        "auto_approve_backup_rows={}, auto_approve_column_dropped={}",
        queue_changed,
        queue_columns_dropped,
        backup_count,
        rule_column_dropped,
    )


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
