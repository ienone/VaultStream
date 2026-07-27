"""各平台二维码登录协议驱动。

驱动只负责平台协议；会话生命周期、超时、状态发布和凭据持久化由
``BrowserAuthService`` 统一处理。
"""

from __future__ import annotations

from abc import ABC, abstractmethod
from dataclasses import dataclass
from enum import StrEnum
from http.cookies import SimpleCookie
from typing import Any
from urllib.parse import parse_qs, urlparse

import httpx

from app.adapters.browser import browser_manager


class QrLoginState(StrEnum):
    WAITING = "waiting"
    SCANNED = "scanned"
    SUCCESS = "success"
    EXPIRED = "expired"
    NEEDS_CAPTCHA = "needs_captcha"


@dataclass(frozen=True)
class QrLoginChallenge:
    content: str
    message: str


@dataclass(frozen=True)
class QrLoginPollResult:
    state: QrLoginState
    message: str
    cookie_str: str | None = None
    captcha_url: str | None = None


class QrLoginDriver(ABC):
    poll_interval = 2.0
    timeout = 240.0

    @abstractmethod
    async def open(self) -> None:
        """创建客户端并完成平台预热。"""

    @abstractmethod
    async def create_challenge(self) -> QrLoginChallenge:
        """创建二维码挑战。"""

    @abstractmethod
    async def poll(self) -> QrLoginPollResult:
        """读取一次平台登录状态。"""

    @abstractmethod
    async def close(self) -> None:
        """释放网络资源。"""


def _cookie_string(client: httpx.AsyncClient) -> str:
    cookies = {cookie.name: cookie.value for cookie in client.cookies.jar if cookie.value}
    return "; ".join(f"{name}={value}" for name, value in cookies.items())


class BilibiliQrLoginDriver(QrLoginDriver):
    """Bilibili Web 二维码登录。

    状态码遵循官方 Web 登录接口：86101 未扫码、86090 已扫码待确认、
    86038 二维码失效、0 登录成功。
    """

    poll_interval = 3.0

    def __init__(self) -> None:
        self._client: httpx.AsyncClient | None = None
        self._qrcode_key = ""

    async def open(self) -> None:
        self._client = httpx.AsyncClient(
            timeout=15,
            follow_redirects=True,
            headers={
                "user-agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) "
                "AppleWebKit/537.36 (KHTML, like Gecko) Chrome/145.0.0.0 Safari/537.36",
                "referer": "https://www.bilibili.com/",
            },
        )

    async def create_challenge(self) -> QrLoginChallenge:
        client = self._require_client()
        response = await client.get(
            "https://passport.bilibili.com/x/passport-login/web/qrcode/generate"
        )
        response.raise_for_status()
        payload = response.json()
        if payload.get("code") != 0:
            raise RuntimeError(f"Bilibili 创建二维码失败: {payload.get('message', '未知错误')}")
        data = payload.get("data") or {}
        self._qrcode_key = str(data.get("qrcode_key") or "")
        url = str(data.get("url") or "")
        if not self._qrcode_key or not url:
            raise RuntimeError("Bilibili 登录接口未返回有效二维码")
        return QrLoginChallenge(url, "请使用哔哩哔哩 App 扫码")

    async def poll(self) -> QrLoginPollResult:
        client = self._require_client()
        response = await client.get(
            "https://passport.bilibili.com/x/passport-login/web/qrcode/poll",
            params={"qrcode_key": self._qrcode_key},
        )
        response.raise_for_status()
        payload = response.json()
        if payload.get("code") != 0:
            raise RuntimeError(f"Bilibili 查询登录状态失败: {payload.get('message', '未知错误')}")
        data = payload.get("data") or {}
        code = data.get("code")
        if code == 0:
            self._capture_set_cookie(response)
            cookie = _cookie_string(client)
            if not cookie:
                raise RuntimeError("Bilibili 登录成功但未收到 Cookie")
            return QrLoginPollResult(QrLoginState.SUCCESS, "登录成功", cookie)
        if code == 86090:
            return QrLoginPollResult(QrLoginState.SCANNED, "已扫码，请在 App 中确认")
        if code == 86038:
            return QrLoginPollResult(QrLoginState.EXPIRED, "二维码已过期")
        return QrLoginPollResult(QrLoginState.WAITING, "等待扫码")

    def _capture_set_cookie(self, response: httpx.Response) -> None:
        client = self._require_client()
        for value in response.headers.get_list("set-cookie"):
            parsed = SimpleCookie()
            parsed.load(value)
            for morsel in parsed.values():
                client.cookies.set(morsel.key, morsel.value, domain=".bilibili.com")

    def _require_client(self) -> httpx.AsyncClient:
        if self._client is None:
            raise RuntimeError("Bilibili 登录驱动尚未初始化")
        return self._client

    async def close(self) -> None:
        if self._client is not None:
            await self._client.aclose()
            self._client = None


class WeiboQrLoginDriver(QrLoginDriver):
    base = "https://passport.weibo.com"

    def __init__(self) -> None:
        self._client: httpx.AsyncClient | None = None
        self._qrid = ""
        self._headers = {
            "User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) "
            "AppleWebKit/537.36 (KHTML, like Gecko) Chrome/145.0.0.0 Safari/537.36",
            "Referer": f"{self.base}/sso/signin",
            "Accept": "application/json, text/plain, */*",
        }

    async def open(self) -> None:
        self._client = httpx.AsyncClient(timeout=15, follow_redirects=True)

    async def create_challenge(self) -> QrLoginChallenge:
        client = self._require_client()
        response = await client.get(
            f"{self.base}/sso/v2/qrcode/image",
            params={"size": 180},
            headers=self._headers,
        )
        response.raise_for_status()
        data = response.json().get("data") or {}
        self._qrid = str(data.get("qrid") or "")
        image_url = str(data.get("image") or "")
        parsed = urlparse(image_url)
        scan_url = parse_qs(parsed.query).get("data", [image_url])[0]
        if not self._qrid or not scan_url:
            raise RuntimeError("微博登录接口未返回有效二维码")
        return QrLoginChallenge(scan_url, "请使用微博 App 扫码")

    async def poll(self) -> QrLoginPollResult:
        client = self._require_client()
        response = await client.get(
            f"{self.base}/sso/v2/qrcode/check",
            params={"qrid": self._qrid},
            headers=self._headers,
        )
        response.raise_for_status()
        payload = response.json()
        retcode = payload.get("retcode")
        if retcode == 50114002:
            return QrLoginPollResult(QrLoginState.SCANNED, "已扫码，等待确认")
        if retcode != 20000000:
            return QrLoginPollResult(QrLoginState.WAITING, "等待扫码")

        data = payload.get("data") or {}
        sso_url = data.get("alt") or data.get("url")
        if sso_url:
            await client.get(str(sso_url), headers=self._headers)
        cookie = _cookie_string(client)
        if not cookie:
            raise RuntimeError("微博登录成功但未收到 Cookie")
        return QrLoginPollResult(QrLoginState.SUCCESS, "登录成功", cookie)

    def _require_client(self) -> httpx.AsyncClient:
        if self._client is None:
            raise RuntimeError("微博登录驱动尚未初始化")
        return self._client

    async def close(self) -> None:
        if self._client is not None:
            await self._client.aclose()
            self._client = None


class ZhihuQrLoginDriver(QrLoginDriver):
    base = "https://www.zhihu.com"
    poll_interval = 0.5
    timeout = 180.0

    def __init__(self) -> None:
        self._client: httpx.AsyncClient | None = None
        self._token = ""
        self._headers = {
            "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) "
            "AppleWebKit/537.36 (KHTML, like Gecko) Chrome/145.0.0.0 Safari/537.36",
            "Accept": "application/json, text/plain, */*",
            "Referer": f"{self.base}/signin",
            "Origin": self.base,
            "x-requested-with": "fetch",
        }

    async def open(self) -> None:
        self._client = httpx.AsyncClient(timeout=15, follow_redirects=True)
        await self._client.get(f"{self.base}/signin", headers=self._headers)
        self._update_xsrf()
        udid_response = await self._client.post(
            f"{self.base}/udid", json={}, headers=self._headers
        )
        if udid_response.is_success and udid_response.text.strip():
            self._headers["x-du-bid"] = udid_response.text.strip()
        await self._client.get(
            f"{self.base}/api/v3/oauth/captcha/v2",
            params={"type": "captcha_sign_in"},
            headers=self._headers,
        )

    async def create_challenge(self) -> QrLoginChallenge:
        client = self._require_client()
        response = await client.post(
            f"{self.base}/api/v3/account/api/login/qrcode",
            json={},
            headers=self._headers,
        )
        response.raise_for_status()
        data = response.json()
        self._token = str(data.get("token") or data.get("qrcode_token") or "")
        link = str(data.get("link") or "")
        if not self._token or not link:
            raise RuntimeError("知乎登录接口未返回有效二维码")
        return QrLoginChallenge(link, "请使用知乎 App 扫码")

    async def poll(self) -> QrLoginPollResult:
        client = self._require_client()
        self._update_xsrf()
        headers = {
            **self._headers,
            "sec-fetch-dest": "empty",
            "sec-fetch-mode": "cors",
            "sec-fetch-site": "same-origin",
            "x-zse-93": "101_3_3.0",
        }
        response = await client.get(
            f"{self.base}/api/v3/account/api/login/qrcode/{self._token}/scan_info",
            headers=headers,
        )
        try:
            data = response.json()
        except ValueError:
            data = {}
        error = data.get("error") if isinstance(data.get("error"), dict) else {}
        if error.get("code") == 40352:
            return QrLoginPollResult(
                QrLoginState.NEEDS_CAPTCHA,
                "知乎要求先完成安全验证，验证后将继续等待扫码",
                captcha_url=str(error.get("redirect") or ""),
            )
        try:
            response.raise_for_status()
        except httpx.HTTPStatusError as exc:
            raise RuntimeError(
                f"知乎登录接口暂时拒绝请求（HTTP {response.status_code}），"
                "请重新生成二维码后重试"
            ) from exc
        status = str(data.get("login_status") or "").upper()
        if data.get("access_token") or data.get("user_id") or status in {"CONFIRMED", "SUCCESS"}:
            await client.get(f"{self.base}/api/v4/me", headers=headers)
            cookie = _cookie_string(client)
            if not cookie:
                raise RuntimeError("知乎登录成功但未收到 Cookie")
            return QrLoginPollResult(QrLoginState.SUCCESS, "登录成功", cookie)
        if data.get("status") == 1:
            return QrLoginPollResult(QrLoginState.SCANNED, "已扫码，等待确认")
        return QrLoginPollResult(QrLoginState.WAITING, "等待扫码")

    def _update_xsrf(self) -> None:
        client = self._require_client()
        xsrf = next((c.value for c in client.cookies.jar if c.name == "_xsrf"), "")
        if xsrf:
            self._headers["x-xsrftoken"] = xsrf

    def _require_client(self) -> httpx.AsyncClient:
        if self._client is None:
            raise RuntimeError("知乎登录驱动尚未初始化")
        return self._client

    async def close(self) -> None:
        if self._client is not None:
            await self._client.aclose()
            self._client = None


class XiaohongshuQrLoginDriver(QrLoginDriver):
    """由真实浏览器页面驱动的小红书二维码登录。

    小红书的扫码状态接口依赖页面运行时生成的签名、指纹和会话上下文。
    驱动只观察页面自身发出的响应和 Cookie 变化，不在 Python 中复刻该协议。
    """

    home = "https://www.xiaohongshu.com"
    login_url = f"{home}/login"
    qr_create_endpoint = "/api/sns/web/v1/login/qrcode/create"
    qr_userinfo_endpoint = "/api/qrcode/userinfo"
    qr_status_endpoint = "/api/sns/web/v1/login/qrcode/status"

    def __init__(self, manager: Any | None = None) -> None:
        self._browser_manager = manager or browser_manager
        self._context: Any | None = None
        self._page: Any | None = None
        self._initial_web_session = ""
        self._browser_qr_status = -1
        self._browser_confirmed = False
        self._browser_error = ""

    async def open(self) -> None:
        async def _open() -> None:
            browser = self._browser_manager.get_browser()
            self._context = await browser.new_context(
                user_agent=self._browser_manager.ua,
                viewport=self._browser_manager.auth_viewport,
            )
            self._page = await self._context.new_page()
            self._page.on("response", self._handle_browser_response)

        await self._browser_manager.submit_coro(_open())

    async def create_challenge(self) -> QrLoginChallenge:
        async def _create() -> str:
            page = self._require_page()
            try:
                async with page.expect_response(
                    lambda response: (
                        self.qr_create_endpoint in response.url
                        and response.request.method == "POST"
                    ),
                    timeout=30_000,
                ) as response_info:
                    await page.goto(
                        self.login_url,
                        wait_until="domcontentloaded",
                        timeout=30_000,
                    )
                response = await response_info.value
                if not response.ok:
                    raise RuntimeError(
                        f"小红书页面创建二维码失败（HTTP {response.status}）"
                    )
                data = self._response_data(await response.json())
                url = str(data.get("url") or "")
                if not url:
                    raise RuntimeError("小红书登录页面未返回有效二维码")
                cookies = self._cookie_map(await self._context.cookies())
                self._initial_web_session = cookies.get("web_session", "")
                return url
            except RuntimeError:
                raise
            except Exception as exc:
                raise RuntimeError("小红书登录页面加载失败，请重新生成二维码") from exc

        url = await self._browser_manager.submit_coro(_create())
        return QrLoginChallenge(url, "请使用小红书 App 扫码")

    async def poll(self) -> QrLoginPollResult:
        async def _poll() -> QrLoginPollResult:
            page = self._require_page()
            context = self._require_context()
            if self._browser_error:
                raise RuntimeError(self._browser_error)

            cookies = self._cookie_map(await context.cookies())
            current_session = cookies.get("web_session", "")
            session_changed = bool(
                current_session and current_session != self._initial_web_session
            )
            page_content = await page.content()
            if "请通过验证" in page_content:
                return QrLoginPollResult(
                    QrLoginState.NEEDS_CAPTCHA,
                    "小红书要求完成人机验证，请取消后重试或手动配置 Cookie",
                )

            if self._browser_confirmed or session_changed:
                required = ("a1", "webId", "web_session")
                missing = [name for name in required if not cookies.get(name)]
                if missing:
                    return QrLoginPollResult(
                        QrLoginState.SCANNED,
                        "已确认，正在等待浏览器完成登录",
                    )
                cookie = "; ".join(
                    f"{name}={value}" for name, value in sorted(cookies.items()) if value
                )
                return QrLoginPollResult(QrLoginState.SUCCESS, "登录成功", cookie)
            if self._browser_qr_status in {1, 2}:
                return QrLoginPollResult(QrLoginState.SCANNED, "已扫码，等待确认")
            return QrLoginPollResult(QrLoginState.WAITING, "等待扫码")

        return await self._browser_manager.submit_coro(_poll())

    async def _handle_browser_response(self, response: Any) -> None:
        url = response.url
        if (
            self.qr_userinfo_endpoint not in url
            and self.qr_status_endpoint not in url
        ):
            return
        try:
            payload = await response.json()
            data = self._response_data(payload)
        except Exception:
            if not response.ok:
                self._browser_error = (
                    f"小红书登录页面请求失败（HTTP {response.status}），请重新生成二维码"
                )
            return

        if self.qr_userinfo_endpoint in url:
            try:
                self._browser_qr_status = int(data.get("codeStatus", -1))
            except (TypeError, ValueError):
                self._browser_qr_status = -1
            return

        if response.ok and (payload.get("success") or payload.get("code") == 0):
            self._browser_confirmed = True
        elif not response.ok:
            self._browser_error = (
                f"小红书登录页面请求失败（HTTP {response.status}），请重新生成二维码"
            )

    @staticmethod
    def _response_data(payload: Any) -> dict[str, Any]:
        if not isinstance(payload, dict):
            return {}
        data = payload.get("data")
        return data if isinstance(data, dict) else payload

    @staticmethod
    def _cookie_map(raw_cookies: list[dict[str, Any]]) -> dict[str, str]:
        return {
            str(cookie.get("name")): str(cookie.get("value"))
            for cookie in raw_cookies
            if cookie.get("name") and cookie.get("value")
            and str(cookie.get("domain", "")).endswith("xiaohongshu.com")
        }

    def _require_page(self) -> Any:
        if self._page is None:
            raise RuntimeError("小红书浏览器登录驱动尚未初始化")
        return self._page

    def _require_context(self) -> Any:
        if self._context is None:
            raise RuntimeError("小红书浏览器登录驱动尚未初始化")
        return self._context

    async def close(self) -> None:
        if self._context is None:
            return

        async def _close() -> None:
            if self._context is not None:
                await self._context.close()
            self._context = None
            self._page = None

        await self._browser_manager.submit_coro(_close())
