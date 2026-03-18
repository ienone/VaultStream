"""
浏览器认证服务 - Async 派发版本

利用共享的 browser_manager 单例（提供专用后台 Loop），
将异步的登录流程打包为 coroutine，通过 submit_coro 安全执行。
"""

import asyncio
import base64
import io
import uuid
import os
import sys
import random
import time
import json
from pathlib import Path
from urllib.parse import urlparse, parse_qs
from typing import Dict, Optional

import httpx
import qrcode
from loguru import logger
from pydantic import BaseModel
from xhshow import Xhshow, SessionManager

from app.adapters.xiaohongshu_profile import build_xhs_crypto_config
from app.services.settings_service import set_setting_value, get_setting_value, delete_setting_value
from app.adapters.browser import browser_manager


class AuthSessionStatus(BaseModel):
    session_id: str
    platform: str
    status: str  # initializing, waiting_scan, success, timeout, failed, needs_captcha
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
    def __init__(self):
        self.sessions: Dict[str, AuthSession] = {}
        self.platforms = {
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

    # ------------------------------------------------------------------
    # 公开 API
    # ------------------------------------------------------------------

    async def start_auth_session(self, platform: str) -> AuthSessionStatus:
        if platform not in self.platforms:
            raise ValueError(f"不支持的平台: {platform}")

        session = AuthSession(platform)
        self.sessions[session.session_id] = session

        # 直接在当前 loop 启动异步流程
        flow_method = getattr(self, f"_{platform}_qr_flow", None)
        if flow_method:
            session.task = asyncio.create_task(flow_method(session))
        else:
            session.status = "failed"
            session.message = f"尚未实现 {platform} 的 HTTP QR 流程"

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
            
        cookie_str = await get_setting_value(f"{platform}_cookie")
        if not cookie_str:
            return False
            
        check_func = getattr(self, f"_check_{platform}_status", None)
        if check_func:
            return await check_func(cookie_str)
            
        return False

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
    # 内部 HTTP QR 流程
    # ------------------------------------------------------------------

    def _make_qr_b64(self, data: str) -> str:
        """生成 QR 码 base64。"""
        qr = qrcode.QRCode(border=2)
        qr.add_data(data)
        qr.make(fit=True)
        img = qr.make_image(fill_color="black", back_color="white")
        buffered = io.BytesIO()
        img.save(buffered, format="PNG")
        return base64.b64encode(buffered.getvalue()).decode("utf-8")

    async def _persist_cookie(self, session: AuthSession):
        await set_setting_value(
            key=f"{session.platform}_cookie",
            value=session.cookie_str,
            category="platform",
            description=f"{session.platform} 自动化登录 Cookie",
        )
        logger.info(f"[{session.platform}] Cookie 已持久化")

    async def _xiaohongshu_qr_flow(self, session: AuthSession):
        ua = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/145.0.0.0 Safari/537.36"
        host = "https://edith.xiaohongshu.com"
        home = "https://www.xiaohongshu.com"
        
        # 配置 xhshow 签名环境 (与 Adapter 保持一致)
        config = build_xhs_crypto_config(ua)
        xhs = Xhshow(config)
        sm = SessionManager(config)

        def get_headers(cookies):
            return {
                "user-agent": ua,
                "content-type": "application/json;charset=UTF-8",
                "cookie": "; ".join(f"{k}={v}" for k, v in cookies.items()),
                "origin": home, "referer": f"{home}/",
                "sec-ch-ua": '"Not:A-Brand";v="99", "Google Chrome";v="145", "Chromium";v="145"',
                "sec-ch-ua-mobile": "?0", "sec-ch-ua-platform": '"macOS"',
                "sec-fetch-dest": "empty", "sec-fetch-mode": "cors", "sec-fetch-site": "same-site",
                "accept": "application/json, text/plain, */*",
            }

        async def api_call(client, method, uri, payload, cookies, extra_headers=None):
            if method == "POST":
                sign = xhs.sign_headers_post(uri, cookies, payload=payload, session=sm)
                headers = {**get_headers(cookies), **sign}
                if extra_headers: headers.update(extra_headers)
                resp = await client.post(f"{host}{uri}", headers=headers, content=json.dumps(payload, separators=(",", ":")))
            else:
                sign = xhs.sign_headers_get(uri, cookies, params=payload, session=sm)
                # 构建带查询参数的完整 URI
                from urllib.parse import urlencode
                full_uri = f"{uri}?{urlencode(payload)}" if payload else uri
                headers = {**get_headers(cookies), **sign}
                resp = await client.get(f"{host}{full_uri}", headers=headers)
            
            data = resp.json()
            if data.get("success") or data.get("code") == 0:
                return data.get("data", {}), resp
            raise RuntimeError(f"XHS API 失败: {json.dumps(data, ensure_ascii=False)[:200]}")

        try:
            session.status = "initializing"
            # 生成模拟设备 ID
            a1 = "".join(random.choices("0123456789abcdef", k=24)) + str(int(time.time() * 1000)) + "".join(random.choices("0123456789abcdef", k=15))
            webid = "".join(random.choices("0123456789abcdef", k=32))
            cookies = {"a1": a1, "webId": webid}

            async with httpx.AsyncClient(timeout=30, follow_redirects=True) as client:
                # 1. 激活虚拟设备
                try:
                    data, resp = await api_call(client, "POST", "/api/sns/web/v1/login/activate", {}, cookies)
                    for n, v in resp.cookies.items(): 
                        if v: cookies[n] = v
                except Exception: pass

                # 2. 创建二维码会话
                data, resp = await api_call(client, "POST", "/api/sns/web/v1/login/qrcode/create", {"qr_type": 1}, cookies)
                qr_id, code, qr_url = data["qr_id"], data["code"], data.get("url", "")

                # 3. 渲染
                session.qrcode_b64 = self._make_qr_b64(qr_url)
                session.status = "waiting_scan"
                session.message = "请使用小红书 App 扫码"

                # 4. 轮询扫码状态
                start = time.time()
                while (time.time() - start) < 240:
                    await asyncio.sleep(2)
                    try:
                        sdata, _ = await api_call(client, "POST", "/api/qrcode/userinfo", 
                                                 {"qrId": qr_id, "code": code}, cookies, {"service-tag": "webcn"})
                    except Exception: continue
                        
                    cs = sdata.get("codeStatus", -1)
                    if cs == 1:
                        session.message = "已扫码，等待确认..."
                    elif cs == 2:
                        # 5. 确认成功，获取最终 Session
                        cdata, cresp = await api_call(client, "GET", "/api/sns/web/v1/login/qrcode/status",
                                                     {"qr_id": qr_id, "code": code}, cookies)
                        li = cdata.get("login_info", {})
                        if isinstance(li, dict):
                            if li.get("session"): cookies["web_session"] = str(li["session"])
                            if li.get("secure_session"): cookies["web_session_sec"] = str(li["secure_session"])
                        for n, v in cresp.cookies.items():
                            if v: cookies[n] = v
                        
                        session.cookie_str = "; ".join(f"{k}={v}" for k, v in cookies.items())
                        session.status = "success"
                        session.message = "登录成功"
                        break
                
                if session.status == "waiting_scan":
                    session.status = "timeout"
                    session.message = "扫码超时"

        except Exception as e:
            logger.error(f"XHS QR flow error: {e}")
            session.status = "failed"
            session.message = str(e)
        finally:
            if session.status == "success" and session.cookie_str:
                await self._persist_cookie(session)

    async def _weibo_qr_flow(self, session: AuthSession):
        BASE = "https://passport.weibo.com"
        HEADERS = {
            "User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/145.0.0.0 Safari/537.36",
            "Referer": f"{BASE}/sso/signin",
            "Accept": "application/json, text/plain, */*",
        }

        try:
            async with httpx.AsyncClient(timeout=15, follow_redirects=True) as client:
                # 1. 获取 QR
                resp = await client.get(f"{BASE}/sso/v2/qrcode/image", params={"size": 180}, headers=HEADERS)
                qr_data = resp.json()
                data = qr_data.get("data", {})
                qrid = data.get("qrid", "")
                image_url = data.get("image", "")

                # 2. 提取扫码链接并渲染
                parsed = urlparse(image_url)
                qs = parse_qs(parsed.query)
                scan_url = qs.get("data", [""])[0]
                if not scan_url:
                    scan_url = image_url

                session.qrcode_b64 = self._make_qr_b64(scan_url)
                session.status = "waiting_scan"
                session.message = "请使用微博 App 扫码"

                # 3. 轮询
                start = time.time()
                while (time.time() - start) < 240:
                    await asyncio.sleep(2)
                    try:
                        check_resp = await client.get(f"{BASE}/sso/v2/qrcode/check",
                            params={"qrid": qrid}, headers=HEADERS)
                        check_data = check_resp.json()
                    except Exception:
                        continue

                    retcode = check_data.get("retcode", -1)
                    if retcode == 50114002:
                        session.message = "已扫码，等待确认..."
                    elif retcode == 20000000:
                        # 4. 完成
                        cdata = check_data.get("data", {})
                        sso_url = cdata.get("alt") or cdata.get("url", "")
                        cookies = {}
                        
                        if sso_url:
                            sso_resp = await client.get(sso_url, headers=HEADERS)
                            for resp in sso_resp.history:
                                for name, value in resp.cookies.items():
                                    if value: cookies[name] = value
                            for name, value in sso_resp.cookies.items():
                                if value: cookies[name] = value

                        for cookie in client.cookies.jar:
                            if cookie.value: cookies[cookie.name] = cookie.value

                        session.cookie_str = "; ".join(f"{k}={v}" for k, v in cookies.items())
                        session.status = "success"
                        session.message = "登录成功"
                        break
                
                if session.status == "waiting_scan":
                    session.status = "timeout"
                    session.message = "扫码超时"

        except Exception as e:
            logger.error(f"Weibo QR flow error: {e}")
            session.status = "failed"
            session.message = str(e)
        finally:
            if session.status == "success" and session.cookie_str:
                await self._persist_cookie(session)

    async def _zhihu_qr_flow(self, session: AuthSession):
        BASE = "https://www.zhihu.com"
        HEADERS = {
            "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/145.0.0.0 Safari/537.36",
            "Accept": "application/json, text/plain, */*",
            "Referer": f"{BASE}/signin",
            "Origin": BASE,
            "x-requested-with": "fetch",
        }

        async with httpx.AsyncClient(timeout=15, follow_redirects=True) as client:
            try:
                # 1. 预热
                await client.get(f"{BASE}/signin", headers=HEADERS)
                xsrf = ""
                for c in client.cookies.jar:
                    if c.name == "_xsrf": xsrf = c.value
                
                h = {**HEADERS}
                if xsrf: h["x-xsrftoken"] = xsrf
                await client.post(f"{BASE}/udid", json={}, headers=h)
                
                # 2. 创建 QR
                r = await client.post(f"{BASE}/api/v3/account/api/login/qrcode", json={}, headers=h)
                qr_data = r.json()
                token = qr_data.get("token") or qr_data.get("qrcode_token", "")
                link = qr_data.get("link", "")

                session.qrcode_b64 = self._make_qr_b64(link)
                session.status = "waiting_scan"
                session.message = "请使用知乎 App 扫码"

                # 3. 轮询
                poll_headers = {
                    **h,
                    "sec-fetch-dest": "empty", "sec-fetch-mode": "cors", "sec-fetch-site": "same-origin",
                    "x-zse-93": "101_3_3.0",
                }
                start = time.time()
                while (time.time() - start) < 180:
                    await asyncio.sleep(0.5)
                    xsrf = ""
                    for c in client.cookies.jar:
                        if c.name == "_xsrf": xsrf = c.value
                    if xsrf: poll_headers["x-xsrftoken"] = xsrf

                    resp = await client.get(f"{BASE}/api/v3/account/api/login/qrcode/{token}/scan_info", headers=poll_headers)
                    info = resp.json()

                    # 检查 code 40352 人机验证
                    err = info.get("error", {}) if isinstance(info.get("error"), dict) else {}
                    if err.get("code") == 40352:
                        session.status = "needs_captcha"
                        session.captcha_url = err.get("redirect", "")
                        session.message = "请先完成人机验证"
                        continue

                    if session.status == "needs_captcha":
                        session.status = "waiting_scan"

                    api_status = info.get("status")
                    if api_status == 1:
                        session.message = "已扫码，等待确认..."
                    
                    is_success = False
                    if info.get("access_token") or info.get("user_id"):
                        is_success = True
                    else:
                        status_str = (info.get("login_status") or "").upper()
                        if status_str in ("CONFIRMED", "SUCCESS"): is_success = True

                    if is_success:
                        # 补偿获取 z_c0
                        await client.get(f"{BASE}/api/v4/me", headers=poll_headers)
                        cookies = {c.name: c.value for c in client.cookies.jar if c.value}
                        session.cookie_str = "; ".join(f"{k}={v}" for k, v in cookies.items())
                        session.status = "success"
                        session.message = "登录成功"
                        break

                if session.status in ("waiting_scan", "needs_captcha"):
                    session.status = "timeout"
                    session.message = "扫码超时"

            except Exception as e:
                logger.error(f"Zhihu QR flow error: {e}")
                session.status = "failed"
                session.message = str(e)
            finally:
                if session.status == "success" and session.cookie_str:
                    await self._persist_cookie(session)

    # ------------------------------------------------------------------
    # HTTP 状态检查
    # ------------------------------------------------------------------

    async def _check_xiaohongshu_status(self, cookie_str: str) -> bool:
        ua = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/145.0.0.0 Safari/537.36"
        check_uri = "/api/sns/web/v1/user/me"

        # 解析 cookie 字符串为字典，供签名使用
        cookies: dict = {}
        for item in cookie_str.split(";"):
            item = item.strip()
            if "=" in item:
                k, v = item.split("=", 1)
                cookies[k.strip()] = v.strip()

        # 构造签名头（与 Adapter 保持一致的 CryptoConfig）
        try:
            config = build_xhs_crypto_config(ua)
            xhs = Xhshow(config)
            sm = SessionManager(config)
            sign = xhs.sign_headers_get(check_uri, cookies, session=sm)
        except Exception as e:
            # 签名失败（如 cookie 中缺少 a1），直接视为无效
            logger.warning(f"[xiaohongshu] 检测签名失败（cookie 可能缺少 a1）: {e}")
            return False

        headers = {
            "user-agent": ua,
            "cookie": cookie_str,
            "accept": "application/json, text/plain, */*",
            "origin": "https://www.xiaohongshu.com",
            "referer": "https://www.xiaohongshu.com/",
            "sec-ch-ua": '"Not:A-Brand";v="99", "Google Chrome";v="145", "Chromium";v="145"',
            "sec-ch-ua-mobile": "?0",
            "sec-ch-ua-platform": '"macOS"',
            "sec-fetch-dest": "empty",
            "sec-fetch-mode": "cors",
            "sec-fetch-site": "same-site",
            **sign,
        }

        try:
            async with httpx.AsyncClient(timeout=10) as client:
                resp = await client.get(
                    self.platforms["xiaohongshu"]["check_url"],
                    headers=headers,
                )
                data = resp.json()
                # 兼容 success=True 和 success=1 两种形式
                if data.get("success"):
                    return True
                # 记录具体失败原因便于排查
                logger.info(f"[xiaohongshu] Cookie 失效，接口响应: code={data.get('code')} msg={data.get('msg')}")
                return False
        except Exception as e:
            # 网络异常与 cookie 失效分开记录
            logger.warning(f"[xiaohongshu] 登录状态检测网络异常: {e}")
            return False

    async def _check_weibo_status(self, cookie_str: str) -> bool:
        headers = {
            "user-agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/145.0.0.0 Safari/537.36",
            "cookie": cookie_str,
        }
        try:
            async with httpx.AsyncClient(timeout=10, follow_redirects=False) as client:
                resp = await client.get(self.platforms["weibo"]["check_url"], headers=headers)
                # 200 OK 且没有重定向到登录页则认为有效
                return resp.status_code == 200
        except Exception:
            return False

    async def _check_zhihu_status(self, cookie_str: str) -> bool:
        headers = {
            "user-agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/145.0.0.0 Safari/537.36",
            "cookie": cookie_str,
            "accept": "application/json, text/plain, */*",
        }
        try:
            async with httpx.AsyncClient(timeout=10) as client:
                resp = await client.get(self.platforms["zhihu"]["check_url"], headers=headers)
                data = resp.json()
                return "id" in data or "name" in data
        except Exception:
            return False

    async def refresh_zhihu_zse_cookie(self, target_url: str = "https://www.zhihu.com/people/liu-kan-shan-78") -> bool:
        """
        触发无头浏览器访问知乎具体页面，提取并更新 __zse_ck。
        与原有的配置中的 zhihu_cookie 合并后保存。
        """
        cookie_str = await get_setting_value("zhihu_cookie")
        if not cookie_str:
            logger.warning("未配置 zhihu_cookie，无法刷新 __zse_ck")
            return False

        logger.info(f"正在后台启动 WebKit 更新知乎指纹，目标 URL: {target_url}")
        
        # 将原 cookie str 转为 playwright 兼容的列表
        cookies_list = []
        for item in cookie_str.split(";"):
            item = item.strip()
            if "=" in item:
                k, v = item.split("=", 1)
                cookies_list.append({"name": k.strip(), "value": v.strip(), "domain": ".zhihu.com", "path": "/"})

        try:
            browser = await browser_manager.get_browser()
            context = await browser.new_context(
                user_agent="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/145.0.0.0 Safari/537.36",
                viewport={"width": 1280, "height": 720}
            )
            # 注入旧 Cookie 保持登录态
            await context.add_cookies(cookies_list)
            
            page = await context.new_page()
            await page.goto(target_url, wait_until="networkidle", timeout=30000)
            await asyncio.sleep(5)  # 等待反爬引擎计算下发指纹

            new_cookies = await context.cookies()
            zse_ck = None
            for c in new_cookies:
                if c["name"] == "__zse_ck":
                    zse_ck = c["value"]
            
            if not zse_ck:
                logger.warning("未能提取到新的 __zse_ck")
                return False
                
            logger.info(f"成功提取到新的 __zse_ck: {zse_ck[:30]}...")

            # 合并 Cookie
            cookie_dict = {}
            for item in cookie_str.split(";"):
                item = item.strip()
                if "=" in item:
                    k, v = item.split("=", 1)
                    cookie_dict[k.strip()] = v.strip()
            
            cookie_dict["__zse_ck"] = zse_ck
            
            # 从 playwright 拿回的主域 cookie（可能顺带刷新了 d_c0 等）也可顺便更新
            for c in new_cookies:
                if c["name"] in ["__zse_ck", "d_c0", "_zap", "_xsrf", "z_c0"]:
                    cookie_dict[c["name"]] = c["value"]

            new_cookie_str = "; ".join(f"{k}={v}" for k, v in cookie_dict.items())
            
            await set_setting_value(
                key="zhihu_cookie",
                value=new_cookie_str,
                category="platform"
            )
            logger.info("已成功合并并保存新的知乎 Cookie")
            return True
            
        except Exception as e:
            logger.error(f"提取知乎指纹失败: {e}")
            return False
        finally:
            if 'context' in locals():
                await context.close()


browser_auth_service = BrowserAuthService()
