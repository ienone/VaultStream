"""
数据库连接管理
"""
from sqlalchemy import text
from app.models import Base
from app.core.db_adapter import engine, AsyncSessionLocal


async def init_db():
    """初始化数据库"""
    async with engine.begin() as conn:
        await conn.run_sync(Base.metadata.create_all)

    # 一次性数据更新：ReviewStatus 大写 → 小写
    await _migrate_review_status_lowercase()
    await _migrate_distribution_target_backfill_watermark()


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
