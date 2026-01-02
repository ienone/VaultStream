"""
FastAPI 主应用
"""
import asyncio
from contextlib import asynccontextmanager
from pathlib import Path
from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from fastapi.staticfiles import StaticFiles
from loguru import logger

from app.config import settings
from app.database import init_db
from app.queue import task_queue
from app.worker import worker
from app.api import router


@asynccontextmanager
async def lifespan(app: FastAPI):
    """应用生命周期管理"""
    # 启动时
    logger.info("Starting VaultStream application...")
    
    # 初始化数据库
    await init_db()
    logger.info("Database initialized")
    
    # 连接Redis
    await task_queue.connect()
    
    # 启动后台worker
    worker_task = asyncio.create_task(worker.start())
    logger.info("Background worker started")
    
    yield
    
    # 关闭时
    logger.info("Shutting down VaultStream application...")
    
    # 停止worker
    await worker.stop()
    worker_task.cancel()
    try:
        await worker_task
    except asyncio.CancelledError:
        pass
    
    # 断开Redis
    await task_queue.disconnect()
    
    logger.info("Application shutdown complete")


# 创建应用
app = FastAPI(
    title="VaultStream API",
    description="超级收藏夹 - MVP版本",
    version="0.1.0",
    lifespan=lifespan
)

# CORS中间件
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],  # 生产环境需要限制
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# 注册路由
app.include_router(router, prefix="/api/v1", tags=["api"])

# 挂载静态文件
static_dir = Path(__file__).parent.parent / "static"
if static_dir.exists():
    app.mount("/", StaticFiles(directory=str(static_dir), html=True), name="static")


@app.get("/api")
async def api_root():
    """API根路径"""
    return {
        "name": "VaultStream",
        "version": "0.1.0",
        "description": "超级收藏夹 - MVP版本"
    }


if __name__ == "__main__":
    import uvicorn
    uvicorn.run(
        "app.main:app",
        host=settings.api_host,
        port=settings.api_port,
        reload=settings.debug
    )
