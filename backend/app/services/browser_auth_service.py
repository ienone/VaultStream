"""
浏览器认证服务 - Async 派发版本

利用共享的 browser_manager 单例（提供专用后台 Loop），
将异步的登录流程打包为 coroutine，通过 submit_coro 安全执行。
"""

import asyncio
import base64
import uuid
from typing import Dict, Optional

from loguru import logger
from pydantic import BaseModel

from app.services.settings_service import set_setting_value, get_setting_value, delete_setting_value
from app.core.browser_manager import browser_manager


class AuthSessionStatus(BaseModel):
    session_id: str
    platform: str
    status: str  # initializing, waiting_scan, success, timeout, failed
    message: Optional[str] = None
    qrcode_b64: Optional[str] = None


class AuthSession:
    def __init__(self, platform: str):
        self.session_id = str(uuid.uuid4())
        self.platform = platform
        self.status = "initializing"
        self.qrcode_b64: Optional[str] = None
        self.message: Optional[str] = None
        self.cookie_str: Optional[str] = None
        self.task: Optional[asyncio.Task] = None


class BrowserAuthService:
    def __init__(self):
        self.sessions: Dict[str, AuthSession] = {}
        self.platforms = {
            "xiaohongshu": {
                "login_url": "https://www.xiaohongshu.com/explore",
                "qrcode_selector": ".qrcode-img, img[class*='qrcode'], img[src*='qrcode']",
                "success_selector": ".user.side-bar-component",
                "check_url": "https://www.xiaohongshu.com/explore",
                "check_selector": ".user.side-bar-component",
                "domain": ".xiaohongshu.com",
            },
            "zhihu": {
                "login_url": "https://www.zhihu.com/signin?next=%2F",
                "qrcode_selector": "canvas",
                "success_selector": ".AppHeader-profile",
                "check_url": "https://www.zhihu.com",
                "check_selector": ".AppHeader-profile",
                "domain": ".zhihu.com",
            },
            "weibo": {
                "login_url": "https://passport.weibo.com/sso/signin",
                "qrcode_selector": ".qr-img-box img, .LoginCard_wrap_1Zngm img, img[src*='qrcode']",
                "success_selector": ".Frame_wrap_3C2R6",
                "check_url": "https://weibo.com",
                "check_selector": ".Frame_wrap_3C2R6",
                "domain": ".weibo.com",
            },
        }

    # ------------------------------------------------------------------
    # 公开 API
    # ------------------------------------------------------------------

    async def start_auth_session(self, platform: str) -> AuthSessionStatus:
        if platform not in self.platforms:
            raise ValueError(f"不支持的平台: {platform}")

        session = AuthSession(platform)
        self.sessions[session.session_id] = session

        # Drive auth flow async in main loop, which delegates playwright parts
        session.task = asyncio.create_task(self._drive_auth_flow_wrapper(session))

        return await self.get_session_status(session.session_id)

    async def get_session_status(self, session_id: str) -> AuthSessionStatus:
        session = self.sessions.get(session_id)
        if not session:
            raise ValueError(f"会话不存在: {session_id}")
        return AuthSessionStatus(
            session_id=session.session_id,
            platform=session.platform,
            status=session.status,
            message=session.message,
            qrcode_b64=session.qrcode_b64,
        )

    async def get_session_qrcode(self, session_id: str) -> Optional[str]:
        session = self.sessions.get(session_id)
        if not session:
            raise ValueError(f"会话不存在: {session_id}")
        return session.qrcode_b64

    async def check_platform_status(self, platform: str) -> bool:
        if platform not in self.platforms:
            return False
            
        cookie_str = await get_setting_value(f"{platform}_cookie")
        if not cookie_str:
            return False
            
        config = self.platforms[platform]
        domain = config["domain"]

        cookies = []
        for item in cookie_str.split(";"):
            if "=" in item:
                name, value = item.strip().split("=", 1)
                if name and value:
                    cookies.append({"name": name, "value": value, "domain": domain, "path": "/"})

        return await browser_manager.submit_coro(self._check_status_pw_job(platform, cookies, config))

    async def logout_platform(self, platform: str):
        if platform not in self.platforms:
            return
        await delete_setting_value(f"{platform}_cookie")
        logger.info(f"已删除 {platform}_cookie")

    async def cancel_session(self, session_id: str):
        session = self.sessions.get(session_id)
        if session:
            session.status = "failed"
            session.message = "已取消"
            if session.task and not session.task.done():
                session.task.cancel()
        self.sessions.pop(session_id, None)

    # ------------------------------------------------------------------
    # 内部 Playwright 作业协程（被 submit 到专用后台 Loop）
    # ------------------------------------------------------------------

    async def _check_status_pw_job(self, platform: str, cookies: list, config: dict) -> bool:
        browser = browser_manager.get_browser()
        context = await browser.new_context(
            viewport=browser_manager.fetch_viewport,
            user_agent=browser_manager.ua
        )
        if cookies:
            await context.add_cookies(cookies)
            
        try:
            page = await context.new_page()
            await page.goto(config["check_url"], timeout=15000)
            await asyncio.sleep(2)

            if "login" in page.url or "signin" in page.url:
                return False

            try:
                element = await page.wait_for_selector(config["check_selector"], timeout=5000)
                return element is not None
            except Exception:
                return False
        except Exception as e:
            logger.warning(f"平台状态检测失败 [{platform}]: {e}")
            return False
        finally:
            await context.close()

    async def _auth_flow_pw_job(self, session: AuthSession, config: dict):
        browser = browser_manager.get_browser()
        context = await browser.new_context(
            viewport=browser_manager.auth_viewport,
            user_agent=browser_manager.ua
        )
        try:
            page = await context.new_page()
            await page.goto(config["login_url"])
            await page.wait_for_load_state("networkidle")
            await asyncio.sleep(2)

            logger.info(f"[{session.platform}] 已导航到 {page.url}")

            # --- 定位二维码 ---
            qr_element = None

            if session.platform == "weibo":
                for img in await page.locator("img").all():
                    src = await img.get_attribute("src") or ""
                    if "qr" in src.lower() or "qrcode" in src.lower():
                        box = await img.bounding_box()
                        if box and box["width"] > 80 and abs(box["width"] - box["height"]) < 15:
                            qr_element = img
                            break
                if not qr_element:
                    for sel in [".qr-img-box img", "img[src*='qrcode']", ".LoginCard_wrap_1Zngm img"]:
                        try:
                            el = page.locator(sel).first
                            if await el.is_visible():
                                qr_element = el
                                break
                        except Exception:
                            pass

            elif session.platform == "zhihu":
                try:
                    await page.wait_for_selector("canvas", timeout=15000)
                    for canvas in await page.locator("canvas").all():
                        box = await canvas.bounding_box()
                        if box and box["width"] > 80 and abs(box["width"] - box["height"]) < 20:
                            qr_element = canvas
                            break
                except Exception as e:
                    logger.warning(f"知乎 canvas 未找到: {e}")

            else:
                for sel in config["qrcode_selector"].split(","):
                    sel = sel.strip()
                    try:
                        el = await page.wait_for_selector(sel, timeout=10000)
                        if el and await el.is_visible():
                            qr_element = el
                            break
                    except Exception:
                        pass

            if qr_element is None:
                session.status = "failed"
                session.message = f"无法定位 {session.platform} 的二维码，请重试"
                return

            # 截图
            qr_bytes = await qr_element.screenshot()
            session.qrcode_b64 = base64.b64encode(qr_bytes).decode("utf-8")
            session.status = "waiting_scan"
            session.message = "二维码已就绪，请使用手机扫码"
            logger.info(f"[{session.platform}] 二维码截图成功")

            # --- 轮询登录成功 ---
            for _ in range(60):
                if session.status == "failed":
                    break

                await asyncio.sleep(2)
                cookies = await context.cookies()
                has_auth = False

                if session.platform == "weibo":
                    has_auth = any(c["name"] == "SUB" for c in cookies)

                elif session.platform == "zhihu":
                    has_auth = "signin" not in page.url and "zhihu.com" in page.url
                    if not has_auth:
                        try:
                            el = await page.query_selector(config["success_selector"])
                            has_auth = el is not None
                        except Exception:
                            pass

                elif session.platform == "xiaohongshu":
                    try:
                        el = await page.query_selector(config["success_selector"])
                        has_auth = el is not None
                    except Exception:
                        pass

                if has_auth:
                    session.status = "success"
                    session.message = "登录成功"
                    session.cookie_str = "; ".join([f"{c['name']}={c['value']}" for c in cookies])
                    logger.info(f"[{session.platform}] 登录成功")
                    break

            if session.status == "waiting_scan":
                session.status = "timeout"
                session.message = "等待扫码超时，请重试"

        except Exception as e:
            import traceback
            logger.error(f"[{session.platform}] 认证流异常: {repr(e)}\n{traceback.format_exc()}")
            session.status = "failed"
            session.message = repr(e)
        finally:
            await context.close()

    async def _drive_auth_flow_wrapper(self, session: AuthSession):
        config = self.platforms[session.platform]
        try:
            # 委托给专用 Loop 运行
            await browser_manager.submit_coro(self._auth_flow_pw_job(session, config))
            
            # 成功后持久化 Cookie
            if session.status == "success" and session.cookie_str:
                await set_setting_value(
                    key=f"{session.platform}_cookie",
                    value=session.cookie_str,
                    category="platform",
                    description=f"{session.platform} 自动化登录 Cookie",
                )
                logger.info(f"[{session.platform}] Cookie 已保存")
        except asyncio.CancelledError:
             pass


browser_auth_service = BrowserAuthService()
