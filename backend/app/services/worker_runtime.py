"""Supervise long-lived loops without replaying individual business operations."""
import asyncio
from collections.abc import Callable, Coroutine
from typing import Any

from app.core.logging import logger


_workers: dict[str, asyncio.Task] = {}
_recovering: set[str] = set()


def start_worker(name: str, factory: Callable[[], Coroutine[Any, Any, None]]) -> asyncio.Task:
    existing = _workers.get(name)
    if existing is not None and not existing.done():
        raise RuntimeError(f"Worker already started: {name}")

    async def supervise() -> None:
        try:
            while True:
                try:
                    _recovering.discard(name)
                    await factory()
                    raise RuntimeError(f"Worker loop exited: {name}")
                except asyncio.CancelledError:
                    raise
                except Exception:
                    if asyncio.current_task().cancelling():
                        raise asyncio.CancelledError
                    _recovering.add(name)
                    logger.exception("后台循环 {} 已中断，5 秒后恢复", name)
                    await asyncio.sleep(5)
        finally:
            _recovering.discard(name)

    task = asyncio.create_task(supervise(), name=name)
    _workers[name] = task
    return task


def worker_states() -> dict[str, str]:
    return {
        name: "stopped" if task.done() else "recovering" if name in _recovering else "running"
        for name, task in _workers.items()
    }


def parse_workers_available() -> bool:
    return any(name.startswith("parse-worker-") and state == "running"
               for name, state in worker_states().items())
