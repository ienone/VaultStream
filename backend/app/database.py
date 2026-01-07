"""
数据库连接管理
"""
from sqlalchemy import text
from app.models import Base

# 使用适配器模式支持多种数据库
from app.db_adapter import get_database_adapter

# 获取数据库适配器
_db_adapter = get_database_adapter()
engine = _db_adapter.get_engine()
AsyncSessionLocal = _db_adapter.get_session_maker()


async def init_db():
    """初始化数据库"""
    async with engine.begin() as conn:
        await conn.run_sync(Base.metadata.create_all)


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
        try:
            yield session
        finally:
            await session.close()
