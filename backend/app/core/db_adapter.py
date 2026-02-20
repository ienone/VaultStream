"""
数据库适配器 - SQLite (aiosqlite)
"""
import os
import time
from sqlalchemy import event
from sqlalchemy.ext.asyncio import create_async_engine, AsyncSession, async_sessionmaker
from sqlalchemy.pool import NullPool
from app.core.config import settings
from app.core.logging import logger


def _create_engine():
    """创建 SQLite 异步引擎"""
    db_path = settings.sqlite_db_path
    os.makedirs(os.path.dirname(os.path.abspath(db_path)), exist_ok=True)
    
    url = f"sqlite+aiosqlite:///{db_path}"
    _engine = create_async_engine(
        url,
        echo=settings.debug_sql,
        future=True,
        poolclass=NullPool,
    )
    
    @event.listens_for(_engine.sync_engine, "connect")
    def set_sqlite_pragma(dbapi_conn, connection_record):
        cursor = dbapi_conn.cursor()
        cursor.execute("PRAGMA journal_mode=WAL")
        cursor.execute("PRAGMA synchronous=NORMAL")
        cursor.execute("PRAGMA cache_size=-64000")
        cursor.execute("PRAGMA temp_store=MEMORY")
        cursor.execute("PRAGMA mmap_size=268435456")
        cursor.execute("PRAGMA foreign_keys=ON")
        cursor.close()

    # 慢查询日志
    if settings.slow_query_threshold_ms > 0:
        @event.listens_for(_engine.sync_engine, "before_cursor_execute")
        def _before_cursor_execute(conn, cursor, statement, parameters, context, executemany):
            conn.info.setdefault("query_start_time", []).append(time.monotonic())

        @event.listens_for(_engine.sync_engine, "after_cursor_execute")
        def _after_cursor_execute(conn, cursor, statement, parameters, context, executemany):
            start_times = conn.info.get("query_start_time")
            if not start_times:
                return
            elapsed_ms = (time.monotonic() - start_times.pop()) * 1000
            if elapsed_ms >= settings.slow_query_threshold_ms:
                logger.warning(
                    "Slow query detected: elapsed_ms={}, statement={}, parameters={}",
                    round(elapsed_ms, 2),
                    statement[:500],
                    str(parameters)[:200] if parameters else None,
                )

    logger.info(f"SQLite 引擎已创建: {db_path}")
    return _engine


engine = _create_engine()
AsyncSessionLocal = async_sessionmaker(engine, class_=AsyncSession, expire_on_commit=False)
