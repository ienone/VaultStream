"""共享 Chromium，在独立事件循环中管理浏览器与隔离会话。"""

import asyncio
import sys
import threading
from typing import Optional, Any, Coroutine

from loguru import logger
from playwright.async_api import async_playwright, Browser, BrowserContext

_AUTH_VIEWPORT = {"width": 1280, "height": 800}
_FETCH_VIEWPORT = {"width": 1280, "height": 900}
_SHUTDOWN_JOIN_TIMEOUT_SECONDS = 5.0


class PlaywrightBrowserManager:
    def __init__(self):
        self._pw_loop: Optional[asyncio.AbstractEventLoop] = None
        self._pw_thread: Optional[threading.Thread] = None

        self._playwright = None
        self._browser: Optional[Browser] = None
        self._browser_lock: Optional[asyncio.Lock] = None

        self._started = False
        self._initializing = False  # 防止并发重入导致递归
        self._loop_ready = threading.Event()
        self._startup_lock: Optional[asyncio.Lock] = None

    def _get_startup_lock(self) -> asyncio.Lock:
        if self._startup_lock is None:
            self._startup_lock = asyncio.Lock()
        return self._startup_lock

    # ------------------------------------------------------------------
    # Lifespan 集成
    # ------------------------------------------------------------------

    async def startup(self):
        if self._started:
            return

        async with self._get_startup_lock():
            if self._started:
                return
            self._initializing = True

            try:
                self._loop_ready.clear()

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
                    name="PlaywrightLoopThread",
                )
                self._pw_thread.start()

                # 等待后台 loop 创建完毕
                self._loop_ready.wait()

                # 直接通过 run_coroutine_threadsafe 初始化浏览器，
                # 不经过 submit_coro，避免 submit_coro → startup → submit_coro 的递归死循环
                if self._pw_loop is None:
                    raise RuntimeError("Playwright 后台 Loop 创建失败")
                future = asyncio.run_coroutine_threadsafe(self._init_browser(), self._pw_loop)
                await asyncio.wrap_future(future)

                self._started = True
                logger.info("PlaywrightBrowserManager: 后台循环已启动")
            except Exception:
                raise
            finally:
                self._initializing = False

    async def _init_browser(self):
        self._playwright = await async_playwright().start()

    async def shutdown(self):
        if not self._started or self._pw_loop is None or self._pw_thread is None:
            return
            
        # 优雅关闭 browser
        await self.submit_coro(self._close_browser())
        
        # 停止 loop
        self._pw_loop.call_soon_threadsafe(self._pw_loop.stop)
        self._pw_thread.join(timeout=_SHUTDOWN_JOIN_TIMEOUT_SECONDS)
        if self._pw_thread.is_alive():
            logger.error(
                "PlaywrightBrowserManager: 后台循环线程在 {}s 内未退出",
                _SHUTDOWN_JOIN_TIMEOUT_SECONDS,
            )
        
        self._started = False
        self._pw_loop = None
        self._pw_thread = None
        self._playwright = None
        self._browser = None
        self._browser_lock = None
        self._loop_ready.clear()
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
        if not self._started:
            try:
                await self.startup()
            except Exception:
                coro.close()
                raise

        if not self._pw_loop:
            raise RuntimeError("Playwright 后台循环尚未启动")
        future = asyncio.run_coroutine_threadsafe(coro, self._pw_loop)
        return await asyncio.wrap_future(future)
        
    async def get_browser(self) -> Browser:
        """仅在 submit_coro 的事件循环中获取同一个 Chromium。"""
        if not self._started or not self._playwright:
            raise RuntimeError("浏览器尚未就绪")
        if self._browser_lock is None:
            self._browser_lock = asyncio.Lock()
        async with self._browser_lock:
            if not self._browser or not self._browser.is_connected():
                self._browser = await self._playwright.chromium.launch(
                    headless=True,
                    args=["--disable-blink-features=AutomationControlled"],
                )
            return self._browser

    async def new_context(self, *, proxy: str | None, viewport: dict | None = None) -> BrowserContext:
        """每次操作使用独立 Cookie、存储与代理；调用方负责关闭会话。"""
        browser = await self.get_browser()
        version = browser.version.split(".")[0]
        return await browser.new_context(
            viewport=viewport or self.fetch_viewport,
            user_agent=self.ua,
            extra_http_headers={"sec-ch-ua": (
                f'"Chromium";v="{version}", "Not_A Brand";v="8", "Google Chrome";v="{version}"'
            )},
            service_workers="block",
            **({"proxy": {"server": proxy}} if proxy else {}),
        )

    # 公开配置
    @property
    def auth_viewport(self):
        return _AUTH_VIEWPORT

    @property
    def fetch_viewport(self):
        return dict(_FETCH_VIEWPORT)

    @property
    def ua(self):
        version = self._browser.version.split(".")[0] if self._browser else "145"
        return ("Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 "
                f"(KHTML, like Gecko) Chrome/{version}.0.0.0 Safari/537.36")


browser_manager = PlaywrightBrowserManager()
