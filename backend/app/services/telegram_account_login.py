"""One explicit, bounded QR login; no automatic code requests or retries."""
import asyncio
import base64
import io
import qrcode
from uuid import uuid4
from telethon import errors
from app.services.telegram_account_client import create_account_client


class TelegramAccountLogin:
    def __init__(self):
        self._task = None
        self._password = None
        self.snapshot = None

    @property
    def active(self):
        return self._task is not None and not self._task.done()

    def start(self):
        if self.active:
            raise ValueError("Telegram 登录正在进行")
        # Validate credentials before accepting the request, without connecting.
        from app.core.config import settings
        if not settings.telegram_api_id or not settings.telegram_api_hash.get_secret_value():
            raise ValueError("请先配置 Telegram 应用凭据")
        self.snapshot = {"login_id": uuid4().hex, "state": "waiting", "qrcode_b64": None,
                         "expires_at": None, "message": None}
        self._task = asyncio.create_task(self._run())
        return dict(self.snapshot)

    def get(self, login_id):
        if self.snapshot is None or self.snapshot["login_id"] != login_id:
            raise KeyError(login_id)
        return dict(self.snapshot)

    def password(self, login_id, password):
        self.get(login_id)
        if self._password is None or self._password.done():
            raise ValueError("当前登录不需要两步验证密码")
        self.snapshot.update(state="waiting", message=None)
        self._password.set_result(password)
        return dict(self.snapshot)

    async def cancel(self, login_id=None):
        if login_id is not None:
            self.get(login_id)
        if self.active:
            self._task.cancel()
            await asyncio.gather(self._task, return_exceptions=True)
            self.snapshot.update(state="cancelled", qrcode_b64=None, expires_at=None, message=None)

    async def _run(self):
        client = None
        try:
            async with asyncio.timeout(300):
                client = create_account_client(receive_updates=True)
                await client.connect()
                if not await client.is_user_authorized():
                    qr = await client.qr_login()
                    buffer = io.BytesIO()
                    qrcode.make(qr.url).save(buffer, format="PNG")
                    self.snapshot.update(state="qr", qrcode_b64=base64.b64encode(buffer.getvalue()).decode(), expires_at=qr.expires)
                    try:
                        await qr.wait()
                    except errors.SessionPasswordNeededError:
                        self.snapshot.update(qrcode_b64=None, expires_at=None)
                        while True:
                            self._password = asyncio.get_running_loop().create_future()
                            self.snapshot["state"] = "password_required"
                            password = await self._password
                            try:
                                await client.sign_in(password=password)
                                break
                            except errors.PasswordHashInvalidError:
                                self.snapshot["message"] = "密码不正确，请重试"
                            finally:
                                password = None
                me = await client.get_me()
                if me is None or me.bot:
                    raise ValueError("请使用 Telegram 用户账号登录")
                self.snapshot.update(state="authorized", message=None)
        except asyncio.CancelledError:
            self.snapshot.update(state="cancelled", message=None)
            raise
        except TimeoutError:
            self.snapshot.update(state="expired", message="登录已过期，请重新扫码")
        except errors.FloodWaitError:
            self.snapshot.update(state="failed", message="Telegram 暂时限制登录，请稍后再试")
        except Exception:
            self.snapshot.update(state="failed", message="登录未完成，请稍后重试")
        finally:
            self.snapshot.update(qrcode_b64=None, expires_at=None)
            self._password = None
            if client is not None:
                await client.disconnect()
