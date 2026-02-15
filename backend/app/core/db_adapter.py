"""
数据库适配器 - SQLite (aiosqlite)
"""
import os
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
    
    logger.info(f"SQLite 引擎已创建: {db_path}")
    return _engine


engine = _create_engine()
AsyncSessionLocal = async_sessionmaker(engine, class_=AsyncSession, expire_on_commit=False)
