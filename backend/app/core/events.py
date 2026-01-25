
import asyncio
from typing import AsyncGenerator, List, Any
from app.core.logging import logger

class EventBus:
    """简单的内存事件总线，用于 SSE 广播"""
    _subscribers: List[asyncio.Queue] = []

    @classmethod
    async def subscribe(cls) -> AsyncGenerator[Any, None]:
        """订阅事件流"""
        queue = asyncio.Queue()
        cls._subscribers.append(queue)
        try:
            logger.debug(f"New SSE subscriber. Total: {len(cls._subscribers)}")
            while True:
                data = await queue.get()
                yield data
        finally:
            cls._subscribers.remove(queue)
            logger.debug(f"SSE subscriber disconnected. Total: {len(cls._subscribers)}")

    @classmethod
    async def publish(cls, event: str, data: dict):
        """发布事件"""
        message = {"event": event, "data": data}
        # 广播给所有订阅者
        for queue in cls._subscribers:
            await queue.put(message)

event_bus = EventBus()
