"""
FastAPI 主应用
"""
import sys
import asyncio

# Fix for Windows: Playwright requires ProactorEventLoop
if sys.platform == 'win32':
    asyncio.set_event_loop_policy(asyncio.WindowsProactorEventLoopPolicy())

from contextlib import asynccontextmanager
from pathlib import Path
from time import perf_counter
from fastapi import FastAPI
from fastapi import Request
from fastapi.middleware.cors import CORSMiddleware
from fastapi.staticfiles import StaticFiles

from app.core.logging import logger, setup_logging, log_context, new_request_id

from app.core.config import settings, validate_settings
from app.core.database import init_db
from app.core.queue import task_queue
from app.core.events import event_bus
from app.worker import worker
from app.distribution import get_queue_worker

# Import new routers
from app.routers import (
    contents, distribution, system, media, bot_management, 
    events, distribution_queue, bot_config
)
from app.api.v1 import browser_auth
from app.core.browser_manager import browser_manager

setup_logging(level=settings.log_level, fmt=settings.log_format, debug=settings.debug)


async def _bootstrap_system_settings():
    """初始化系统设置，如生成 API Token"""
    from app.services.settings_service import get_setting_value, set_setting_value, load_all_settings_to_memory
    from pydantic import SecretStr
    import secrets

    # 1. 预先加载所有 DB 配置到内存（例如 Cookies 等环境级变量）
    await load_all_settings_to_memory()

    # 2. 检查 API Token
    token = await get_setting_value("api_token")
    env_token = settings.api_token.get_secret_value()

    if not token and not env_token:
        # 生成新 Token
        new_token = f"VS_{secrets.token_urlsafe(32)}"
        await set_setting_value("api_token", new_token, category="security", description="自动生成的 API 访问密钥")
        
        # 更新内存中的 settings 对象，确保后续鉴权通过
        settings.api_token = SecretStr(new_token)
        
        # 醒目打印
        print("\n" + "="*70)
        print("  " + "首次启动! 请复制以下 API 访问密钥以连接前端:".center(66))
        print("\n" + f"  {new_token}  ".center(70, " "))
        print("\n" + "  该密钥已安全存储在数据库中，您稍后可在设置页面修改。".center(66))
        print("="*70 + "\n")
    elif env_token:
        # 如果环境变量有，确保内存中使用环境变量的
        settings.api_token = SecretStr(env_token)
    elif token:
        # 如果数据库有，确保内存中同步数据库的
        settings.api_token = SecretStr(token)


@asynccontextmanager
async def lifespan(app: FastAPI):
    """应用生命周期管理"""
    # 启动时
    validate_settings()
    logger.info("启动 VaultStream 应用程序...")
    
    # 初始化数据库
    await init_db()
    logger.info("数据库初始化完成")

    # 自举 API Token
    await _bootstrap_system_settings()

    # 预热共享 WebKit 浏览器（认证服务 + Tier 3 解析器公用）
    await browser_manager.startup()
    
    # 连接任务队列
    await task_queue.connect()

    # 启动事件总线（跨实例事件桥接）
    await event_bus.start()
    
    # 启动后台worker
    from app.worker.task_processor import TaskWorker
    parse_workers = []
    for i in range(settings.parse_worker_count):
        w = TaskWorker()
        parse_workers.append(asyncio.create_task(w.start()))
    logger.info("后台任务工作器已启动 (worker_count={})", settings.parse_worker_count)
    
    # 启动分发队列 Worker
    queue_worker = get_queue_worker(worker_count=settings.queue_worker_count)
    queue_worker.start()
    logger.info("分发队列 Worker 已启动 (worker_count={})", settings.queue_worker_count)
    
    # 启动 Cookie 保活任务
    from app.worker.cookie_keepalive import start_cookie_keepalive_tasks
    start_cookie_keepalive_tasks()
    logger.info("Cookie 保活任务队列已启动")
    
    yield
    
    # 关闭时
    logger.info("关闭 VaultStream 应用程序...")

    # 停止共享浏览器
    await browser_manager.shutdown()

    
    # 停止分发队列 Worker
    await queue_worker.stop()
    logger.info("分发队列 Worker 已停止")
    
    # 停止worker
    for task in parse_workers:
        task.cancel()
    for task in parse_workers:
        try:
            await task
        except asyncio.CancelledError:
            pass
    logger.info("后台任务工作器已停止")
    
    # 断开任务队列
    await task_queue.disconnect()

    # 停止事件总线
    await event_bus.stop()
    
    logger.info("应用程序关闭完成")


# 创建应用
app = FastAPI(
    title="VaultStream API",
    description="跨平台收藏&分享软件",
    version="0.0.1",
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
            logger.exception("未处理的请求异常")
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

    from fastapi.responses import JSONResponse

    return JSONResponse(status_code=500, content={"detail": "internal error"}, headers={"X-Request-Id": request_id})

# CORS中间件
_cors_origins = [o.strip() for o in settings.cors_allowed_origins.split(",") if o.strip()]
app.add_middleware(
    CORSMiddleware,
    allow_origins=_cors_origins,
    allow_credentials=("*" not in _cors_origins),
    allow_methods=["*"],
    allow_headers=["*"],
)

# 注册路由
app.include_router(contents.router, prefix="/api/v1", tags=["contents"])
app.include_router(distribution.router, prefix="/api/v1", tags=["distribution"])
app.include_router(system.router, prefix="/api/v1", tags=["system"])
app.include_router(media.router, prefix="/api/v1", tags=["media"])
app.include_router(bot_management.router, prefix="/api/v1", tags=["bot"])
app.include_router(bot_config.router, prefix="/api/v1", tags=["bot-config"])
app.include_router(events.router, prefix="/api/v1", tags=["events"])
app.include_router(distribution_queue.router, prefix="/api/v1", tags=["distribution-queue"])
app.include_router(browser_auth.router, prefix="/api/v1/browser-auth", tags=["browser-auth"])


@app.get("/api/v1/init-status", tags=["System"])
async def init_status(request: Request):
    """
    检查系统初始化状态，主要用于前端判断是否跳转引导页或展示主界面
    """
    
    # Placeholder for actual initialization status logic
    pass


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
    """健康检查（根路径）— 代理到 /api/v1/health"""
    from app.routers.system import health_check
    return await health_check()


# 挂载媒体文件目录（供 frontend 访问归档的图片视频）
media_dir = Path(settings.storage_local_root)
if media_dir.exists():
    app.mount("/media", StaticFiles(directory=str(media_dir)), name="media")


if __name__ == "__main__":
    import uvicorn
    uvicorn.run(
        "app.main:app",
        host=settings.api_host,
        port=settings.api_port,
        reload=settings.debug
    )