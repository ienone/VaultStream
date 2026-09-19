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
        review_status=ReviewStatus.APPROVED, title='Fixture', body='Fixture body', tags=[name])
    rules = [DistributionRule(name=f'{name}-{n}', match_conditions={'tags': [name]}) for n in range(2)]
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


async def test_expired_preparation_retries_but_unknown_send_is_quarantined(db_session):
    from datetime import timedelta
    from sqlalchemy import select
    from app.core.time_utils import utcnow
    from app.models import NotificationMessage
    from app.services.distribution.delivery_state import recover_expired_deliveries
    items, _ = await prepare(db_session)
    for item, phase in zip(items, ['delivery_preparing', None]):
        item.status = QueueItemStatus.PROCESSING
        item.locked_at = utcnow() - timedelta(days=1)
        item.locked_by = f'dead-{item.id}'
        item.last_error_type = phase
        item.attempt_count = 1
    await db_session.commit()
    assert await recover_expired_deliveries(db_session) >= 2
    for item in items:
        await db_session.refresh(item)
        assert item.status == QueueItemStatus.FAILED
    assert items[0].next_attempt_at is not None
    assert items[1].next_attempt_at is None
    assert items[1].last_error_type == 'delivery_unknown'
    message = (await db_session.execute(select(NotificationMessage).where(
        NotificationMessage.source_id == str(items[1].id),
        NotificationMessage.source_type == 'distribution_delivery',
    ))).scalar_one()
    assert message.route == f'/automation/distribution?review_item={items[1].id}'
    # A second rule for the same destination cannot bypass the unknown attempt.
    with pytest.raises(ValueError):
        await DistributionQueueWorker().process_item_now(items[0].id)


@pytest.mark.parametrize('result', ['lost_response', 'empty_response', 'cancelled'])
async def test_send_boundary_is_durable_and_never_automatically_replayed(db_session, monkeypatch, result):
    from app.models import PushedRecord
    from sqlalchemy import select
    items, _ = await prepare(db_session)
    item_id = items[0].id

    async def send(*args):
        async with AsyncSessionLocal() as observer:
            sending = await observer.get(ContentQueueItem, item_id)
            assert sending.status == QueueItemStatus.PROCESSING
            assert sending.last_error_type == 'delivery_sending'
            # The network wait must not keep a SQLite writer transaction open.
            sending.priority += 1
            await observer.commit()
        if result == 'lost_response':
            raise TimeoutError('remote accepted, reply lost')
        if result == 'cancelled':
            raise asyncio.CancelledError()
        return None

    push = AsyncMock(side_effect=send)
    monkeypatch.setattr('app.tasks.distribution_worker.get_push_service', lambda _: SimpleNamespace(push=push))
    worker = DistributionQueueWorker()
    if result == 'cancelled':
        with pytest.raises(asyncio.CancelledError):
            await worker.process_item_now(item_id)
    else:
        await worker.process_item_now(item_id)
    await db_session.refresh(items[0])
    assert items[0].last_error_type == 'delivery_unknown'
    assert items[0].next_attempt_at is None
    assert (await db_session.execute(select(PushedRecord).where(
        PushedRecord.content_id == items[0].content_id,
    ))).first() is None
    with pytest.raises(ValueError):
        await worker.process_item_now(item_id)
    assert push.await_count == 1


async def test_unknown_requires_single_fresh_reconciliation_not_bulk_retry(db_session, client):
    from datetime import datetime, timedelta, timezone
    from app.core.time_utils import utcnow
    from app.models import NotificationMessage, PushedRecord
    from app.services.distribution.delivery_state import recover_expired_deliveries
    from sqlalchemy import select
    items, _ = await prepare(db_session)
    item = items[0]
    item.status = QueueItemStatus.PROCESSING
    item.locked_at = utcnow() - timedelta(days=1)
    item.locked_by = 'dead-sender'
    item.last_error_type = 'delivery_sending'
    await db_session.commit()
    await recover_expired_deliveries(db_session)
    for action, payload in [
        (f'items/{item.id}/retry', {}),
        (f'items/{item.id}/cancel', {}),
        (f'items/{item.id}/status', {'status': 'will_push'}),
        ('batch-retry', {'item_ids': [items[1].id, item.id]}),
        (f'content/{item.content_id}/repush-now', {}),
    ]:
        response = await client.post(f'/api/v1/distribution-queue/{action}', json=payload)
        assert response.status_code == 409, response.text
    await db_session.refresh(items[1])
    assert items[1].status == QueueItemStatus.SCHEDULED
    row = (await client.get(f'/api/v1/distribution-queue/items/{item.id}')).json()
    # The same instant in a non-UTC offset must match the observed database version.
    observed = datetime.fromisoformat(row['last_error_at'].replace('Z', '+00:00'))
    payload = {
        'outcome': 'delivered', 'message_id': 'observed-platform-message',
        'observed_error_at': observed.astimezone(timezone(timedelta(hours=8))).isoformat(),
    }
    response = await client.post(f'/api/v1/distribution-queue/items/{item.id}/reconcile', json=payload)
    assert response.status_code == 200, response.text
    assert response.json()['status'] == 'success'
    assert response.json()['next_attempt_at'] is None
    repeated = await client.post(f'/api/v1/distribution-queue/items/{item.id}/reconcile', json=payload)
    assert repeated.status_code == 409
    record = (await db_session.execute(select(PushedRecord).where(
        PushedRecord.content_id == item.content_id,
    ))).scalar_one()
    assert record.message_id == 'observed-platform-message'
    notice = (await db_session.execute(select(NotificationMessage).where(
        NotificationMessage.dedupe_key == f'delivery-unknown:{item.id}',
    ))).scalar_one()
    assert notice.dismissed_at is not None


async def test_telegram_media_timeout_does_not_fall_back_to_another_send(monkeypatch):
    from telegram.error import TimedOut
    from app.push.telegram import TelegramPushService
    bot = SimpleNamespace(send_photo=AsyncMock(side_effect=TimedOut()), send_message=AsyncMock())
    with pytest.raises(TimedOut):
        await TelegramPushService()._send_single_media(
            bot, 'test-chat', {'type': 'photo', 'url': 'https://fixture.invalid/image'}, 'caption',
        )
    bot.send_photo.assert_awaited_once()
    bot.send_message.assert_not_awaited()


@pytest.mark.parametrize('late_result', ['success', 'failure'])
async def test_expired_sender_cannot_overwrite_recovery_or_break_poll(db_session, monkeypatch, late_result):
    from datetime import timedelta
    from sqlalchemy import select, update
    from app.core.time_utils import utcnow
    from app.models import PushedRecord
    from app.services.distribution.delivery_state import recover_expired_deliveries
    items, _ = await prepare(db_session)
    item = items[0]
    item.priority = 100_000
    await db_session.commit()
    item_id, content_id = item.id, item.content_id

    async def send(*_args):
        async with AsyncSessionLocal() as recovery:
            await recovery.execute(update(ContentQueueItem).where(
                ContentQueueItem.id == item_id,
            ).values(locked_at=utcnow() - timedelta(days=1)))
            await recovery.commit()
            assert await recover_expired_deliveries(recovery) >= 1
        if late_result == 'failure':
            raise TimeoutError('late response')
        return 'late-message-id'

    push = AsyncMock(side_effect=send)
    monkeypatch.setattr('app.tasks.distribution_worker.get_push_service', lambda _: SimpleNamespace(push=push))
    result = await DistributionQueueWorker()._poll_once('fresh-worker')
    assert result['error_count'] == 0
    assert result['status_counts'] == {'failed': 1}
    await db_session.refresh(item)
    assert item.last_error_type == 'delivery_unknown'
    assert item.message_id is None
    assert (await db_session.execute(select(PushedRecord).where(
        PushedRecord.content_id == content_id,
    ))).first() is None
    push.assert_awaited_once()


async def test_unknown_cannot_be_reset_by_force_or_agent(db_session):
    from app.core.time_utils import utcnow
    from app.services.agent.tools.push import _push_batch_tool
    from app.services.distribution import DistributionService
    items, targets = await prepare(db_session)
    for item in items:
        item.status = QueueItemStatus.FAILED
        item.last_error_type = 'delivery_unknown'
        item.last_error_at = utcnow()
    for target in targets:
        target.backfill_watermark = None
    await db_session.commit()
    content_id = items[0].content_id
    assert await DistributionService(db_session).enqueue_content(content_id, force=True) == 0
    result = await _push_batch_tool({'content_ids': [content_id]}, SimpleNamespace(db=db_session))
    assert result['scheduled_count'] == 0
    for item in items:
        await db_session.refresh(item)
        assert item.last_error_type == 'delivery_unknown'


async def test_manual_claim_cannot_adopt_replacement_token_after_commit(db_session, monkeypatch):
    from contextlib import asynccontextmanager
    from datetime import timedelta
    from sqlalchemy import update
    from app.core.time_utils import utcnow

    items, _ = await prepare(db_session)
    item_id = items[0].id
    items[0].priority = 1_000_000
    await db_session.commit()
    committed, resume = asyncio.Event(), asyncio.Event()

    @asynccontextmanager
    async def paused_session():
        async with AsyncSessionLocal() as session:
            commit = session.commit

            async def commit_then_pause():
                await commit()
                if committed.is_set():
                    return
                async with AsyncSessionLocal() as observer:
                    current = await observer.get(ContentQueueItem, item_id)
                    claimed = current.status == QueueItemStatus.PROCESSING
                if claimed:
                    committed.set()
                    await resume.wait()

            monkeypatch.setattr(session, 'commit', commit_then_pause)
            yield session

    monkeypatch.setattr('app.tasks.distribution_worker.AsyncSessionLocal', paused_session)
    push = AsyncMock(return_value='must-not-send-with-stolen-token')
    monkeypatch.setattr('app.tasks.distribution_worker.get_push_service', lambda _: SimpleNamespace(push=push))
    worker = DistributionQueueWorker()
    delayed_execution = asyncio.create_task(worker.process_item_now(item_id))
    try:
        await asyncio.wait_for(committed.wait(), 5)
        async with AsyncSessionLocal() as expire:
            await expire.execute(update(ContentQueueItem).where(ContentQueueItem.id == item_id).values(
                locked_at=utcnow() - timedelta(days=1),
            ))
            await expire.commit()
        async with AsyncSessionLocal() as new_worker:
            replacement = await worker._claim_items(new_worker, 'replacement')
            assert [item.id for item in replacement] == [item_id]
            replacement_token = replacement[0].locked_by
    finally:
        resume.set()
        await delayed_execution

    push.assert_not_awaited()
    async with AsyncSessionLocal() as observer:
        current = await observer.get(ContentQueueItem, item_id)
        assert current.status == QueueItemStatus.PROCESSING
        assert current.last_error_type == 'delivery_preparing'
        assert current.locked_by == replacement_token


@pytest.mark.parametrize('peer_status', [QueueItemStatus.SCHEDULED, QueueItemStatus.FAILED])
async def test_not_sent_stops_peer_delivery_until_explicit_reschedule(
    db_session, client, monkeypatch, peer_status,
):
    from datetime import timedelta
    from app.core.time_utils import utcnow

    items, _ = await prepare(db_session)
    unknown, peer = items
    unknown.status = QueueItemStatus.FAILED
    unknown.last_error_type = 'delivery_unknown'
    unknown.last_error_at = utcnow()
    unknown.priority = peer.priority = 2_000_000
    peer.status = peer_status
    peer.attempt_count = 1
    peer.next_attempt_at = utcnow() - timedelta(seconds=1)

    # A different destination for the same content retains its authorization.
    chat = await db_session.get(BotChat, unknown.bot_chat_id)
    other_chat = BotChat(bot_config_id=chat.bot_config_id, chat_id=uuid4().hex,
        chat_type=BotChatType.CHANNEL)
    db_session.add(other_chat)
    await db_session.flush()
    db_session.add(DistributionTarget(rule_id=unknown.rule_id, bot_chat_id=other_chat.id))
    unrelated = ContentQueueItem(content_id=unknown.content_id, rule_id=unknown.rule_id,
        bot_chat_id=other_chat.id, target_platform='telegram', target_id=other_chat.chat_id,
        status=QueueItemStatus.SCHEDULED, priority=1_000_000)
    db_session.add(unrelated)
    await db_session.commit()

    observed = (await client.get(f'/api/v1/distribution-queue/items/{unknown.id}')).json()
    response = await client.post(f'/api/v1/distribution-queue/items/{unknown.id}/reconcile', json={
        'outcome': 'not_sent', 'observed_error_at': observed['last_error_at'],
    })
    assert response.status_code == 200, response.text

    push = AsyncMock(return_value='explicitly-authorized-message')
    monkeypatch.setattr('app.tasks.distribution_worker.get_push_service', lambda _: SimpleNamespace(push=push))
    worker = DistributionQueueWorker()
    await worker._poll_once('after-reconcile')
    assert [call.args[1] for call in push.await_args_list] == [other_chat.chat_id]
    await db_session.refresh(peer)
    assert peer.status == QueueItemStatus.FAILED
    assert peer.next_attempt_at is None
    assert peer.attempt_count == 1
    assert peer.last_error_type == 'delivery_not_sent'

    # Either stopped row can be explicitly scheduled through the existing API.
    resume_id = unknown.id if peer_status == QueueItemStatus.SCHEDULED else peer.id
    response = await client.post(f'/api/v1/distribution-queue/items/{resume_id}/schedule', json={
        'scheduled_at': utcnow().isoformat(),
    })
    assert response.status_code == 200, response.text
    await worker._poll_once('after-explicit-schedule')
    assert [call.args[1] for call in push.await_args_list] == [other_chat.chat_id, unknown.target_id]


async def test_not_sent_preserves_other_delivery_results_and_identities(db_session, client):
    from app.core.time_utils import utcnow

    items, _ = await prepare(db_session)
    unknown, other_unknown = items
    for item in items:
        item.status = QueueItemStatus.FAILED
        item.last_error_type = 'delivery_unknown'
        item.last_error_at = utcnow()

    other_content = Content(platform=Platform.UNIVERSAL, url=f'https://fixture.invalid/{uuid4()}')
    db_session.add(other_content)
    await db_session.flush()
    protected = [other_unknown]
    for name, status, content_id, platform in [
        ('sending', QueueItemStatus.PROCESSING, unknown.content_id, 'telegram'),
        ('sent', QueueItemStatus.SUCCESS, unknown.content_id, 'telegram'),
        ('other-content', QueueItemStatus.SCHEDULED, other_content.id, 'telegram'),
        ('other-platform', QueueItemStatus.SCHEDULED, unknown.content_id, 'qq'),
    ]:
        rule = DistributionRule(name=f'{name}-{uuid4()}', match_conditions={})
        db_session.add(rule)
        await db_session.flush()
        peer = ContentQueueItem(content_id=content_id, rule_id=rule.id,
            bot_chat_id=unknown.bot_chat_id, target_platform=platform, target_id=unknown.target_id,
            status=status, locked_by='active-owner' if name == 'sending' else None,
            locked_at=utcnow() if name == 'sending' else None,
            message_id='accepted-message' if name == 'sent' else None)
        db_session.add(peer)
        protected.append(peer)
    await db_session.commit()
    before = [(item.status, item.last_error_type, item.last_error_at, item.locked_by, item.message_id)
        for item in protected]

    observed = (await client.get(f'/api/v1/distribution-queue/items/{unknown.id}')).json()
    response = await client.post(f'/api/v1/distribution-queue/items/{unknown.id}/reconcile', json={
        'outcome': 'not_sent', 'observed_error_at': observed['last_error_at'],
    })
    assert response.status_code == 200, response.text
    for item, expected in zip(protected, before):
        await db_session.refresh(item)
        assert (item.status, item.last_error_type, item.last_error_at, item.locked_by, item.message_id) == expected
