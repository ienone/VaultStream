import uuid
import pytest
from unittest.mock import AsyncMock, patch, MagicMock
from app.tasks.distribution_worker import DistributionQueueWorker
from app.models import Content, ContentQueueItem, QueueItemStatus, ContentStatus, ReviewStatus, BotChat, DistributionRule, BotConfig, BotChatType, BotConfigPlatform, PushedRecord
from app.core.time_utils import utcnow

@pytest.fixture(autouse=True)
def mock_event_bus():
    with patch("app.core.events.event_bus.publish", new_callable=AsyncMock) as mock:
        yield mock

@pytest.mark.asyncio
async def test_process_item_now_success(db_session, monkeypatch):
    # 1. Setup data
    bot_config = BotConfig(platform=BotConfigPlatform.TELEGRAM, name="test_bot")
    db_session.add(bot_config)
    await db_session.flush()
    
    bot_chat = BotChat(
        bot_config_id=bot_config.id,
        chat_id="123", 
        chat_type=BotChatType.CHANNEL,
        enabled=True, 
        is_accessible=True
    )
    db_session.add(bot_chat)
    await db_session.flush()
    
    rule = DistributionRule(
        name="test_rule", 
        match_conditions={"platforms": ["bilibili"]}, 
        enabled=True
    )
    db_session.add(rule)
    await db_session.flush()
    
    content = Content(
        url="https://test.com", 
        platform="bilibili", 
        status=ContentStatus.PARSE_SUCCESS, 
        review_status=ReviewStatus.APPROVED,
        title="Test Content",
        body="Test Body"
    )
    db_session.add(content)
    await db_session.flush()
    
    item = ContentQueueItem(
        content_id=content.id,
        bot_chat_id=bot_chat.id,
        rule_id=rule.id,
        target_platform="telegram",
        target_id="123",
        status=QueueItemStatus.SCHEDULED,
        priority=10
    )
    db_session.add(item)
    await db_session.commit()
    await db_session.refresh(item)
    item_id = item.id

    # 2. Patch dependencies
    from tests.conftest import TestingSessionLocal
    monkeypatch.setattr("app.tasks.distribution_worker.AsyncSessionLocal", TestingSessionLocal)
    
    mock_push_service = AsyncMock()
    mock_push_service.push.return_value = "msg_123"
    
    with patch("app.tasks.distribution_worker.get_push_service", return_value=mock_push_service):
        worker = DistributionQueueWorker(worker_count=0)
        
        # 3. Execute
        await worker.process_item_now(item_id)
        
        # 4. Verify
        await db_session.refresh(item)
        assert item.status == QueueItemStatus.SUCCESS
        assert item.message_id == "msg_123"
        mock_push_service.push.assert_called_once()

@pytest.mark.asyncio
async def test_process_item_now_failure(db_session, monkeypatch):
    # 1. Setup data
    bot_config = BotConfig(platform=BotConfigPlatform.TELEGRAM, name="test_bot")
    db_session.add(bot_config)
    await db_session.flush()
    
    bot_chat = BotChat(
        bot_config_id=bot_config.id,
        chat_id="123", 
        chat_type=BotChatType.CHANNEL,
        enabled=True, 
        is_accessible=True
    )
    db_session.add(bot_chat)
    await db_session.flush()
    
    rule = DistributionRule(
        name="test_rule_fail", 
        match_conditions={"platforms": ["bilibili"]}, 
        enabled=True
    )
    db_session.add(rule)
    await db_session.flush()
    
    content = Content(
        url="https://test.com", 
        platform="bilibili", 
        status=ContentStatus.PARSE_SUCCESS, 
        review_status=ReviewStatus.APPROVED,
        title="Test Content"
    )
    db_session.add(content)
    await db_session.flush()
    
    item = ContentQueueItem(
        content_id=content.id,
        bot_chat_id=bot_chat.id,
        rule_id=rule.id,
        target_platform="telegram",
        target_id="123",
        status=QueueItemStatus.SCHEDULED,
    )
    db_session.add(item)
    await db_session.commit()
    item_id = item.id

    # 2. Patch
    from tests.conftest import TestingSessionLocal
    monkeypatch.setattr("app.tasks.distribution_worker.AsyncSessionLocal", TestingSessionLocal)
    
    mock_push_service = AsyncMock()
    mock_push_service.push.side_effect = Exception("Push failed")
    
    with patch("app.tasks.distribution_worker.get_push_service", return_value=mock_push_service):
        worker = DistributionQueueWorker(worker_count=0)
        
        # 3. Execute
        await worker.process_item_now(item_id)
        
        # 4. Verify
        await db_session.refresh(item)
        assert item.status == QueueItemStatus.FAILED
        assert "Push failed" in item.last_error


# ── Helper ──────────────────────────────────────────────

async def _setup_full_chain(db_session, *, bot_chat_enabled=True, bot_chat_accessible=True,
                             content_status=ContentStatus.PARSE_SUCCESS,
                             review_status=ReviewStatus.APPROVED,
                             item_status=QueueItemStatus.SCHEDULED,
                             target_platform="telegram",
                             nsfw_routing_result=None,
                             attempt_count=0,
                             max_attempts=3):
    """Create a complete BotConfig→BotChat→Rule→Content→QueueItem chain and return all objects."""
    uid = uuid.uuid4().hex[:8]
    bot_config = BotConfig(platform=BotConfigPlatform.TELEGRAM, name=f"test_bot_{uid}")
    db_session.add(bot_config)
    await db_session.flush()

    bot_chat = BotChat(
        bot_config_id=bot_config.id,
        chat_id="123",
        chat_type=BotChatType.CHANNEL,
        enabled=bot_chat_enabled,
        is_accessible=bot_chat_accessible,
    )
    db_session.add(bot_chat)
    await db_session.flush()

    rule = DistributionRule(
        name=f"test_rule_{uid}",
        match_conditions={"platforms": ["bilibili"]},
        enabled=True,
    )
    db_session.add(rule)
    await db_session.flush()

    content = Content(
        url=f"https://test.com/{uid}",
        platform="bilibili",
        status=content_status,
        review_status=review_status,
        title="Test Content",
        body="Test Body",
    )
    db_session.add(content)
    await db_session.flush()

    item = ContentQueueItem(
        content_id=content.id,
        bot_chat_id=bot_chat.id,
        rule_id=rule.id,
        target_platform=target_platform,
        target_id="123",
        status=item_status,
        priority=10,
        nsfw_routing_result=nsfw_routing_result,
        attempt_count=attempt_count,
        max_attempts=max_attempts,
    )
    db_session.add(item)
    await db_session.commit()
    await db_session.refresh(item)
    return bot_config, bot_chat, rule, content, item


# ── process_item_now — item not found ───────────────────

@pytest.mark.asyncio
async def test_process_item_now_not_found(db_session, monkeypatch):
    from tests.conftest import TestingSessionLocal
    monkeypatch.setattr("app.tasks.distribution_worker.AsyncSessionLocal", TestingSessionLocal)

    worker = DistributionQueueWorker(worker_count=0)
    with pytest.raises(ValueError, match="Queue item not found"):
        await worker.process_item_now(999999)


# ── process_item_now — already SUCCESS ──────────────────

@pytest.mark.asyncio
async def test_process_item_now_already_success(db_session, monkeypatch):
    _, _, _, _, item = await _setup_full_chain(db_session, item_status=QueueItemStatus.SUCCESS)

    from tests.conftest import TestingSessionLocal
    monkeypatch.setattr("app.tasks.distribution_worker.AsyncSessionLocal", TestingSessionLocal)

    worker = DistributionQueueWorker(worker_count=0)
    with pytest.raises(ValueError, match="not pushable"):
        await worker.process_item_now(item.id)


# ── _process_item — bot_chat disabled ───────────────────

@pytest.mark.asyncio
async def test_process_item_bot_chat_disabled(db_session, monkeypatch):
    _, _, _, _, item = await _setup_full_chain(db_session, bot_chat_enabled=False)

    from tests.conftest import TestingSessionLocal
    monkeypatch.setattr("app.tasks.distribution_worker.AsyncSessionLocal", TestingSessionLocal)

    mock_push_service = AsyncMock()
    with patch("app.tasks.distribution_worker.get_push_service", return_value=mock_push_service):
        worker = DistributionQueueWorker(worker_count=0)
        await worker.process_item_now(item.id)

    await db_session.refresh(item)
    assert item.status == QueueItemStatus.SCHEDULED
    assert item.last_error_type == "target_unavailable"


# ── _process_item — content not eligible ────────────────

@pytest.mark.asyncio
async def test_process_item_content_not_eligible(db_session, monkeypatch):
    _, _, _, _, item = await _setup_full_chain(db_session, review_status=ReviewStatus.PENDING)

    from tests.conftest import TestingSessionLocal
    monkeypatch.setattr("app.tasks.distribution_worker.AsyncSessionLocal", TestingSessionLocal)

    mock_push_service = AsyncMock()
    with patch("app.tasks.distribution_worker.get_push_service", return_value=mock_push_service):
        worker = DistributionQueueWorker(worker_count=0)
        await worker.process_item_now(item.id)

    await db_session.refresh(item)
    assert item.status == QueueItemStatus.FAILED
    assert item.last_error_type == "content_not_eligible"


# ── _process_item — dedupe ──────────────────────────────

@pytest.mark.asyncio
async def test_process_item_dedupe(db_session, monkeypatch):
    _, _, _, content, item = await _setup_full_chain(db_session)

    # Insert existing pushed record for same content+target
    existing = PushedRecord(
        content_id=content.id,
        target_platform="telegram",
        target_id="123",
        message_id="old_msg",
        push_status="success",
    )
    db_session.add(existing)
    await db_session.commit()

    from tests.conftest import TestingSessionLocal
    monkeypatch.setattr("app.tasks.distribution_worker.AsyncSessionLocal", TestingSessionLocal)

    mock_push_service = AsyncMock()
    with patch("app.tasks.distribution_worker.get_push_service", return_value=mock_push_service):
        worker = DistributionQueueWorker(worker_count=0)
        await worker.process_item_now(item.id)

    await db_session.refresh(item)
    assert item.status == QueueItemStatus.FAILED
    assert item.last_error_type == "already_pushed_dedupe"


# ── _process_item — nsfw routing override ───────────────

@pytest.mark.asyncio
async def test_process_item_nsfw_routing(db_session, monkeypatch):
    _, _, _, _, item = await _setup_full_chain(
        db_session, nsfw_routing_result={"target_id": "nsfw_channel_456"}
    )

    from tests.conftest import TestingSessionLocal
    monkeypatch.setattr("app.tasks.distribution_worker.AsyncSessionLocal", TestingSessionLocal)

    mock_push_service = AsyncMock()
    mock_push_service.push.return_value = "msg_nsfw"

    with patch("app.tasks.distribution_worker.get_push_service", return_value=mock_push_service):
        worker = DistributionQueueWorker(worker_count=0)
        await worker.process_item_now(item.id)

    await db_session.refresh(item)
    assert item.status == QueueItemStatus.SUCCESS
    # Verify push was called with the overridden target
    mock_push_service.push.assert_called_once()
    actual_target = mock_push_service.push.call_args[0][1]
    assert actual_target == "nsfw_channel_456"


# ── _process_item — no message_id, telegram → FAILED ────

@pytest.mark.asyncio
async def test_process_item_no_message_id_telegram_failed(db_session, monkeypatch):
    _, _, _, _, item = await _setup_full_chain(db_session, target_platform="telegram")

    from tests.conftest import TestingSessionLocal
    monkeypatch.setattr("app.tasks.distribution_worker.AsyncSessionLocal", TestingSessionLocal)

    mock_push_service = AsyncMock()
    mock_push_service.push.return_value = None  # no message_id

    with patch("app.tasks.distribution_worker.get_push_service", return_value=mock_push_service):
        worker = DistributionQueueWorker(worker_count=0)
        await worker.process_item_now(item.id)

    await db_session.refresh(item)
    assert item.status == QueueItemStatus.FAILED
    assert "no message_id" in item.last_error


# ── _process_item — no message_id, non-telegram → FAILED

@pytest.mark.asyncio
async def test_process_item_no_message_id_non_telegram(db_session, monkeypatch):
    _, _, _, _, item = await _setup_full_chain(db_session, target_platform="discord")

    from tests.conftest import TestingSessionLocal
    monkeypatch.setattr("app.tasks.distribution_worker.AsyncSessionLocal", TestingSessionLocal)

    mock_push_service = AsyncMock()
    mock_push_service.push.return_value = None  # no message_id

    with patch("app.tasks.distribution_worker.get_push_service", return_value=mock_push_service):
        worker = DistributionQueueWorker(worker_count=0)
        await worker.process_item_now(item.id)

    await db_session.refresh(item)
    assert item.status == QueueItemStatus.FAILED
    assert "no message_id" in item.last_error


# ── _handle_failure — under max_attempts ────────────────

@pytest.mark.asyncio
async def test_handle_failure_under_max(db_session, monkeypatch):
    _, _, _, _, item = await _setup_full_chain(
        db_session, attempt_count=0, max_attempts=3
    )

    from tests.conftest import TestingSessionLocal
    monkeypatch.setattr("app.tasks.distribution_worker.AsyncSessionLocal", TestingSessionLocal)

    mock_push_service = AsyncMock()
    mock_push_service.push.side_effect = RuntimeError("transient error")

    with patch("app.tasks.distribution_worker.get_push_service", return_value=mock_push_service):
        worker = DistributionQueueWorker(worker_count=0)
        await worker.process_item_now(item.id)

    await db_session.refresh(item)
    assert item.status == QueueItemStatus.FAILED
    assert item.attempt_count == 1
    assert item.next_attempt_at is not None  # retry scheduled


# ── _handle_failure — at max_attempts ───────────────────

@pytest.mark.asyncio
async def test_handle_failure_at_max(db_session, monkeypatch):
    _, _, _, _, item = await _setup_full_chain(
        db_session, attempt_count=2, max_attempts=3
    )

    from tests.conftest import TestingSessionLocal
    monkeypatch.setattr("app.tasks.distribution_worker.AsyncSessionLocal", TestingSessionLocal)

    mock_push_service = AsyncMock()
    mock_push_service.push.side_effect = RuntimeError("final error")

    with patch("app.tasks.distribution_worker.get_push_service", return_value=mock_push_service):
        worker = DistributionQueueWorker(worker_count=0)
        await worker.process_item_now(item.id)

    await db_session.refresh(item)
    assert item.status == QueueItemStatus.FAILED
    assert item.attempt_count == 3
    assert item.next_attempt_at is None  # no more retries


# ── _claim_items — scheduled items are claimed ──────────

@pytest.mark.asyncio
async def test_claim_items_scheduled(db_session, monkeypatch):
    _, _, _, _, item = await _setup_full_chain(db_session)

    from tests.conftest import TestingSessionLocal

    async with TestingSessionLocal() as session:
        worker = DistributionQueueWorker(worker_count=0)
        claimed = await worker._claim_items(session, "test-worker")

    assert len(claimed) >= 1
    claimed_ids = {c.id for c in claimed}
    assert item.id in claimed_ids
    target = next(c for c in claimed if c.id == item.id)
    assert target.status == QueueItemStatus.PROCESSING
    assert target.locked_by == "test-worker"


# ── _claim_items — empty when nothing eligible ──────────

@pytest.mark.asyncio
async def test_claim_items_empty(db_session, monkeypatch):
    # Item is SUCCESS → not eligible for claiming
    _, _, _, _, item = await _setup_full_chain(db_session, item_status=QueueItemStatus.SUCCESS)

    from tests.conftest import TestingSessionLocal

    async with TestingSessionLocal() as session:
        worker = DistributionQueueWorker(worker_count=0)
        claimed = await worker._claim_items(session, "test-worker")

    assert claimed == []


# ── start / stop lifecycle ──────────────────────────────

@pytest.mark.asyncio
async def test_start_stop():
    worker = DistributionQueueWorker(worker_count=2)

    worker.start()
    assert worker.running is True
    assert len(worker._tasks) == 2

    # calling start again should be no-op
    worker.start()
    assert len(worker._tasks) == 2

    await worker.stop()
    assert worker.running is False
    assert len(worker._tasks) == 0


# ── get_queue_worker singleton ──────────────────────────

def test_get_queue_worker_singleton(monkeypatch):
    import app.tasks.distribution_worker as mod
    monkeypatch.setattr(mod, "_queue_worker", None)

    w1 = mod.get_queue_worker(worker_count=1)
    w2 = mod.get_queue_worker(worker_count=5)
    assert w1 is w2
