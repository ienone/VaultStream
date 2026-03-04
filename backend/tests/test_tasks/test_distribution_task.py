import pytest
from unittest.mock import AsyncMock, patch, MagicMock
from app.tasks.distribution_worker import DistributionQueueWorker
from app.models import Content, ContentQueueItem, QueueItemStatus, ContentStatus, ReviewStatus, BotChat, DistributionRule, BotConfig, BotChatType, BotConfigPlatform
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
        needs_approval=False,
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
        needs_approval=False
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
