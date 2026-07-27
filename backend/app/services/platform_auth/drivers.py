"""各平台二维码登录协议驱动。

驱动只负责平台协议；会话生命周期、超时、状态发布和凭据持久化由
``BrowserAuthService`` 统一处理。
"""

from __future__ import annotations

import json
import random
import time
from abc import ABC, abstractmethod
from dataclasses import dataclass
from enum import StrEnum
from http.cookies import SimpleCookie
from urllib.parse import parse_qs, urlencode, urlparse

import httpx
from xhshow import SessionManager, Xhshow

from app.adapters.xiaohongshu_profile import build_xhs_crypto_config


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
        await self._client.post(f"{self.base}/udid", json={}, headers=self._headers)

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
        response.raise_for_status()
        data = response.json()
        error = data.get("error") if isinstance(data.get("error"), dict) else {}
        if error.get("code") == 40352:
            return QrLoginPollResult(
                QrLoginState.NEEDS_CAPTCHA,
                "请先完成人机验证",
                captcha_url=str(error.get("redirect") or ""),
            )
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
    host = "https://edith.xiaohongshu.com"
    home = "https://www.xiaohongshu.com"

    def __init__(self) -> None:
        self._client: httpx.AsyncClient | None = None
        self._qr_id = ""
        self._code = ""
        self._ua = (
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) "
            "AppleWebKit/537.36 (KHTML, like Gecko) Chrome/145.0.0.0 Safari/537.36"
        )
        config = build_xhs_crypto_config(self._ua)
        self._signer = Xhshow(config)
        self._session_manager = SessionManager(config)
        self._cookies: dict[str, str] = {}

    async def open(self) -> None:
        self._client = httpx.AsyncClient(timeout=30, follow_redirects=True)
        self._cookies = {
            "a1": "".join(random.choices("0123456789abcdef", k=24))
            + str(int(time.time() * 1000))
            + "".join(random.choices("0123456789abcdef", k=15)),
            "webId": "".join(random.choices("0123456789abcdef", k=32)),
        }
        try:
            _, response = await self._api("POST", "/api/sns/web/v1/login/activate", {})
            self._merge_response_cookies(response)
        except Exception:
            pass

    async def create_challenge(self) -> QrLoginChallenge:
        data, response = await self._api(
            "POST", "/api/sns/web/v1/login/qrcode/create", {"qr_type": 1}
        )
        self._merge_response_cookies(response)
        self._qr_id = str(data.get("qr_id") or "")
        self._code = str(data.get("code") or "")
        url = str(data.get("url") or "")
        if not self._qr_id or not self._code or not url:
            raise RuntimeError("小红书登录接口未返回有效二维码")
        return QrLoginChallenge(url, "请使用小红书 App 扫码")

    async def poll(self) -> QrLoginPollResult:
        data, _ = await self._api(
            "POST",
            "/api/qrcode/userinfo",
            {"qrId": self._qr_id, "code": self._code},
            {"service-tag": "webcn"},
        )
        status = data.get("codeStatus", -1)
        if status == 1:
            return QrLoginPollResult(QrLoginState.SCANNED, "已扫码，等待确认")
        if status != 2:
            return QrLoginPollResult(QrLoginState.WAITING, "等待扫码")

        confirmed, response = await self._api(
            "GET",
            "/api/sns/web/v1/login/qrcode/status",
            {"qr_id": self._qr_id, "code": self._code},
        )
        login_info = confirmed.get("login_info") or {}
        if isinstance(login_info, dict):
            if login_info.get("session"):
                self._cookies["web_session"] = str(login_info["session"])
            if login_info.get("secure_session"):
                self._cookies["web_session_sec"] = str(login_info["secure_session"])
        self._merge_response_cookies(response)
        cookie = "; ".join(f"{name}={value}" for name, value in self._cookies.items())
        return QrLoginPollResult(QrLoginState.SUCCESS, "登录成功", cookie)

    async def _api(
        self,
        method: str,
        uri: str,
        payload: dict,
        extra_headers: dict[str, str] | None = None,
    ) -> tuple[dict, httpx.Response]:
        client = self._require_client()
        headers = self._headers()
        if method == "POST":
            headers.update(
                self._signer.sign_headers_post(
                    uri,
                    self._cookies,
                    payload=payload,
                    session=self._session_manager,
                )
            )
            if extra_headers:
                headers.update(extra_headers)
            response = await client.post(
                f"{self.host}{uri}",
                headers=headers,
                content=json.dumps(payload, separators=(",", ":")),
            )
        else:
            headers.update(
                self._signer.sign_headers_get(
                    uri,
                    self._cookies,
                    params=payload,
                    session=self._session_manager,
                )
            )
            full_uri = f"{uri}?{urlencode(payload)}" if payload else uri
            response = await client.get(f"{self.host}{full_uri}", headers=headers)
        response.raise_for_status()
        body = response.json()
        if body.get("success") or body.get("code") == 0:
            return body.get("data") or {}, response
        raise RuntimeError(f"小红书接口失败: {json.dumps(body, ensure_ascii=False)[:200]}")

    def _headers(self) -> dict[str, str]:
        return {
            "user-agent": self._ua,
            "content-type": "application/json;charset=UTF-8",
            "cookie": "; ".join(f"{k}={v}" for k, v in self._cookies.items()),
            "origin": self.home,
            "referer": f"{self.home}/",
            "sec-ch-ua": '"Not:A-Brand";v="99", "Google Chrome";v="145", "Chromium";v="145"',
            "sec-ch-ua-mobile": "?0",
            "sec-ch-ua-platform": '"macOS"',
            "sec-fetch-dest": "empty",
            "sec-fetch-mode": "cors",
            "sec-fetch-site": "same-site",
            "accept": "application/json, text/plain, */*",
        }

    def _merge_response_cookies(self, response: httpx.Response) -> None:
        for name, value in response.cookies.items():
            if value:
                self._cookies[name] = value

    def _require_client(self) -> httpx.AsyncClient:
        if self._client is None:
            raise RuntimeError("小红书登录驱动尚未初始化")
        return self._client

    async def close(self) -> None:
        if self._client is not None:
            await self._client.aclose()
            self._client = None
