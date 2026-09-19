import asyncio
from sqlalchemy import select, delete
from app.core.db_adapter import AsyncSessionLocal
from app.core.queue_adapter import TaskQueue
from app.models import Task, TaskStatus


async def test_settlement_uses_claimed_task_row_identity(db_session):
    """Two rows for one content must be settled independently and idempotently."""
    await db_session.execute(delete(Task))
    db_session.add_all([
        Task(task_type="parse_content", payload={"content_id": 42, "task_id": name}, status=TaskStatus.PENDING)
        for name in ("first", "second")
    ])
    await db_session.commit()
    queue = TaskQueue()
    first = await queue.dequeue(timeout=12)
    second = await queue.dequeue(timeout=12)
    assert first is not None and second is not None
    assert first.id != second.id

    first.payload["content_id"] = 999
    assert await queue.mark_complete(first) is True
    assert await queue.mark_complete(first) is False
    async with AsyncSessionLocal() as session:
        assert (await session.get(Task, first.id)).status == TaskStatus.COMPLETED
        assert (await session.get(Task, second.id)).status == TaskStatus.RUNNING

    assert await queue.mark_failed(second, reason="broken") is True
    assert await queue.mark_failed(second, reason="changed") is False
    async with AsyncSessionLocal() as session:
        assert (await session.get(Task, first.id)).status == TaskStatus.COMPLETED
        failed = await session.get(Task, second.id)
        assert failed.status == TaskStatus.FAILED
        assert failed.last_error == "broken"


async def test_concurrent_claims_and_recreated_queue_do_not_repeat_tasks(db_session):
    await db_session.execute(delete(Task))
    await db_session.commit()
    queue = TaskQueue()
    for index in range(12):
        assert await queue.enqueue({'content_id': index, 'task_id': f'claim-{index}'})

    async def consume(worker_queue):
        item = await worker_queue.dequeue(timeout=12)
        assert item is not None
        assert await worker_queue.mark_complete(item)
        return item.id

    first = await asyncio.gather(*(consume(queue) for _ in range(4)))
    remaining = await asyncio.gather(*(consume(TaskQueue()) for _ in range(8)))
    assert len(set(first + remaining)) == 12
    async with AsyncSessionLocal() as observer:
        rows = (await observer.execute(select(Task))).scalars().all()
        assert len(rows) == 12
        assert all(row.status == TaskStatus.COMPLETED for row in rows)
