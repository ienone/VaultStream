"""
数据库连接管理
"""
from sqlalchemy import text
from sqlalchemy.ext.asyncio import create_async_engine, AsyncSession, async_sessionmaker
from app.config import settings
from app.models import Base

# 创建异步引擎
# echo=False 避免输出大量 SQL 日志，仅在真正需要 SQL 调试时手动开启
engine = create_async_engine(
    settings.database_url,
    echo=settings.debug_sql,  # 使用独立的 debug_sql 配置
    future=True
)

# 创建异步会话工厂
AsyncSessionLocal = async_sessionmaker(
    engine,
    class_=AsyncSession,
    expire_on_commit=False
)


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
