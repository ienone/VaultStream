"""
数据库适配器层 - 支持 SQLite 和 PostgreSQL 切换
"""
from abc import ABC, abstractmethod
from typing import Any
import os
from sqlalchemy import event, create_engine
from sqlalchemy.ext.asyncio import create_async_engine, AsyncSession, async_sessionmaker
from sqlalchemy.pool import StaticPool, NullPool
from app.core.config import settings
from app.core.logging import logger


class DatabaseAdapter(ABC):
    """数据库适配器基类"""
    
    @abstractmethod
    def get_engine(self):
        """获取数据库引擎"""
        pass
    
    @abstractmethod
    def get_session_maker(self):
        """获取会话工厂"""
        pass


class SQLiteAdapter(DatabaseAdapter):
    """SQLite 适配器（轻量模式）"""
    
    def __init__(self, db_path: str):
        self.db_path = db_path
        # 确保数据目录存在
        os.makedirs(os.path.dirname(os.path.abspath(db_path)), exist_ok=True)
        
        # SQLite URL (使用 aiosqlite 支持异步)
        self.url = f"sqlite+aiosqlite:///{db_path}"
        self._engine = None
        self._session_maker = None
    
    def get_engine(self):
        """获取 SQLite 引擎"""
        if self._engine is None:
            self._engine = create_async_engine(
                self.url,
                echo=settings.debug_sql,
                future=True,
                # SQLite 在异步模式下使用 NullPool 避免连接池问题
                poolclass=NullPool,
            )
            
            # 配置 SQLite 优化参数
            @event.listens_for(self._engine.sync_engine, "connect")
            def set_sqlite_pragma(dbapi_conn, connection_record):
                cursor = dbapi_conn.cursor()
                # WAL 模式：允许并发读
                cursor.execute("PRAGMA journal_mode=WAL")
                # 平衡性能与安全
                cursor.execute("PRAGMA synchronous=NORMAL")
                # 64MB 缓存
                cursor.execute("PRAGMA cache_size=-64000")
                # 临时表放内存
                cursor.execute("PRAGMA temp_store=MEMORY")
                # 256MB mmap
                cursor.execute("PRAGMA mmap_size=268435456")
                # 外键约束
                cursor.execute("PRAGMA foreign_keys=ON")
                cursor.close()
            
            logger.info(f"SQLite 引擎已创建: {self.db_path}")
        
        return self._engine
    
    def get_session_maker(self):
        """获取 SQLite 会话工厂"""
        if self._session_maker is None:
            engine = self.get_engine()
            self._session_maker = async_sessionmaker(
                engine,
                class_=AsyncSession,
                expire_on_commit=False
            )
        return self._session_maker


def get_database_adapter() -> DatabaseAdapter:
    """根据配置获取数据库适配器"""
    db_type = settings.database_type
    
    if db_type == "sqlite":
        return SQLiteAdapter(settings.sqlite_db_path)
    else:
        raise ValueError(
            f"不支持的数据库类型: {db_type}。"
            f"当前仅支持 'sqlite'。如需 PostgreSQL 支持，请参考文档重新实现 PostgreSQLAdapter。"
        )


# 全局适配器实例
_adapter = get_database_adapter()

# 导出引擎和会话工厂（保持向后兼容）
engine = _adapter.get_engine()
AsyncSessionLocal = _adapter.get_session_maker()
