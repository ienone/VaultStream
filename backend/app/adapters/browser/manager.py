"""
全局 WebKit 浏览器单例管理器（特设独立异步循环）

解决 Windows FastAPI 并发缺陷的终极方案：
  - Windows Uvicorn 默认在主线程使用 SelectorEventLoop，导致 async_playwright 闪退。
  - 改用 sync_playwright 跨线程又会导致 greenlet thread mismatch 并发崩溃。
方案：
  在后台线程启动一个独立的 `asyncio.ProactorEventLoop` 永久循环。
  所有 async Playwright 操作通过 `submit_coro` 安全扔进去执行并跨线程返回 future。
  业务层代码保持 100% async / await 风格，无缝协作。
"""

import asyncio
import sys
import threading
from typing import Optional, Any, Coroutine

from loguru import logger
from playwright.async_api import async_playwright, Browser

_WEBKIT_UA = (
    "Mozilla/5.0 (Macintosh; Intel Mac OS X 14_5) "
    "AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.5 Safari/605.1.15"
)
_AUTH_VIEWPORT = {"width": 1280, "height": 800}
_FETCH_VIEWPORT = {"width": 1280, "height": 900}


class PlaywrightBrowserManager:
    def __init__(self):
        self._pw_loop: Optional[asyncio.AbstractEventLoop] = None
        self._pw_thread: Optional[threading.Thread] = None
        
        self._playwright = None
        self._browser: Optional[Browser] = None
        
        self._started = False
        self._loop_ready = threading.Event()

    # ------------------------------------------------------------------
    # Lifespan 集成
    # ------------------------------------------------------------------

    async def startup(self):
        if self._started:
            return
            
        def _run_background_loop():
            # 必须在线程起始时设置 policy 为 Proactor，确保支持 Windows subprocess
            if sys.platform == "win32":
                asyncio.set_event_loop_policy(asyncio.WindowsProactorEventLoopPolicy())
                
            self._pw_loop = asyncio.new_event_loop()
            asyncio.set_event_loop(self._pw_loop)
            
            # 通知主线程 loop 初始化完毕
            self._loop_ready.set()
            
            # 开启永久循环
            self._pw_loop.run_forever()
            
            # 清理
            self._pw_loop.close()

        self._pw_thread = threading.Thread(
            target=_run_background_loop, 
            daemon=True, 
            name="PlaywrightLoopThread"
        )
        self._pw_thread.start()
        
        # 等待后台 loop 创建完毕
        self._loop_ready.wait()
        
        # 在该 loop 中初始化 browser
        await self.submit_coro(self._init_browser())
        
        self._started = True
        logger.info("PlaywrightBrowserManager: WebKit 后台循环预热完成")

    async def _init_browser(self):
        self._playwright = await async_playwright().start()
        self._browser = await self._playwright.webkit.launch(
            headless=True,
            args=["--no-sandbox"],
        )

    async def shutdown(self):
        if not self._started:
            return
            
        # 优雅关闭 browser
        await self.submit_coro(self._close_browser())
        
        # 停止 loop
        self._pw_loop.call_soon_threadsafe(self._pw_loop.stop)
        self._pw_thread.join()
        
        self._started = False
        logger.info("PlaywrightBrowserManager: 浏览器与后台循环已关闭")

    async def _close_browser(self):
        if self._browser:
            try:
                await self._browser.close()
            except Exception:
                pass
        if self._playwright:
            try:
                await self._playwright.stop()
            except Exception:
                pass

    # ------------------------------------------------------------------
    # 核心：将任务派发给专用 Loop 执行
    # ------------------------------------------------------------------

    async def submit_coro(self, coro: Coroutine) -> Any:
        """将协程抛入后台专有 loop，并跨事件循环无缝等待其结果返回。"""
        if not self._pw_loop:
            raise RuntimeError("Playwright 后台循环尚未启动")
        future = asyncio.run_coroutine_threadsafe(coro, self._pw_loop)
        return await asyncio.wrap_future(future)
        
    def get_browser(self) -> Browser:
        """获取真实的 Browser 实例。注意它仅能在 Submit 的协程中使用。"""
        if not self._started or not self._browser:
            raise RuntimeError("浏览器尚未就绪")
        return self._browser

    # 公开配置
    @property
    def auth_viewport(self):
        return _AUTH_VIEWPORT

    @property
    def fetch_viewport(self):
        return dict(_FETCH_VIEWPORT)

    @property
    def ua(self):
        return _WEBKIT_UA


browser_manager = PlaywrightBrowserManager()
