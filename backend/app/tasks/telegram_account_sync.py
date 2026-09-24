"""Single-leader Telegram account synchronization; login is always explicit."""
import asyncio
from pathlib import Path
from app.services.telegram_account_client import create_account_client
from app.services.telegram_account_login import TelegramAccountLogin

from app.core.config import settings
from app.services.config_service import ConfigService, coerce_bool
from app.services.automation_policy import AutomationPolicyService
from app.services.telegram_account_sync import TelegramAccountSync
from app.services.background_task_state import record_task_run_started, record_task_run_success, record_task_run_error


class TelegramAccountSyncTask:
    def __init__(self):
        self._scheduler = None
        self._running = None
        self.config = ConfigService()
        self._start_lock = asyncio.Lock()
        self.login = TelegramAccountLogin()

    @property
    def running(self):
        return self._running is not None and not self._running.done()

    def start(self):
        self._scheduler = asyncio.create_task(self._loop())

    async def stop(self):
        tasks = [task for task in (self._scheduler, self._running) if task and not task.done()]
        for task in tasks:
            task.cancel()
        await asyncio.gather(*tasks, return_exceptions=True)
        await self.login.cancel()

    async def options(self):
        return {
            "channels_enabled": coerce_bool(await self.config.get_value_fresh("enable_telegram_channel_sync", False)),
            "saved_enabled": coerce_bool(await self.config.get_value_fresh("enable_telegram_saved_sync", False)),
        }

    async def configure(self, *, channels_enabled, saved_enabled):
        async with self._start_lock:
            previous = await self.options()
            await self.config.set_value("enable_telegram_channel_sync", channels_enabled, category="telegram")
            await self.config.set_value("enable_telegram_saved_sync", saved_enabled, category="telegram")
            disabling = (previous["channels_enabled"] and not channels_enabled) or (previous["saved_enabled"] and not saved_enabled)
            if disabling and self.running:
                self._running.cancel()
                await asyncio.gather(self._running, return_exceptions=True)

    async def preview(self, source):
        from app.adapters.telegram_account import TelegramAccountReader
        from telethon import utils
        async with self._start_lock:
            if self.running or self.login.active:
                raise ValueError("Telegram 同步或登录正在进行")
            client = create_account_client()
            try:
                async with asyncio.timeout(30):
                    await client.connect()
                    me = await client.get_me()
                    if me is None or me.bot or me.id != source.config["account_id"]:
                        raise ValueError("请连接该来源所属的 Telegram 账号")
                    posts, cursor = await TelegramAccountReader(client).read_page(source.config["peer_id"], after=None, limit=20)
                    peer_id, _ = utils.resolve_id(source.config["peer_id"])
                    prefix = source.config.get("username") or f"c/{peer_id}"
                    samples = [{"url": f"https://t.me/{prefix}/{post.address.message_id}",
                                "title": post.body[:160] or None, "author": source.name,
                                "published_at": post.messages[0].date.isoformat(), "tag_count": 0,
                                "media_count": sum(bool(m.photo or m.document) for m in post.messages)}
                               for post in posts]
                    return samples, cursor
            finally:
                await client.disconnect()

    async def start_login(self):
        async with self._start_lock:
            if self.running:
                raise ValueError("请等待当前同步完成后再登录")
            return self.login.start()

    async def trigger(self, *, scheduled=False, source_id=None):
        async with self._start_lock:
            return await self._trigger(scheduled=scheduled, source_id=source_id)

    async def _trigger(self, *, scheduled, source_id):
        if self.running or self.login.active:
            raise ValueError("Telegram 同步或登录正在进行")
        options = await self.options()
        if source_id is not None:
            options["saved_enabled"] = False
        if scheduled and not (await AutomationPolicyService().favorites_scheduler()).allowed:
            options["saved_enabled"] = False
        if not any(options.values()):
            raise ValueError("请先开启频道或收藏同步")
        if not settings.telegram_api_id or not settings.telegram_api_hash.get_secret_value():
            raise ValueError("请先配置 Telegram 应用凭据")
        if not Path(settings.telegram_session_path).is_file():
            raise ValueError("请先登录 Telegram 用户账号")
        run = await record_task_run_started("telegram_account_sync", trigger="scheduled" if scheduled else "manual")
        self._running = asyncio.create_task(self._execute(run["run_id"], options, source_id))
        return run["run_id"]

    async def _execute(self, run_id, options, source_id):
        client = None
        try:
            client = create_account_client()
            await client.connect()
            if not await client.is_user_authorized():
                raise ValueError("Telegram 登录已失效")
            result = await TelegramAccountSync(client).sync(channels=options["channels_enabled"], saved=options["saved_enabled"], source_id=source_id)
            await record_task_run_success("telegram_account_sync", run_id, **result)
        except asyncio.CancelledError:
            await record_task_run_error("telegram_account_sync", run_id, "同步已中止")
            raise
        except Exception as error:
            await record_task_run_error("telegram_account_sync", run_id, f"Telegram 同步失败：{type(error).__name__}")
        finally:
            if client is not None:
                await client.disconnect()

    async def _loop(self):
        while True:
            if not self.running:
                try:
                    await self.trigger(scheduled=True)
                except ValueError:
                    pass  # Disabled/unconfigured accounts should not generate heartbeat errors.
                except Exception as error:
                    await record_task_run_error("telegram_account_sync", None, f"同步调度失败：{type(error).__name__}")
            await asyncio.sleep(300)
