"""
任务队列并发安全性与吞吐量压测。

验证目标：
1. 多 Worker 并发出队零重复（CAS 原子性）
2. 单机部署场景下吞吐量满足需求（目标: >100 tasks/s）
3. Worker 优雅重启后任务可持续处理（持久化能力）
"""
import asyncio
import os
import time
from collections import Counter

import pytest
from sqlalchemy import select, func, text
from sqlalchemy.ext.asyncio import (
    create_async_engine,
    AsyncSession,
    async_sessionmaker,
)

from app.models import Base, Task, TaskStatus
from app.core.queue_adapter import TaskQueue


# ── 隔离的测试数据库 ──────────────────────────────────

_TEST_DB = os.path.abspath("data/test_queue_concurrency.db")
_DB_URL = f"sqlite+aiosqlite:///{_TEST_DB}"


@pytest.fixture(scope="module")
def event_loop():
    loop = asyncio.new_event_loop()
    yield loop
    loop.close()


@pytest.fixture(scope="module", autouse=True)
async def _setup_db():
    """为本模块创建独立的测试数据库。"""
    os.makedirs(os.path.dirname(os.path.abspath(_TEST_DB)), exist_ok=True)

    _engine = create_async_engine(_DB_URL, echo=False)

    from sqlalchemy import event as sa_event

    @sa_event.listens_for(_engine.sync_engine, "connect")
    def _pragma(dbapi_conn, _):
        cur = dbapi_conn.cursor()
        cur.execute("PRAGMA journal_mode=WAL")
        cur.execute("PRAGMA synchronous=NORMAL")
        cur.close()

    async with _engine.begin() as conn:
        await conn.run_sync(Base.metadata.create_all)

    _session_factory = async_sessionmaker(
        _engine, class_=AsyncSession, expire_on_commit=False
    )

    yield _engine, _session_factory

    await _engine.dispose()
    if os.path.exists(_TEST_DB):
        os.remove(_TEST_DB)
    for suffix in ("-wal", "-shm"):
        p = _TEST_DB + suffix
        if os.path.exists(p):
            os.remove(p)


# ── Helpers ───────────────────────────────────────────

async def _seed_tasks(session_factory, count: int):
    """批量写入 PENDING 任务。"""
    async with session_factory() as session:
        for i in range(count):
            session.add(
                Task(
                    task_type="parse_content",
                    payload={"content_id": i, "task_id": f"bench-{i}"},
                    status=TaskStatus.PENDING,
                    priority=0,
                    max_retries=3,
                )
            )
        await session.commit()


async def _clear_tasks(session_factory):
    async with session_factory() as session:
        await session.execute(text("DELETE FROM tasks"))
        await session.commit()


def _status_key(status: TaskStatus | str) -> str:
    if isinstance(status, TaskStatus):
        return status.value
    return str(status)


async def _task_status_counts(session_factory) -> dict[str, int]:
    async with session_factory() as session:
        rows = (
            await session.execute(
                select(Task.status, func.count(Task.id)).group_by(Task.status)
            )
        ).all()
    return {_status_key(status): count for status, count in rows}


def _count_status(counts: dict[str, int], status: TaskStatus) -> int:
    return counts.get(status.value, 0)


def _percentile(values: list[float], p: float) -> float:
    if not values:
        return 0.0
    ordered = sorted(values)
    index = int(round((len(ordered) - 1) * p))
    index = max(0, min(len(ordered) - 1, index))
    return ordered[index]


def _make_queue(session_factory) -> TaskQueue:
    """构造一个绑定到测试数据库的 TaskQueue 实例。"""
    q = TaskQueue()
    q._session_maker = session_factory
    return q


# ── Tests ─────────────────────────────────────────────


class TestConcurrentDequeue:
    """多 Worker 并发出队：零重复、零丢失。"""

    TASK_COUNT = 200
    WORKER_COUNT = 8

    @pytest.mark.asyncio
    async def test_no_duplicate_dequeue(self, _setup_db):
        """
        启动 WORKER_COUNT 个协程同时从队列出队，
        验证：每个任务只被消费一次，总消费数 == 入队数，且状态全部落到 COMPLETED。
        """
        _engine, session_factory = _setup_db

        await _clear_tasks(session_factory)

        await _seed_tasks(session_factory, self.TASK_COUNT)

        queue = _make_queue(session_factory)
        consumed: list[int] = []
        lock = asyncio.Lock()

        async def worker():
            while True:
                result = await queue.dequeue(timeout=1)
                if result is None:
                    break
                content_id = int(result["content_id"])
                await queue.mark_complete(content_id)
                async with lock:
                    consumed.append(content_id)

        workers = [asyncio.create_task(worker()) for _ in range(self.WORKER_COUNT)]
        await asyncio.gather(*workers)

        # 断言：零重复
        counter = Counter(consumed)
        duplicates = {cid: cnt for cid, cnt in counter.items() if cnt > 1}
        assert not duplicates, f"发现重复消费: {duplicates}"

        # 断言：零丢失
        assert len(consumed) == self.TASK_COUNT, (
            f"任务丢失: 消费 {len(consumed)}/{self.TASK_COUNT}"
        )

        # 断言：状态一致性
        counts = await _task_status_counts(session_factory)
        assert _count_status(counts, TaskStatus.COMPLETED) == self.TASK_COUNT
        assert _count_status(counts, TaskStatus.PENDING) == 0
        assert _count_status(counts, TaskStatus.RUNNING) == 0


class TestEnqueueThroughput:
    """入队吞吐量基准。"""

    TASK_COUNT = 500

    @pytest.mark.asyncio
    async def test_enqueue_throughput(self, _setup_db):
        """
        连续入队 TASK_COUNT 个任务，测量吞吐量。
        目标: > 100 tasks/s（个人部署场景绰绰有余）。
        同时输出 P50/P95 单任务入队耗时，避免只看均值失真。
        """
        _engine, session_factory = _setup_db

        await _clear_tasks(session_factory)

        queue = _make_queue(session_factory)

        latencies: list[float] = []
        t0 = time.perf_counter()
        for i in range(self.TASK_COUNT):
            op_t0 = time.perf_counter()
            ok = await queue.enqueue({"content_id": i, "task_id": f"tp-{i}"})
            assert ok is True
            latencies.append(time.perf_counter() - op_t0)
        elapsed = time.perf_counter() - t0

        throughput = self.TASK_COUNT / elapsed
        p50_ms = _percentile(latencies, 0.50) * 1000
        p95_ms = _percentile(latencies, 0.95) * 1000
        print(
            f"\n入队吞吐量: {throughput:.0f} tasks/s "
            f"({self.TASK_COUNT} tasks in {elapsed:.2f}s, p50={p50_ms:.2f}ms, p95={p95_ms:.2f}ms)"
        )

        assert throughput > 100, f"吞吐量不足: {throughput:.0f} tasks/s"

        # 验证全部入库
        async with session_factory() as session:
            result = await session.execute(
                select(func.count(Task.id)).where(Task.status == TaskStatus.PENDING)
            )
            assert result.scalar() == self.TASK_COUNT


class TestDequeueThroughput:
    """出队吞吐量基准（含 CAS 竞争）。"""

    TASK_COUNT = 200
    WORKER_COUNT = 4

    @pytest.mark.asyncio
    async def test_dequeue_throughput(self, _setup_db):
        """
        WORKER_COUNT 个协程并发出队，测量总吞吐量。
        使用“最后一次成功出队时间”计算有效吞吐，避免队列耗尽后的空轮询尾巴影响结果。
        """
        _engine, session_factory = _setup_db

        await _clear_tasks(session_factory)

        await _seed_tasks(session_factory, self.TASK_COUNT)
        queue = _make_queue(session_factory)

        consumed: list[int] = []
        lock = asyncio.Lock()
        t0 = time.perf_counter()
        last_success_at = t0

        async def worker():
            nonlocal last_success_at
            while True:
                result = await queue.dequeue(timeout=1)
                if result is None:
                    break
                content_id = int(result["content_id"])
                await queue.mark_complete(content_id)
                now = time.perf_counter()
                async with lock:
                    consumed.append(content_id)
                    last_success_at = now

        workers = [asyncio.create_task(worker()) for _ in range(self.WORKER_COUNT)]
        await asyncio.gather(*workers)
        total_elapsed = time.perf_counter() - t0
        active_elapsed = max(last_success_at - t0, 1e-9)

        consumed_count = len(consumed)
        throughput_active = consumed_count / active_elapsed
        throughput_total = consumed_count / total_elapsed if total_elapsed > 0 else 0
        print(
            f"\n出队吞吐量(有效): {throughput_active:.0f} tasks/s "
            f"({consumed_count} tasks, {self.WORKER_COUNT} workers, active={active_elapsed:.2f}s, total={total_elapsed:.2f}s, total_throughput={throughput_total:.0f})"
        )

        assert consumed_count == self.TASK_COUNT

        counter = Counter(consumed)
        duplicates = {cid: cnt for cid, cnt in counter.items() if cnt > 1}
        assert not duplicates, f"发现重复消费: {duplicates}"

        assert throughput_active > 80, f"出队吞吐量不足: {throughput_active:.0f} tasks/s"

        counts = await _task_status_counts(session_factory)
        assert _count_status(counts, TaskStatus.COMPLETED) == self.TASK_COUNT
        assert _count_status(counts, TaskStatus.PENDING) == 0
        assert _count_status(counts, TaskStatus.RUNNING) == 0


class TestGracefulRestartReliability:
    """单机场景下 Worker 优雅重启可靠性。"""

    TASK_COUNT = 300
    PHASE1_TARGET = 120
    WORKER_COUNT = 4

    @pytest.mark.asyncio
    async def test_graceful_restart_can_finish_all_tasks(self, _setup_db):
        """
        阶段1先消费部分任务并优雅停止，阶段2使用新 Queue 实例继续消费。
        验证：任务不会丢失，最终全部 COMPLETED。
        """
        _engine, session_factory = _setup_db

        await _clear_tasks(session_factory)
        await _seed_tasks(session_factory, self.TASK_COUNT)

        queue_phase1 = _make_queue(session_factory)
        consumed_phase1: list[int] = []
        lock = asyncio.Lock()
        stop_event = asyncio.Event()

        async def phase1_worker():
            while True:
                if stop_event.is_set():
                    break

                result = await queue_phase1.dequeue(timeout=1)
                if result is None:
                    break

                content_id = int(result["content_id"])
                await queue_phase1.mark_complete(content_id)

                async with lock:
                    consumed_phase1.append(content_id)
                    if len(consumed_phase1) >= self.PHASE1_TARGET:
                        stop_event.set()

        phase1_workers = [
            asyncio.create_task(phase1_worker()) for _ in range(self.WORKER_COUNT)
        ]
        await asyncio.gather(*phase1_workers)

        assert len(consumed_phase1) >= self.PHASE1_TARGET

        counts_after_phase1 = await _task_status_counts(session_factory)
        completed_phase1 = _count_status(counts_after_phase1, TaskStatus.COMPLETED)
        pending_phase1 = _count_status(counts_after_phase1, TaskStatus.PENDING)
        running_phase1 = _count_status(counts_after_phase1, TaskStatus.RUNNING)

        assert completed_phase1 == len(consumed_phase1)
        assert pending_phase1 > 0
        assert running_phase1 == 0

        # 模拟重启：重新构造 queue 实例继续消费剩余任务
        queue_phase2 = _make_queue(session_factory)
        consumed_phase2: list[int] = []

        async def phase2_worker():
            while True:
                result = await queue_phase2.dequeue(timeout=1)
                if result is None:
                    break

                content_id = int(result["content_id"])
                await queue_phase2.mark_complete(content_id)
                async with lock:
                    consumed_phase2.append(content_id)

        phase2_workers = [
            asyncio.create_task(phase2_worker()) for _ in range(self.WORKER_COUNT)
        ]
        await asyncio.gather(*phase2_workers)

        all_consumed = consumed_phase1 + consumed_phase2
        counter = Counter(all_consumed)
        duplicates = {cid: cnt for cid, cnt in counter.items() if cnt > 1}

        assert not duplicates, f"重启前后出现重复消费: {duplicates}"
        assert len(all_consumed) == self.TASK_COUNT

        final_counts = await _task_status_counts(session_factory)
        assert _count_status(final_counts, TaskStatus.COMPLETED) == self.TASK_COUNT
        assert _count_status(final_counts, TaskStatus.PENDING) == 0
        assert _count_status(final_counts, TaskStatus.RUNNING) == 0
