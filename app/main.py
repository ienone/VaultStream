"""
FastAPI 主应用
"""
import asyncio
from contextlib import asynccontextmanager
from pathlib import Path
from time import perf_counter
from fastapi import FastAPI
from fastapi import Request
from fastapi.middleware.cors import CORSMiddleware
from fastapi.staticfiles import StaticFiles

from app.logging import logger, setup_logging, log_context, new_request_id

from app.config import settings, validate_settings
from app.database import init_db, db_ping
from app.queue import task_queue
from app.worker import worker
from app.api import router


setup_logging(level=settings.log_level, fmt=settings.log_format, debug=settings.debug)


@asynccontextmanager
async def lifespan(app: FastAPI):
    """应用生命周期管理"""
    # 启动时
    validate_settings()
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


@app.middleware("http")
async def request_id_middleware(request: Request, call_next):
    request_id = request.headers.get("X-Request-Id") or new_request_id()
    request.state.request_id = request_id

    start = perf_counter()
    response = None
    with log_context(request_id=request_id):
        try:
            response = await call_next(request)
        except Exception:
            logger.exception("Unhandled request exception")
            raise
        finally:
            elapsed_ms = (perf_counter() - start) * 1000
            logger.info(
                "request_complete path={} method={} status={} elapsed_ms={:.2f}",
                request.url.path,
                request.method,
                getattr(response, "status_code", 500),
                elapsed_ms,
            )

    if response is not None:
        response.headers["X-Request-Id"] = request_id
        return response

    # 理论上不会走到这里，仅兜底
    from fastapi.responses import JSONResponse

    return JSONResponse(status_code=500, content={"detail": "internal error"}, headers={"X-Request-Id": request_id})

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


@app.get("/api")
async def api_root():
    """API根路径"""
    return {
        "name": "VaultStream",
        "version": "0.1.0",
        "description": "超级收藏夹 - MVP版本"
    }


@app.get("/health")
async def health_root():
    """健康检查（根路径）。

    M0 约束：只返回可公开的运行状态，不暴露任何敏感配置。
    """
    redis_ok = await task_queue.ping()
    db_ok = await db_ping()
    status = "ok" if (redis_ok and db_ok) else "degraded"
    return {
        "status": status,
        "db": "ok" if db_ok else "error",
        "redis": "ok" if redis_ok else "error",
    }


# 挂载静态文件（必须放在最后，避免覆盖 /health 等路由）
static_dir = Path(__file__).parent.parent / "static"
if static_dir.exists():
    app.mount("/", StaticFiles(directory=str(static_dir), html=True), name="static")


if __name__ == "__main__":
    import uvicorn
    uvicorn.run(
        "app.main:app",
        host=settings.api_host,
        port=settings.api_port,
        reload=settings.debug
    )
