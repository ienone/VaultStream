
import asyncio
import json
import time
import uuid
from typing import Any, AsyncGenerator, List

from sqlalchemy import text

from app.core.db_adapter import AsyncSessionLocal
from app.core.logging import logger

class EventBus:
    """支持跨实例传播的事件总线（本地内存广播 + SQLite outbox）。"""
    _subscribers: List[asyncio.Queue] = []
    _lock = asyncio.Lock()

    _instance_id = f"instance-{uuid.uuid4().hex[:12]}"
    _running = False
    _poll_task: asyncio.Task | None = None
    _last_seen_event_id: int = 0

    _POLL_INTERVAL_SECONDS = 0.5
    _POLL_BATCH_SIZE = 200
    _MAX_LOCAL_QUEUE_SIZE = 100

    @classmethod
    async def start(cls) -> None:
        """启动跨实例事件桥接轮询。"""
        if cls._running:
            return

        await cls._ensure_event_table()
        await cls._init_last_seen_event_id()

        cls._running = True

        from app.core.config import settings
        if settings.enable_event_outbox_polling:
            cls._poll_task = asyncio.create_task(cls._poll_remote_events(), name="event-bus-poller")
            logger.info(f"EventBus started ({cls._instance_id}) with outbox polling")
        else:
            logger.info(f"EventBus started ({cls._instance_id}) without outbox polling (single-instance mode)")

    @classmethod
    async def stop(cls) -> None:
        """停止事件桥接轮询。"""
        cls._running = False
        if cls._poll_task:
            cls._poll_task.cancel()
            try:
                await cls._poll_task
            except asyncio.CancelledError:
                pass
            finally:
                cls._poll_task = None
        logger.info(f"EventBus stopped ({cls._instance_id})")

    @classmethod
    async def subscribe(cls) -> AsyncGenerator[Any, None]:
        """订阅事件流"""
        from app.core.config import settings

        queue: asyncio.Queue = asyncio.Queue(maxsize=cls._MAX_LOCAL_QUEUE_SIZE)
        
        async with cls._lock:
            if len(cls._subscribers) >= settings.max_sse_subscribers:
                logger.warning(
                    f"SSE subscriber rejected: limit reached ({settings.max_sse_subscribers})"
                )
                yield {"event": "error", "data": {"message": "Too many connections"}}
                return
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
        """发布事件：本地广播 + 写入 outbox 供其他实例同步。"""
        event_id = await cls._persist_outbox_event(event=event, data=data)

        message = {"event": event, "data": data}
        if event_id is not None:
            message["id"] = event_id

        await cls._broadcast_local(message)

    _BROADCAST_SLOW_THRESHOLD_MS = 50  # 广播超过此阈值时记录 warning

    @classmethod
    async def _broadcast_local(cls, message: dict) -> None:
        """向当前进程内订阅者广播。"""
        
        # 获取当前订阅者列表的副本，避免迭代时修改
        async with cls._lock:
            subscribers = list(cls._subscribers)
        
        if not subscribers:
            logger.debug(f"No subscribers for event '{message.get('event')}', skipping")
            return
        
        t0 = time.monotonic()

        # 广播给所有订阅者，失败的跳过
        failed_queues = []
        for queue in subscribers:
            try:
                queue.put_nowait(message)
            except asyncio.QueueFull:
                logger.warning(f"Subscriber queue full, dropping event '{message.get('event')}'")
                failed_queues.append(queue)
            except Exception as e:
                logger.error(f"Failed to publish event '{message.get('event')}': {e}")
                failed_queues.append(queue)
        
        # 清理失败的订阅者
        if failed_queues:
            async with cls._lock:
                for queue in failed_queues:
                    if queue in cls._subscribers:
                        cls._subscribers.remove(queue)
            logger.info(f"Removed {len(failed_queues)} failed/slow subscribers")

        elapsed_ms = (time.monotonic() - t0) * 1000
        if elapsed_ms > cls._BROADCAST_SLOW_THRESHOLD_MS:
            logger.warning(
                f"Slow broadcast: event='{message.get('event')}', "
                f"subscribers={len(subscribers)}, elapsed={elapsed_ms:.1f}ms"
            )
        else:
            logger.debug(
                f"Published event '{message.get('event')}' to "
                f"{len(subscribers) - len(failed_queues)} subscribers ({elapsed_ms:.1f}ms)"
            )

    @classmethod
    async def _ensure_event_table(cls) -> None:
        async with AsyncSessionLocal() as session:
            await session.execute(text("""
                CREATE TABLE IF NOT EXISTS realtime_events (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    event_type VARCHAR(100) NOT NULL,
                    payload TEXT NOT NULL,
                    source_instance VARCHAR(64) NOT NULL,
                    created_at DATETIME DEFAULT CURRENT_TIMESTAMP
                )
            """))
            await session.execute(text(
                "CREATE INDEX IF NOT EXISTS ix_realtime_events_created_at ON realtime_events(created_at)"
            ))
            await session.commit()

    @classmethod
    async def _init_last_seen_event_id(cls) -> None:
        async with AsyncSessionLocal() as session:
            result = await session.execute(text("SELECT COALESCE(MAX(id), 0) FROM realtime_events"))
            cls._last_seen_event_id = int(result.scalar() or 0)

    @classmethod
    async def _persist_outbox_event(cls, event: str, data: dict) -> int | None:
        """持久化事件到 outbox 表，返回事件 ID（用于 SSE Last-Event-ID）。"""
        try:
            payload = json.dumps(data, ensure_ascii=False)
            async with AsyncSessionLocal() as session:
                result = await session.execute(
                    text("""
                        INSERT INTO realtime_events (event_type, payload, source_instance)
                        VALUES (:event_type, :payload, :source_instance)
                    """),
                    {
                        "event_type": event,
                        "payload": payload,
                        "source_instance": cls._instance_id,
                    },
                )
                await session.commit()
                return result.lastrowid
        except Exception as e:
            logger.error(f"Failed to persist outbox event '{event}': {e}")
            return None

    @classmethod
    async def replay_events_since(cls, last_event_id: int) -> list[dict]:
        """从指定 event ID 之后重放事件，用于 SSE 断线续传。"""
        try:
            async with AsyncSessionLocal() as session:
                result = await session.execute(
                    text("""
                        SELECT id, event_type, payload
                        FROM realtime_events
                        WHERE id > :last_id
                        ORDER BY id ASC
                        LIMIT :limit
                    """),
                    {"last_id": last_event_id, "limit": 500},
                )
                rows = result.fetchall()

            events = []
            for row in rows:
                try:
                    data = json.loads(row[2]) if isinstance(row[2], str) else row[2]
                except Exception:
                    continue
                events.append({"id": int(row[0]), "event": row[1], "data": data})
            return events
        except Exception as e:
            logger.error(f"Failed to replay events since {last_event_id}: {e}")
            return []

    @classmethod
    async def _poll_remote_events(cls) -> None:
        while cls._running:
            try:
                async with AsyncSessionLocal() as session:
                    result = await session.execute(
                        text("""
                            SELECT id, event_type, payload, source_instance
                            FROM realtime_events
                            WHERE id > :last_id
                            ORDER BY id ASC
                            LIMIT :limit
                        """),
                        {
                            "last_id": cls._last_seen_event_id,
                            "limit": cls._POLL_BATCH_SIZE,
                        },
                    )
                    rows = result.fetchall()

                for row in rows:
                    event_id = int(row[0])
                    event_type = row[1]
                    payload = row[2]
                    source_instance = row[3]

                    cls._last_seen_event_id = max(cls._last_seen_event_id, event_id)

                    if source_instance == cls._instance_id:
                        continue

                    try:
                        data = json.loads(payload) if isinstance(payload, str) else payload
                    except Exception:
                        logger.warning(f"Invalid event payload for id={event_id}, skipping")
                        continue

                    await cls._broadcast_local({"event": event_type, "data": data, "id": event_id})

                await asyncio.sleep(cls._POLL_INTERVAL_SECONDS)
            except asyncio.CancelledError:
                raise
            except Exception as e:
                logger.error(f"EventBus poll loop error: {e}", exc_info=True)
                await asyncio.sleep(1.0)

event_bus = EventBus()
