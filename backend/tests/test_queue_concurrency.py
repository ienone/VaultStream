import asyncio
from sqlalchemy import select, delete
from app.core.db_adapter import AsyncSessionLocal
from app.core.queue_adapter import TaskQueue
from app.models import Task, TaskStatus


async def test_settlement_uses_claimed_task_row_identity(db_session):
    """Two rows for one content must be settled independently and idempotently."""
    session_factory = AsyncSessionLocal
    await db_session.execute(delete(Task))
    await db_session.commit()

    async with session_factory() as session:
        session.add_all(
            [
                Task(
                    task_type="parse_content",
                    payload={"content_id": 42, "task_id": "first"},
                    status=TaskStatus.PENDING,
                ),
                Task(
                    task_type="parse_content",
                    payload={"content_id": 42, "task_id": "second"},
                    status=TaskStatus.PENDING,
                ),
            ]
        )
        await session.commit()

    queue = TaskQueue()
    await queue.connect()
    first = await queue.dequeue(timeout=12)
    second = await queue.dequeue(timeout=12)
    assert first is not None and second is not None
    assert first.db_id != second.db_id

    first.payload["content_id"] = 999
    assert await queue.mark_complete(first.db_id) is True
    assert await queue.mark_complete(first.db_id) is False
    assert await queue.is_processing(42) is True

    async with session_factory() as session:
        rows = {
            row.id: row
            for row in (await session.execute(select(Task))).scalars().all()
        }
    assert rows[first.db_id].status == TaskStatus.COMPLETED
    assert rows[second.db_id].status == TaskStatus.RUNNING

    assert await queue.mark_failed(second.db_id, reason="non_retryable: broken") is True
    assert await queue.mark_failed(second.db_id, reason="changed") is False

    async with session_factory() as session:
        rows = {
            row.id: row
            for row in (await session.execute(select(Task))).scalars().all()
        }
    assert rows[first.db_id].status == TaskStatus.COMPLETED
    assert rows[second.db_id].status == TaskStatus.FAILED
    assert rows[second.db_id].last_error == "non_retryable: broken"


async def test_concurrent_claims_and_recreated_queue_do_not_repeat_tasks(db_session):
    await db_session.execute(delete(Task))
    await db_session.commit()
    queue = TaskQueue()
    await queue.connect()
    for index in range(12):
        assert await queue.enqueue({'content_id': index, 'task_id': f'claim-{index}'})

    async def consume(worker_queue):
        await worker_queue.connect()
        item = await worker_queue.dequeue(timeout=12)
        assert item is not None
        assert await worker_queue.mark_complete(item.db_id)
        return item.db_id

    # Race actual SQLite claim/settlement operations, then use fresh queue
    # instances for the remaining persisted tasks (not a process-crash test).
    first = await asyncio.gather(*(consume(queue) for _ in range(4)))
    remaining = await asyncio.gather(*(consume(TaskQueue()) for _ in range(8)))
    assert len(set(first + remaining)) == 12
    async with AsyncSessionLocal() as observer:
        rows = (await observer.execute(select(Task))).scalars().all()
        assert len(rows) == 12
        assert all(row.status == TaskStatus.COMPLETED for row in rows)
