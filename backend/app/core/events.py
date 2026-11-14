import asyncio
import json
import uuid
from collections.abc import AsyncIterator
from typing import Any

from sqlalchemy import text

from app.core.config import settings
from app.core.db_adapter import AsyncSessionLocal
from app.core.logging import logger


class EventBus:
    """每个订阅者按数据库游标读取；进程内只广播唤醒信号。"""

    def __init__(self) -> None:
        self._subscribers: set[asyncio.Event] = set()
        self._instance_id = f"instance-{uuid.uuid4().hex[:12]}"
        self._poll_task: asyncio.Task | None = None
        self._running = False
        self._last_seen_event_id = 0

    def get_diagnostics(self) -> dict[str, Any]:
        return {
            "active_subscribers": len(self._subscribers),
            "max_subscribers": settings.max_sse_subscribers,
            "instance_id": self._instance_id,
            "running": self._running,
            "outbox_polling_enabled": settings.enable_event_outbox_polling,
            "last_seen_event_id": self._last_seen_event_id,
        }

    async def start(self) -> None:
        if not self._running:
            self._running = True
            if settings.enable_event_outbox_polling:
                self._poll_task = asyncio.create_task(self._poll(), name="event-bus-poller")

    async def stop(self) -> None:
        self._running = False
        if self._poll_task:
            self._poll_task.cancel()
            try:
                await self._poll_task
            except asyncio.CancelledError:
                pass
            self._poll_task = None

    async def _latest_id(self) -> int:
        async with AsyncSessionLocal() as db:
            return int(await db.scalar(text("SELECT COALESCE(MAX(id), 0) FROM realtime_events")))

    def _wake(self, event_id: int) -> None:
        self._last_seen_event_id = max(self._last_seen_event_id, event_id)
        for wake in self._subscribers:
            wake.set()

    async def publish(self, event: str, data: dict) -> None:
        async with AsyncSessionLocal() as db:
            result = await db.execute(text("""
                INSERT INTO realtime_events (event_type, payload, source_instance)
                VALUES (:event, :payload, :instance)
            """), {"event": event, "payload": json.dumps(data, ensure_ascii=False), "instance": self._instance_id})
            event_id = result.lastrowid
            if event_id % 512 == 0:
                await db.execute(text("DELETE FROM realtime_events WHERE created_at < datetime('now', '-7 days') AND id < :id"), {"id": event_id})
            await db.commit()
        self._wake(event_id)

    async def subscribe(self, after: int | None) -> AsyncIterator[dict]:
        if len(self._subscribers) >= settings.max_sse_subscribers:
            yield {"event": "error", "data": {"message": "Too many connections"}}
            return
        wake = asyncio.Event()
        self._subscribers.add(wake)
        try:
            latest = await self._latest_id()
            cursor = latest if after is None or after > latest else after
            yield {"id": cursor, "event": "connected", "data": {}}
            while True:
                wake.clear()
                while True:
                    async with AsyncSessionLocal() as db:
                        rows = (await db.execute(text("""
                            SELECT id, event_type, payload FROM realtime_events
                            WHERE id > :after ORDER BY id LIMIT 200
                        """), {"after": cursor})).all()
                    for event_id, name, payload in rows:
                        cursor = event_id
                        yield {"id": event_id, "event": name, "data": json.loads(payload)}
                    if len(rows) < 200:
                        break
                try:
                    await asyncio.wait_for(wake.wait(), timeout=30)
                except asyncio.TimeoutError:
                    yield {"event": "ping", "data": {}}
        finally:
            self._subscribers.discard(wake)

    async def _poll(self) -> None:
        while self._running:
            await asyncio.sleep(0.5)
            if self._subscribers:
                try:
                    latest = await self._latest_id()
                    if latest > self._last_seen_event_id:
                        self._wake(latest)
                except Exception:
                    logger.exception("读取跨进程事件失败")


event_bus = EventBus()
