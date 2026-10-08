"""Telegram Application lifecycle owned by the API's periodic-task leader."""
from __future__ import annotations

import asyncio
from contextlib import AsyncExitStack

from telegram import Update

from app.core.time_utils import utcnow
from app.models import BotConfigPlatform
from app.schemas import BotRuntimeResponse


class TelegramBotRuntime:
    def __init__(self):
        self._lock = asyncio.Lock()
        self.api_app = None
        self.owner = False
        self.application = None
        self._cleanup = None
        self.config_id = None
        self.started_at = None
        self.info = {}
        self.last_error = None
        self.last_error_at = None

    def bind(self, api_app, *, owner: bool) -> None:
        self.api_app, self.owner = api_app, owner

    def _require_owner(self):
        if self.api_app is None or not self.owner:
            raise RuntimeError("当前 API 进程不是 Telegram 运行者；请使用单 API worker 部署")

    def _polling_error(self, error):
        self.last_error, self.last_error_at = str(error), utcnow()

    @staticmethod
    async def _stop_running(component) -> None:
        if component.running:
            await component.stop()

    async def start(self, *, reason: str, restart: bool = False) -> dict:
        async with self._lock:
            self._require_owner()
            if self.application and not restart:
                return {"status": "already_running", "reason": reason}
            await self._stop()
            from app.bot.main import VaultStreamBot
            bot = VaultStreamBot(self.api_app)
            cleanup = AsyncExitStack()
            try:
                application = await bot.create_application()
                cleanup.push_async_callback(application.post_shutdown, application)
                cleanup.push_async_callback(application.bot.shutdown)
                cleanup.push_async_callback(application.shutdown)
                await application.initialize()
                await application.post_init(application)
                cleanup.push_async_callback(self._stop_running, application)
                await application.start()
                cleanup.push_async_callback(self._stop_running, application.updater)
                await application.updater.start_polling(
                    allowed_updates=Update.ALL_TYPES, drop_pending_updates=True, bootstrap_retries=0,
                    error_callback=self._polling_error,
                )
                self.info = {
                    "bot_id": str(application.bot.id),
                    "bot_username": application.bot.username,
                    "bot_first_name": application.bot.first_name,
                }
                self.application, self._cleanup = application, cleanup
                self.config_id, self.started_at = bot.bot_config_id, utcnow()
                self.last_error = self.last_error_at = None
            except BaseException as exc:
                error = str(exc).replace(bot.bot_token, "[redacted]") if bot.bot_token else str(exc)
                self.last_error, self.last_error_at = error, utcnow()
                await cleanup.aclose()
                if isinstance(exc, Exception):
                    raise RuntimeError(error) from None
                raise
            return {"status": "restarted" if restart else "started", "reason": reason}

    async def _stop(self):
        cleanup, self._cleanup = self._cleanup, None
        self.application = None
        if cleanup is not None:
            await cleanup.aclose()

    async def stop(self, *, reason: str) -> dict:
        async with self._lock:
            self._require_owner()
            running = self.application is not None
            await self._stop()
            return {"status": "stopped" if running else "not_running", "reason": reason}

    def snapshot(self, config_id: int | None) -> BotRuntimeResponse:
        from app.bot.main import BOT_VERSION
        matches = config_id is not None and config_id == self.config_id
        running = bool(matches and self.application and self.application.running and self.application.updater.running)
        return BotRuntimeResponse(
            platform=BotConfigPlatform.TELEGRAM,
            bot_id=self.info.get("bot_id") if matches else None,
            bot_username=self.info.get("bot_username") if matches else None,
            bot_first_name=self.info.get("bot_first_name") if matches else None,
            started_at=self.started_at if matches else None,
            last_heartbeat_at=None,
            is_running=running,
            uptime_seconds=int((utcnow() - self.started_at).total_seconds()) if running else None,
            version=BOT_VERSION, last_error=self.last_error,
            last_error_at=self.last_error_at,
        )


telegram_bot_runtime = TelegramBotRuntime()
