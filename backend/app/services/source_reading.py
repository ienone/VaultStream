"""Shared pacing and durable platform cooldowns for source readers.

The application has one API worker. Locks serialize starts in that worker;
cooldowns survive restarts in the existing settings store.
"""
from __future__ import annotations

import asyncio
import math
import time
from email.utils import parsedate_to_datetime
from typing import Literal
from urllib.parse import urlsplit

from app.services.config_service import ConfigService


class SourceCoolingDown(RuntimeError):
    def __init__(self, source: str, seconds: int):
        super().__init__(f"{source} 读取已暂停，请在 {seconds} 秒后重试")
        self.retry_after_seconds = seconds


class SourceReading:
    def __init__(self):
        self._locks: dict[tuple[str, str], asyncio.Lock] = {}
        self._last_start: dict[tuple[str, str], float] = {}
        self._cooldowns: dict[str, float] = {}

    @staticmethod
    def feed_scope(url: str) -> str:
        # Different feed hosts must not block one another. Never persist URLs
        # containing credentials or private query strings in cooldown keys.
        return f"rss:{(urlsplit(url).hostname or '').lower()}"

    def http_hooks(self, source: str) -> dict:
        """Pace each HTTP request, including redirects and fallback requests."""
        async def before_request(request):
            await self.wait(source)

        async def after_response(response):
            if response.status_code == 429:
                from app.adapters.errors import RetryableAdapterError
                await self.http_cooldown(source, response.headers.get("Retry-After"))
                raise RetryableAdapterError("读取频率受限，请等待冷却后重试", details={"status": 429})

        return {"request": [before_request], "response": [after_response]}

    async def remaining(self, source: str) -> int:
        saved = await ConfigService().get_value_fresh(f"source_read_cooldown_until_{source}", 0)
        until = max(float(saved or 0), self._cooldowns.get(source, 0))
        return max(0, math.ceil(until - time.time()))

    async def wait(self, source: str, *, lane: Literal["read", "enqueue"] = "read") -> None:
        key = (source, lane)
        async with self._locks.setdefault(key, asyncio.Lock()):
            while True:
                remaining = await self.remaining(source)
                if remaining:
                    raise SourceCoolingDown(source, remaining)
                rate = await ConfigService().get_source_read_rate(source.split(":", 1)[0], fresh=True)
                last = self._last_start.get(key)
                delay = last + 60.0 / rate - time.monotonic() if last is not None else 0
                if delay <= 0:
                    self._last_start[key] = time.monotonic()
                    return
                await asyncio.sleep(delay)
                # Recheck configuration and cooldowns after sleeping.

    async def cooldown(self, source: str, seconds: float) -> None:
        if not math.isfinite(seconds) or seconds < 0:
            raise ValueError("Cooldown must be finite and non-negative")
        config = ConfigService()
        until = time.time() + seconds
        # Publish immediately so waiters stop even while persistence is pending.
        self._cooldowns[source] = max(until, self._cooldowns.get(source, 0))
        saved = await config.get_value_fresh(f"source_read_cooldown_until_{source}", 0)
        self._cooldowns[source] = max(float(saved or 0), self._cooldowns[source])
        await config.set_value(f"source_read_cooldown_until_{source}", self._cooldowns[source], category="source_reading")

    async def http_cooldown(self, source: str, retry_after: str | None) -> None:
        seconds = 300.0
        if retry_after:
            try:
                parsed = float(retry_after)
            except ValueError:
                try:
                    parsed = parsedate_to_datetime(retry_after).timestamp() - time.time()
                except (ValueError, TypeError, OverflowError):
                    parsed = seconds
            if math.isfinite(parsed):
                seconds = max(20.0, parsed)
        await self.cooldown(source, seconds)


source_reading = SourceReading()
