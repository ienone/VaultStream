
import asyncio
from typing import AsyncGenerator, List, Any, Optional
from app.core.logging import logger

class EventBus:
    """简单的内存事件总线，用于 SSE 广播"""
    _subscribers: List[asyncio.Queue] = []
    _lock = asyncio.Lock()

    @classmethod
    async def subscribe(cls) -> AsyncGenerator[Any, None]:
        """订阅事件流"""
        queue: asyncio.Queue = asyncio.Queue(maxsize=100)  # 限制队列大小防止内存溢出
        
        async with cls._lock:
            cls._subscribers.append(queue)
            subscriber_count = len(cls._subscribers)
        
        logger.debug(f"New SSE subscriber. Total: {subscriber_count}")
        
        try:
            while True:
                try:
                    # 超时检查，避免死连接
                    data = await asyncio.wait_for(queue.get(), timeout=300.0)
                    yield data
                except asyncio.TimeoutError:
                    # 发送心跳包
                    yield {"event": "ping", "data": {"timestamp": asyncio.get_event_loop().time()}}
                except Exception as e:
                    logger.error(f"Error in SSE subscriber loop: {e}")
                    break
        finally:
            async with cls._lock:
                if queue in cls._subscribers:
                    cls._subscribers.remove(queue)
                subscriber_count = len(cls._subscribers)
            logger.debug(f"SSE subscriber disconnected. Total: {subscriber_count}")

    @classmethod
    async def publish(cls, event: str, data: dict):
        """发布事件到所有订阅者"""
        message = {"event": event, "data": data}
        
        # 获取当前订阅者列表的副本，避免迭代时修改
        async with cls._lock:
            subscribers = list(cls._subscribers)
        
        if not subscribers:
            logger.debug(f"No subscribers for event '{event}', skipping")
            return
        
        # 广播给所有订阅者，失败的跳过
        failed_queues = []
        for queue in subscribers:
            try:
                queue.put_nowait(message)
            except asyncio.QueueFull:
                logger.warning(f"Subscriber queue full, dropping event '{event}'")
                failed_queues.append(queue)
            except Exception as e:
                logger.error(f"Failed to publish event '{event}': {e}")
                failed_queues.append(queue)
        
        # 清理失败的订阅者
        if failed_queues:
            async with cls._lock:
                for queue in failed_queues:
                    if queue in cls._subscribers:
                        cls._subscribers.remove(queue)
            logger.info(f"Removed {len(failed_queues)} failed subscribers")
        
        logger.debug(f"Published event '{event}' to {len(subscribers) - len(failed_queues)} subscribers")

event_bus = EventBus()
