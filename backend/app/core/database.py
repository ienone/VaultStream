"""Create new databases from ORM metadata; upgrade existing ones with Alembic."""
from pathlib import Path
from typing import Any

from alembic import command
from alembic.config import Config
from sqlalchemy import inspect, text

from app.core.db_adapter import AsyncSessionLocal, engine
from app.models import Base


def migration_config() -> Config:
    return Config(str(Path(__file__).resolve().parents[2] / "alembic.ini"))


async def init_db() -> None:
    """Bootstrap an empty database or apply pending incremental revisions."""
    def initialize(connection):
        config = migration_config()
        config.attributes["connection"] = connection
        tables = inspect(connection).get_table_names()
        if not tables:
            _create_schema(connection)
            command.stamp(config, "head")
        elif "alembic_version" not in tables:
            raise RuntimeError("数据库未经 Alembic 管理，请清空旧测试库后重新初始化")
        else:
            command.upgrade(config, "head")

    async with engine.begin() as connection:
        await connection.run_sync(initialize)


def _create_schema(connection) -> None:
    Base.metadata.create_all(connection)
    connection.exec_driver_sql("""
        CREATE TABLE realtime_events (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            event_type VARCHAR(100) NOT NULL,
            payload TEXT NOT NULL,
            source_instance VARCHAR(64) NOT NULL,
            created_at DATETIME DEFAULT CURRENT_TIMESTAMP
        )
    """)
    connection.exec_driver_sql('CREATE INDEX ix_realtime_events_created_at ON realtime_events(created_at)')
    connection.exec_driver_sql('CREATE VIRTUAL TABLE contents_fts USING fts5(content_id UNINDEXED, title, body, summary)')
    connection.exec_driver_sql("""
        CREATE TRIGGER contents_fts_ai AFTER INSERT ON contents BEGIN
            INSERT INTO contents_fts(rowid, content_id, title, body, summary)
            VALUES (new.id, new.id, COALESCE(new.title, ''), COALESCE(new.body, ''), COALESCE(new.summary, ''));
        END
    """)
    connection.exec_driver_sql("""
        CREATE TRIGGER contents_fts_au AFTER UPDATE OF title, body, summary ON contents BEGIN
            DELETE FROM contents_fts WHERE rowid = old.id;
            INSERT INTO contents_fts(rowid, content_id, title, body, summary)
            VALUES (new.id, new.id, COALESCE(new.title, ''), COALESCE(new.body, ''), COALESCE(new.summary, ''));
        END
    """)
    connection.exec_driver_sql("""
        CREATE TRIGGER contents_fts_ad AFTER DELETE ON contents BEGIN
            DELETE FROM contents_fts WHERE rowid = old.id;
        END
    """)


async def get_database_health() -> dict[str, Any]:
    from app.core.schema_gate import validate_database_schema

    ping_ok = await db_ping()
    details: dict[str, Any] = {"status": "ok" if ping_ok else "error", "ping": ping_ok}
    if ping_ok:
        async with engine.connect() as conn:
            details["schema"] = await validate_database_schema(conn)
        details["fts"] = details["schema"]["fts"]
    else:
        details["fts"] = {"status": "unknown", "available": False}
        details["schema"] = {"status": "unknown"}
    return details


async def db_ping() -> bool:
    try:
        async with engine.connect() as conn:
            await conn.execute(text("SELECT 1"))
        return True
    except Exception:
        return False


async def get_db():
    async with AsyncSessionLocal() as session:
        yield session
