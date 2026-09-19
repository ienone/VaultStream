import asyncio
from datetime import timedelta
from sqlalchemy import select, delete
from app.core.db_adapter import AsyncSessionLocal
from app.core.queue_adapter import TaskQueue
from app.core.time_utils import utcnow
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
    assert await queue.mark_complete(first) is True
    assert await queue.mark_complete(first) is False
    assert await queue.is_processing(42) is True

    async with session_factory() as session:
        rows = {
            row.id: row
            for row in (await session.execute(select(Task))).scalars().all()
        }
    assert rows[first.db_id].status == TaskStatus.COMPLETED
    assert rows[second.db_id].status == TaskStatus.RUNNING

    assert await queue.mark_failed(second, reason="non_retryable: broken") is True
    assert await queue.mark_failed(second, reason="changed") is False

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
        assert await worker_queue.mark_complete(item)
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


async def test_active_claim_is_not_stolen_and_expired_retry_limit_fails(db_session):
    await db_session.execute(delete(Task))
    active = Task(
        task_type="parse_content", payload={"content_id": 1},
        status=TaskStatus.RUNNING, retry_count=1, max_retries=3,
        started_at=utcnow(),
    )
    exhausted = Task(
        task_type="parse_content", payload={"content_id": 2},
        status=TaskStatus.RUNNING, retry_count=3, max_retries=3,
        started_at=utcnow() - TaskQueue.LEASE_DURATION - timedelta(seconds=1),
    )
    db_session.add_all([active, exhausted])
    await db_session.commit()

    queue = TaskQueue()
    await queue.connect()
    assert await queue.dequeue(timeout=1) is None
    async with AsyncSessionLocal() as observer:
        assert (await observer.get(Task, active.id)).status == TaskStatus.RUNNING
        failed = await observer.get(Task, exhausted.id)
        assert failed.status == TaskStatus.FAILED
        assert failed.retry_count == 3


async def test_exhausted_task_and_content_failure_roll_back_together(db_session, monkeypatch):
    from app.models import Content, ContentStatus, Platform

    await db_session.execute(delete(Task))
    content = Content(
        url='https://example.test/exhausted', platform=Platform.UNIVERSAL,
        status=ContentStatus.PROCESSING,
    )
    db_session.add(content)
    await db_session.flush()
    task = Task(
        task_type='parse_content', payload={'content_id': content.id},
        status=TaskStatus.RUNNING, retry_count=3, max_retries=3,
        started_at=utcnow() - TaskQueue.LEASE_DURATION - timedelta(seconds=1),
    )
    db_session.add(task)
    await db_session.commit()
    task_id, content_id = task.id, content.id

    queue = TaskQueue()
    await queue.connect()
    original = queue._release_exhausted_content

    async def fail_after_content_update(session, queued_task_id, queued_content_id):
        await original(session, queued_task_id, queued_content_id)
        raise RuntimeError('crash before shared commit')

    monkeypatch.setattr(queue, '_release_exhausted_content', fail_after_content_update)
    assert await queue.dequeue(timeout=1) is None
    async with AsyncSessionLocal() as observer:
        saved_task = await observer.get(Task, task_id)
        saved_content = await observer.get(Content, content_id)
        assert saved_task.status == TaskStatus.RUNNING
        assert saved_content.status == ContentStatus.PROCESSING


async def test_claim_snapshot_cannot_adopt_a_replacement_after_commit(db_session, monkeypatch):
    from contextlib import asynccontextmanager
    from sqlalchemy import update

    await db_session.execute(delete(Task))
    task = Task(task_type='parse_content', payload={'content_id': 42}, status=TaskStatus.PENDING)
    db_session.add(task)
    await db_session.commit()
    task_id = task.id
    committed, resume = asyncio.Event(), asyncio.Event()

    @asynccontextmanager
    async def paused_session():
        async with AsyncSessionLocal() as session:
            commit = session.commit

            async def commit_then_pause():
                await commit()
                committed.set()
                await resume.wait()

            monkeypatch.setattr(session, 'commit', commit_then_pause)
            yield session

    old_queue, fresh_queue = TaskQueue(), TaskQueue()
    await old_queue.connect()
    await fresh_queue.connect()
    monkeypatch.setattr(old_queue, '_session_maker', paused_session)
    delayed_claim = asyncio.create_task(old_queue.dequeue(timeout=1))
    try:
        await asyncio.wait_for(committed.wait(), 5)
        async with AsyncSessionLocal() as expire:
            await expire.execute(update(Task).where(Task.id == task_id).values(
                started_at=utcnow() - TaskQueue.LEASE_DURATION,
            ))
            await expire.commit()
        replacement = await fresh_queue.dequeue(timeout=1)
    finally:
        resume.set()
        original = await delayed_claim

    assert original.generation == 1
    assert replacement.generation == 2
    assert await fresh_queue.mark_complete(original) is False
    assert await fresh_queue.mark_complete(replacement) is True
