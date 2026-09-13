"""Concurrent entrypoints and late policy changes must not duplicate external sends."""
import asyncio
from types import SimpleNamespace
from uuid import uuid4
from unittest.mock import AsyncMock

import pytest

from app.core.db_adapter import AsyncSessionLocal
from app.models import (Content, ContentStatus, Platform, ReviewStatus, BotConfig, BotConfigPlatform,
    BotChat, BotChatType, DistributionRule, DistributionTarget, ContentQueueItem, QueueItemStatus)
from app.tasks.distribution_worker import DistributionQueueWorker


async def prepare(db):
    name = str(uuid4())
    bot = BotConfig(platform=BotConfigPlatform.TELEGRAM, name=name)
    content = Content(platform=Platform.UNIVERSAL, url=f'https://fixture.invalid/{name}',
        canonical_url=f'https://fixture.invalid/{name}', status=ContentStatus.PARSE_SUCCESS,
        review_status=ReviewStatus.APPROVED, title='Fixture', body='Fixture body')
    rules = [DistributionRule(name=f'{name}-{n}', match_conditions={}) for n in range(2)]
    db.add_all([bot, content, *rules])
    await db.flush()
    chat = BotChat(bot_config_id=bot.id, chat_id=name, chat_type=BotChatType.CHANNEL)
    db.add(chat)
    await db.flush()
    targets = [DistributionTarget(rule_id=rule.id, bot_chat_id=chat.id) for rule in rules]
    items = [ContentQueueItem(content_id=content.id, rule_id=rule.id, bot_chat_id=chat.id,
        target_platform='telegram', target_id=chat.chat_id, status=QueueItemStatus.SCHEDULED) for rule in rules]
    db.add_all([*targets, *items])
    await db.commit()
    return items, targets


async def test_manual_and_duplicate_rule_cannot_claim_inflight_delivery(db_session, monkeypatch):
    items, _ = await prepare(db_session)
    entered, release = asyncio.Event(), asyncio.Event()
    async def send(*args):
        entered.set()
        await release.wait()
        return 'fixture-message'
    push = AsyncMock(side_effect=send)
    monkeypatch.setattr('app.tasks.distribution_worker.get_push_service', lambda _: SimpleNamespace(push=push))
    worker = DistributionQueueWorker()
    running = asyncio.create_task(worker.process_item_now(items[0].id))
    try:
        await asyncio.wait_for(entered.wait(), 5)
        with pytest.raises(ValueError):
            await worker.process_item_now(items[0].id)
        with pytest.raises(ValueError):
            await worker.process_item_now(items[1].id)
    finally:
        release.set()
        await running
    assert push.await_count == 1
    await worker.process_item_now(items[1].id)
    assert push.await_count == 1


async def test_target_disabled_during_render_prevents_send(db_session, monkeypatch):
    items, targets = await prepare(db_session)
    worker = DistributionQueueWorker()
    original = worker._distributor._build_content_payload
    async def render(*args, **kwargs):
        result = await original(*args, **kwargs)
        async with AsyncSessionLocal() as other:
            target = await other.get(DistributionTarget, targets[0].id)
            target.enabled = False
            await other.commit()
        return result
    monkeypatch.setattr(worker._distributor, '_build_content_payload', render)
    push = AsyncMock()
    monkeypatch.setattr('app.tasks.distribution_worker.get_push_service', lambda _: SimpleNamespace(push=push))
    await worker.process_item_now(items[0].id)
    push.assert_not_awaited()
    await db_session.refresh(items[0])
    assert items[0].status == QueueItemStatus.SCHEDULED
    assert items[0].last_error_type == 'rule_or_target_disabled'


@pytest.mark.parametrize("change, expected", [
    ("filter", "tags_not_any_matched"),
    ("route", "target_routing_changed"),
    ("approval", "approval_required"),
])
async def test_policy_changed_during_render_prevents_send(db_session, monkeypatch, change, expected):
    items, _ = await prepare(db_session)
    worker = DistributionQueueWorker()
    original = worker._distributor._build_content_payload
    async def render(*args, **kwargs):
        result = await original(*args, **kwargs)
        async with AsyncSessionLocal() as other:
            rule = await other.get(DistributionRule, items[0].rule_id)
            if change == "filter":
                rule.match_conditions = {"tags": ["required"]}
            elif change == "route":
                chat = await other.get(BotChat, items[0].bot_chat_id)
                chat.chat_id = "changed-destination"
            else:
                rule.approval_required = True
                content = await other.get(Content, items[0].content_id)
                content.review_status = ReviewStatus.AUTO_APPROVED
            await other.commit()
        return result
    monkeypatch.setattr(worker._distributor, "_build_content_payload", render)
    push = AsyncMock()
    monkeypatch.setattr("app.tasks.distribution_worker.get_push_service", lambda _: SimpleNamespace(push=push))
    await worker.process_item_now(items[0].id)
    push.assert_not_awaited()
    await db_session.refresh(items[0])
    assert items[0].status == QueueItemStatus.SCHEDULED
    assert items[0].last_error_type == expected


@pytest.mark.parametrize('action', ['retry', 'cancel', 'status'])
async def test_queue_api_cannot_release_active_send(db_session, action):
    from fastapi import HTTPException
    from starlette.requests import Request
    from app.routers.distribution_queue import retry_queue_item, cancel_queue_item, set_queue_item_status
    from app.schemas import QueueItemRetryRequest
    items, _ = await prepare(db_session)
    item = items[0]
    item.status = QueueItemStatus.PROCESSING
    item.locked_by = 'active-worker'
    await db_session.commit()
    request = Request({'type': 'http', 'method': 'POST', 'path': '/', 'headers': []})
    with pytest.raises(HTTPException) as error:
        if action == 'retry':
            await retry_queue_item(item.id, request, QueueItemRetryRequest(), db_session)
        elif action == 'cancel':
            await cancel_queue_item(item.id, db_session)
        else:
            await set_queue_item_status(item.id, request, {'status': 'will_push'}, db_session)
    assert error.value.status_code == 409
    await db_session.rollback()
    await db_session.refresh(item)
    assert item.status == QueueItemStatus.PROCESSING
    assert item.locked_by == 'active-worker'


@pytest.mark.parametrize('action', ['batch_retry', 'repush', 'batch_repush'])
async def test_bulk_queue_api_preserves_active_send(db_session, action):
    from fastapi import HTTPException
    from app.routers.distribution_queue import batch_retry_queue_items, repush_now_content_queue, batch_repush_now_content_queue
    from app.schemas import BatchQueueRetryRequest
    items, _ = await prepare(db_session)
    items[1].status = QueueItemStatus.PROCESSING
    items[1].locked_by = 'active-worker'
    await db_session.commit()
    with pytest.raises(HTTPException) as error:
        if action == 'batch_retry':
            await batch_retry_queue_items(BatchQueueRetryRequest(item_ids=[item.id for item in items]), db_session)
        elif action == 'repush':
            await repush_now_content_queue(items[0].content_id, None, db_session)
        else:
            await batch_repush_now_content_queue({'content_ids':[items[0].content_id]}, db_session)
    assert error.value.status_code == 409
    await db_session.rollback()
    await db_session.refresh(items[1])
    assert items[1].status == QueueItemStatus.PROCESSING
    assert items[1].locked_by == 'active-worker'


async def test_edit_cannot_overwrite_worker_claim_after_read(db_session):
    from fastapi import HTTPException
    from app.routers.distribution_queue import _lock_queue_item_for_edit
    items, _ = await prepare(db_session)
    item = items[0]
    async with AsyncSessionLocal() as worker:
        current = await worker.get(ContentQueueItem, item.id)
        current.status = QueueItemStatus.PROCESSING
        current.locked_by = 'worker-won-race'
        await worker.commit()
    with pytest.raises(HTTPException) as error:
        await _lock_queue_item_for_edit(db_session, item)
    assert error.value.status_code == 409
    await db_session.rollback()
    await db_session.refresh(item)
    assert item.locked_by == 'worker-won-race'


async def test_force_enqueue_cannot_overwrite_concurrent_claim(db_session, monkeypatch):
    from sqlalchemy.sql.dml import Update
    from app.services.distribution import DistributionService
    items, targets = await prepare(db_session)
    for target in targets:
        target.backfill_watermark = None
    item = items[0]
    item.status = QueueItemStatus.FAILED
    await db_session.commit()
    execute = db_session.execute
    raced = False
    async def race(statement, *args, **kwargs):
        nonlocal raced
        if isinstance(statement, Update) and statement.table.name == 'content_queue_items' and not raced:
            raced = True
            async with AsyncSessionLocal() as worker:
                current = await worker.get(ContentQueueItem, item.id)
                current.status = QueueItemStatus.PROCESSING
                current.locked_by = 'worker-won-enqueue-race'
                await worker.commit()
        return await execute(statement, *args, **kwargs)
    monkeypatch.setattr(db_session, 'execute', race)
    await DistributionService(db_session).enqueue_content(item.content_id, force=True)
    assert raced
    await db_session.refresh(item)
    assert item.status == QueueItemStatus.PROCESSING
    assert item.locked_by == 'worker-won-enqueue-race'
