"""统一的平台二维码认证服务。"""

from __future__ import annotations

import asyncio
import base64
import io
import time
import uuid
from collections.abc import Callable
from contextlib import suppress
from typing import Optional

import httpx
import qrcode
from loguru import logger
from pydantic import BaseModel
from xhshow import SessionManager, Xhshow

from app.adapters.browser import browser_manager
from app.adapters.utils.cookie_utils import strip_cookie_wrapper_quotes
from app.adapters.xiaohongshu_profile import build_xhs_crypto_config
from app.services.config_service import ConfigService
from app.services.platform_auth import (
    BilibiliQrLoginDriver,
    QrLoginDriver,
    QrLoginState,
    WeiboQrLoginDriver,
    XiaohongshuQrLoginDriver,
    ZhihuQrLoginDriver,
)


class AuthSessionStatus(BaseModel):
    session_id: str
    platform: str
    status: str
    message: Optional[str] = None
    qrcode_b64: Optional[str] = None
    captcha_url: Optional[str] = None


class AuthSession:
    def __init__(self, platform: str):
        self.session_id = str(uuid.uuid4())
        self.platform = platform
        self.status = "initializing"
        self.qrcode_b64: Optional[str] = None
        self.message: Optional[str] = None
        self.cookie_str: Optional[str] = None
        self.captcha_url: Optional[str] = None
        self.task: Optional[asyncio.Task] = None


class BrowserAuthService:
    """管理统一会话状态，并将平台协议委托给二维码登录驱动。"""

    def __init__(
        self,
        config_service: ConfigService | None = None,
        driver_factories: dict[str, Callable[[], QrLoginDriver]] | None = None,
    ):
        self._config_service = config_service or ConfigService()
        self.sessions: dict[str, AuthSession] = {}
        self._zhihu_refresh_lock = asyncio.Lock()
        self._zhihu_refresh_inflight: Optional[asyncio.Task] = None
        self._zhihu_refresh_last_ts = 0.0
        self._zhihu_refresh_last_result: Optional[bool] = None
        self._zhihu_refresh_cooldown_seconds = 90.0
        self._driver_factories = driver_factories or {
            "bilibili": BilibiliQrLoginDriver,
            "xiaohongshu": XiaohongshuQrLoginDriver,
            "weibo": WeiboQrLoginDriver,
            "zhihu": ZhihuQrLoginDriver,
        }
        self.platforms = {
            "bilibili": {
                "check_url": "https://api.bilibili.com/x/web-interface/nav",
                "auth_cookie_names": ["SESSDATA", "bili_jct"],
                "domain": ".bilibili.com",
            },
            "xiaohongshu": {
                "check_url": "https://edith.xiaohongshu.com/api/sns/web/v1/user/me",
                "auth_cookie_names": ["a1", "webId", "web_session"],
                "domain": ".xiaohongshu.com",
            },
            "zhihu": {
                "check_url": "https://www.zhihu.com/api/v4/me",
                "domain": ".zhihu.com",
            },
            "weibo": {
                "check_url": "https://passport.weibo.com/visitor/visitor?a=init",
                "auth_cookie_names": ["SUB"],
                "domain": ".weibo.com",
            },
        }

    async def start_auth_session(self, platform: str) -> AuthSessionStatus:
        if platform not in self.platforms:
            raise ValueError(f"不支持的平台: {platform}")

        session = AuthSession(platform)
        self.sessions[session.session_id] = session
        factory = self._driver_factories.get(platform)
        if factory is None:
            session.status = "failed"
            session.message = f"尚未实现 {platform} 的二维码登录流程"
        else:
            session.task = asyncio.create_task(self._run_qr_flow(session, factory()))
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
            captcha_url=session.captcha_url,
        )

    async def get_session_qrcode(self, session_id: str) -> Optional[str]:
        session = self.sessions.get(session_id)
        if not session:
            raise ValueError(f"会话不存在: {session_id}")
        return session.qrcode_b64

    async def check_platform_status(self, platform: str) -> bool:
        if platform not in self.platforms:
            return False
        cookie_str = await self._config_service.get_platform_cookie_string(
            platform,
            fresh=True,
        )
        if not cookie_str:
            return False
        check = getattr(self, f"_check_{platform}_status", None)
        return bool(await check(cookie_str)) if check else False

    async def logout_platform(self, platform: str) -> None:
        if platform not in self.platforms:
            return
        keys = [f"{platform}_cookie"]
        if platform == "bilibili":
            keys.extend(["bilibili_bili_jct", "bilibili_buvid3"])
        for key in keys:
            await self._config_service.delete_value(key)
        logger.info("已清除 {} 平台登录配置", platform)

    async def cancel_session(self, session_id: str) -> None:
        session = self.sessions.get(session_id)
        if session:
            session.status = "failed"
            session.message = "已取消"
            if session.task and not session.task.done():
                session.task.cancel()
                with suppress(asyncio.CancelledError):
                    await session.task
        self.sessions.pop(session_id, None)

    def _make_qr_b64(self, data: str) -> str:
        qr = qrcode.QRCode(border=2)
        qr.add_data(data)
        qr.make(fit=True)
        image = qr.make_image(fill_color="black", back_color="white")
        buffer = io.BytesIO()
        image.save(buffer, format="PNG")
        return base64.b64encode(buffer.getvalue()).decode("utf-8")

    async def _persist_cookie(self, session: AuthSession) -> None:
        await self._config_service.set_value(
            key=f"{session.platform}_cookie",
            value=session.cookie_str,
            category="platform",
            description=f"{session.platform} 自动化登录 Cookie",
        )
        logger.info("[{}] Cookie 已持久化", session.platform)

    async def _run_qr_flow(self, session: AuthSession, driver: QrLoginDriver) -> None:
        try:
            await driver.open()
            challenge = await driver.create_challenge()
            session.qrcode_b64 = self._make_qr_b64(challenge.content)
            session.status = "waiting_scan"
            session.message = challenge.message

            deadline = time.monotonic() + driver.timeout
            while time.monotonic() < deadline:
                await asyncio.sleep(driver.poll_interval)
                result = await driver.poll()
                session.message = result.message
                session.captcha_url = result.captcha_url

                if result.state == QrLoginState.NEEDS_CAPTCHA:
                    session.status = "needs_captcha"
                    continue
                if result.state == QrLoginState.EXPIRED:
                    session.status = "timeout"
                    return
                if result.state == QrLoginState.SUCCESS:
                    if not result.cookie_str:
                        raise RuntimeError("平台登录成功但未返回可保存的 Cookie")
                    session.cookie_str = result.cookie_str
                    session.status = "success"
                    await self._persist_cookie(session)
                    return
                session.status = "waiting_scan"

            session.status = "timeout"
            session.message = "扫码超时"
        except asyncio.CancelledError:
            session.status = "failed"
            session.message = "已取消"
            raise
        except Exception as exc:
            logger.exception("{} QR flow error: {}", session.platform, exc)
            session.status = "failed"
            session.message = str(exc)
        finally:
            await driver.close()

    async def _check_bilibili_status(self, cookie_str: str) -> bool:
        headers = self._cookie_headers(cookie_str)
        try:
            async with httpx.AsyncClient(timeout=10) as client:
                response = await client.get(self.platforms["bilibili"]["check_url"], headers=headers)
                data = response.json()
                return data.get("code") == 0 and (data.get("data") or {}).get("isLogin") is True
        except Exception:
            return False

    async def _check_xiaohongshu_status(self, cookie_str: str) -> bool:
        cookie_str = strip_cookie_wrapper_quotes(cookie_str)
        ua = (
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) "
            "AppleWebKit/537.36 (KHTML, like Gecko) Chrome/145.0.0.0 Safari/537.36"
        )
        uri = "/api/sns/web/v1/user/me"
        cookies = self._parse_cookies(cookie_str)
        try:
            config = build_xhs_crypto_config(ua)
            sign = Xhshow(config).sign_headers_get(
                uri,
                cookies,
                session=SessionManager(config),
            )
        except Exception as exc:
            logger.warning("[xiaohongshu] 检测签名失败: {}", exc)
            return False
        headers = {
            **self._cookie_headers(cookie_str, ua),
            "origin": "https://www.xiaohongshu.com",
            "referer": "https://www.xiaohongshu.com/",
            **sign,
        }
        try:
            async with httpx.AsyncClient(timeout=10) as client:
                response = await client.get(self.platforms["xiaohongshu"]["check_url"], headers=headers)
                return bool(response.json().get("success"))
        except Exception as exc:
            logger.warning("[xiaohongshu] 登录状态检测网络异常: {}", exc)
            return False

    async def _check_weibo_status(self, cookie_str: str) -> bool:
        try:
            async with httpx.AsyncClient(timeout=10, follow_redirects=False) as client:
                response = await client.get(
                    self.platforms["weibo"]["check_url"],
                    headers=self._cookie_headers(cookie_str),
                )
                return response.status_code == 200
        except Exception:
            return False

    async def _check_zhihu_status(self, cookie_str: str) -> bool:
        try:
            async with httpx.AsyncClient(timeout=10) as client:
                response = await client.get(
                    self.platforms["zhihu"]["check_url"],
                    headers={**self._cookie_headers(cookie_str), "accept": "application/json, text/plain, */*"},
                )
                data = response.json()
                return "id" in data or "name" in data
        except Exception:
            return False

    @staticmethod
    def _cookie_headers(cookie_str: str, user_agent: str | None = None) -> dict[str, str]:
        return {
            "user-agent": user_agent
            or "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 "
            "(KHTML, like Gecko) Chrome/145.0.0.0 Safari/537.36",
            "cookie": strip_cookie_wrapper_quotes(cookie_str),
        }

    @staticmethod
    def _parse_cookies(cookie_str: str) -> dict[str, str]:
        cookies: dict[str, str] = {}
        for item in strip_cookie_wrapper_quotes(cookie_str).split(";"):
            if "=" in item:
                name, value = item.strip().split("=", 1)
                cookies[name.strip()] = value.strip()
        return cookies

    async def refresh_zhihu_zse_cookie(
        self,
        target_url: str = "https://www.zhihu.com/people/liu-kan-shan-78",
    ) -> bool:
        now = time.monotonic()
        async with self._zhihu_refresh_lock:
            inflight = self._zhihu_refresh_inflight
            if inflight and not inflight.done():
                task = inflight
            elif (
                self._zhihu_refresh_last_result is not None
                and now - self._zhihu_refresh_last_ts < self._zhihu_refresh_cooldown_seconds
            ):
                return bool(self._zhihu_refresh_last_result)
            else:
                task = asyncio.create_task(self._refresh_zhihu_zse_cookie_impl(target_url))
                self._zhihu_refresh_inflight = task
        try:
            result = bool(await task)
        except Exception as exc:
            logger.error("提取知乎指纹失败: {}", exc)
            result = False
        async with self._zhihu_refresh_lock:
            self._zhihu_refresh_last_ts = time.monotonic()
            self._zhihu_refresh_last_result = result
            if self._zhihu_refresh_inflight is task:
                self._zhihu_refresh_inflight = None
        return result

    async def _refresh_zhihu_zse_cookie_impl(self, target_url: str) -> bool:
        cookie_str = await self._config_service.get_platform_cookie_string("zhihu", fresh=True)
        if not cookie_str:
            logger.warning("未配置 zhihu_cookie，无法刷新 __zse_ck")
            return False

        normalized = strip_cookie_wrapper_quotes(cookie_str)
        cookies = [
            {"name": name, "value": value, "domain": ".zhihu.com", "path": "/"}
            for name, value in self._parse_cookies(normalized).items()
        ]

        async def _browser_task() -> dict[str, str]:
            browser = browser_manager.get_browser()
            context = await browser.new_context(
                user_agent=self._cookie_headers("")["user-agent"],
                viewport={"width": 1280, "height": 720},
            )
            try:
                await context.add_cookies(cookies)
                page = await context.new_page()
                await page.goto(target_url, wait_until="networkidle", timeout=30000)
                await asyncio.sleep(5)
                return {
                    cookie["name"]: cookie["value"]
                    for cookie in await context.cookies()
                    if cookie["name"] in {"__zse_ck", "d_c0", "_zap", "_xsrf", "z_c0"}
                }
            finally:
                await context.close()

        extracted = await browser_manager.submit_coro(_browser_task())
        if not extracted.get("__zse_ck"):
            logger.warning("未能提取到新的 __zse_ck")
            return False
        merged = self._parse_cookies(normalized)
        merged.update(extracted)
        await self._config_service.set_value(
            key="zhihu_cookie",
            value="; ".join(f"{name}={value}" for name, value in merged.items()),
            category="platform",
        )
        logger.info("已成功合并并保存新的知乎 Cookie")
        return True


browser_auth_service = BrowserAuthService()
