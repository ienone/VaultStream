"""
数据库连接管理
"""
from typing import Any

from sqlalchemy import text
from sqlalchemy.ext.asyncio import AsyncConnection

from app.core.db_adapter import AsyncSessionLocal, engine
from app.models import Base


async def init_db():
    """初始化数据库基础结构。"""
    async with engine.begin() as conn:
        await conn.run_sync(Base.metadata.create_all)
        await ensure_content_fts(conn)


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
    else:
        details["fts"] = {"status": "unknown", "available": False}
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
