import pytest
import uuid
from unittest.mock import AsyncMock, patch
from datetime import timedelta
from sqlalchemy import delete

from app.services.distribution.scheduler import (
    enqueue_content,
    enqueue_content_background,
)
from app.tasks.distribution_worker import compute_auto_scheduled_at
from app.models import (
    Content,
    DistributionRule,
    DistributionTarget,
    BotChat,
    BotConfig,
    BotChatType,
    BotConfigPlatform,
    ContentQueueItem,
    QueueItemStatus,
    ContentStatus,
    ReviewStatus,
    PushedRecord,
    Platform,
)
from app.core.time_utils import utcnow


@pytest.fixture(autouse=True)
def mock_event_bus():
    with patch("app.core.events.event_bus.publish", new_callable=AsyncMock) as mock:
        yield mock


@pytest.fixture(autouse=True)
async def clean_scheduler_tables(db_session):
    """避免与其他测试文件共享 DB 时出现唯一键污染。"""
    yield
    for model in (
        ContentQueueItem,
        DistributionTarget,
        DistributionRule,
        BotChat,
        BotConfig,
        PushedRecord,
        Content,
    ):
        await db_session.execute(delete(model))
    await db_session.commit()


@pytest.fixture
def patch_session_local(monkeypatch):
    from tests.conftest import TestingSessionLocal
    monkeypatch.setattr(
        "app.services.distribution.scheduler.AsyncSessionLocal", TestingSessionLocal
    )


async def _create_bot_chat(db_session, *, chat_id="test_chat_1", nsfw_chat_id=None):
    bot_config = BotConfig(platform=BotConfigPlatform.TELEGRAM, name="sched_test_bot")
    db_session.add(bot_config)
    await db_session.flush()

    bot_chat = BotChat(
        bot_config_id=bot_config.id,
        chat_id=chat_id,
        chat_type=BotChatType.CHANNEL,
        enabled=True,
        is_accessible=True,
        nsfw_chat_id=nsfw_chat_id,
    )
    db_session.add(bot_chat)
    await db_session.flush()
    return bot_chat


async def _create_rule(db_session, *, name, match_conditions=None, approval_required=False,
                       rate_limit=None, time_window=None, nsfw_policy="allow", priority=0):
    rule = DistributionRule(
        name=name,
        match_conditions=match_conditions or {},
        enabled=True,
        approval_required=approval_required,
        rate_limit=rate_limit,
        time_window=time_window,
        nsfw_policy=nsfw_policy,
        priority=priority,
    )
    db_session.add(rule)
    await db_session.flush()
    return rule


async def _create_target(db_session, *, rule_id, bot_chat_id):
    target = DistributionTarget(
        rule_id=rule_id,
        bot_chat_id=bot_chat_id,
        enabled=True,
    )
    db_session.add(target)
    await db_session.flush()
    return target


async def _create_content(db_session, *, url="https://sched-test.com", platform=Platform.BILIBILI,
                          status=ContentStatus.PARSE_SUCCESS, review_status=ReviewStatus.APPROVED,
                          is_nsfw=False, queue_priority=0):
    content = Content(
        url=url,
        platform=platform,
        status=status,
        review_status=review_status,
        is_nsfw=is_nsfw,
        queue_priority=queue_priority,
        title="Scheduler Test",
    )
    db_session.add(content)
    await db_session.flush()
    return content


# ---------- compute_auto_scheduled_at ----------


@pytest.mark.asyncio
async def test_compute_auto_scheduled_at_no_rate_limit(db_session):
    rule = await _create_rule(db_session, name="no_rate_sched", rate_limit=None, time_window=None)
    bot_chat = await _create_bot_chat(db_session, chat_id="sched_nrl")
    await db_session.commit()

    before = utcnow()
    result = await compute_auto_scheduled_at(
        session=db_session, rule=rule, bot_chat_id=bot_chat.id, target_id=bot_chat.chat_id
    )
    after = utcnow()

    assert before <= result <= after


@pytest.mark.asyncio
async def test_compute_auto_scheduled_at_with_rate_limit(db_session):
    # Ensure the "no prior records" assumption is true in shared test DB setups.
    await db_session.execute(delete(ContentQueueItem))
    await db_session.execute(delete(PushedRecord))
    await db_session.commit()

    uid = uuid.uuid4().hex[:8]
    rule = await _create_rule(
        db_session, name=f"rate_limit_sched_{uid}", rate_limit=5, time_window=3600
    )
    bot_chat = await _create_bot_chat(db_session, chat_id=f"sched_rl_{uid}")
    await db_session.commit()

    # No prior queue items or pushed records — should return ~utcnow()
    before = utcnow()
    result = await compute_auto_scheduled_at(
        session=db_session, rule=rule, bot_chat_id=bot_chat.id, target_id=bot_chat.chat_id
    )
    after = utcnow()

    assert before <= result <= after


@pytest.mark.asyncio
async def test_compute_auto_scheduled_at_throttled(db_session):
    uid = uuid.uuid4().hex[:8]
    rule = await _create_rule(
        db_session, name=f"throttle_sched_{uid}", rate_limit=2, time_window=3600
    )
    bot_chat = await _create_bot_chat(db_session, chat_id=f"sched_thr_{uid}")
    # Create dummy contents to satisfy PushedRecord FK and unique constraint
    dummy_contents = []
    for i in range(2):
        c = Content(
            url=f"https://throttle-dummy-{uid}-{i}.com",
            platform=Platform.BILIBILI,
            status=ContentStatus.PARSE_SUCCESS,
            review_status=ReviewStatus.APPROVED,
            title=f"Throttle dummy {i}",
        )
        db_session.add(c)
    await db_session.flush()
    dummy_contents = [c for c in db_session.new]  # already flushed above

    now = utcnow()
    # Re-query the dummy contents to get their IDs
    from sqlalchemy import select as sa_select
    res = await db_session.execute(
        sa_select(Content).where(Content.url.like(f"https://throttle-dummy-{uid}-%"))
    )
    dummies = res.scalars().all()

    # Insert 2 recent pushed records (>= rate_limit) within the time window
    for i, dummy in enumerate(dummies[:2]):
        pr = PushedRecord(
            content_id=dummy.id,
            target_platform="telegram",
            target_id=bot_chat.chat_id,
            push_status="success",
            pushed_at=now - timedelta(seconds=60 * (i + 1)),
        )
        db_session.add(pr)
    await db_session.commit()

    result = await compute_auto_scheduled_at(
        session=db_session, rule=rule, bot_chat_id=bot_chat.id, target_id=bot_chat.chat_id
    )

    # The earliest push is at now - 120s; throttle_until = earliest + 3600s
    # So result should be well into the future
    assert result > now


# ---------- enqueue_content ----------


@pytest.mark.asyncio
async def test_enqueue_content_not_found(db_session):
    count = await enqueue_content(999999, session=db_session)
    assert count == 0


@pytest.mark.asyncio
async def test_enqueue_content_wrong_status(db_session):
    content = await _create_content(
        db_session, url="https://wrong-status.com", status=ContentStatus.UNPROCESSED
    )
    await db_session.commit()

    count = await enqueue_content(content.id, session=db_session)
    assert count == 0


@pytest.mark.asyncio
async def test_enqueue_content_rejected_review(db_session):
    content = await _create_content(
        db_session,
        url="https://rejected-review.com",
        review_status=ReviewStatus.REJECTED,
    )
    await db_session.commit()

    count = await enqueue_content(content.id, session=db_session)
    assert count == 0


@pytest.mark.asyncio
async def test_enqueue_content_creates_items(db_session, mock_event_bus):
    bot_chat = await _create_bot_chat(db_session, chat_id="sched_create")
    rule = await _create_rule(db_session, name="sched_create_rule", priority=5)
    await _create_target(db_session, rule_id=rule.id, bot_chat_id=bot_chat.id)
    content = await _create_content(
        db_session, url="https://sched-create.com", queue_priority=2
    )
    await db_session.commit()

    count = await enqueue_content(content.id, session=db_session)
    assert count >= 1

    from sqlalchemy import select
    result = await db_session.execute(
        select(ContentQueueItem).where(
            ContentQueueItem.content_id == content.id,
            ContentQueueItem.rule_id == rule.id,
            ContentQueueItem.bot_chat_id == bot_chat.id,
        )
    )
    item = result.scalar_one_or_none()
    assert item is not None
    assert item.status == QueueItemStatus.SCHEDULED
    assert item.priority == rule.priority + content.queue_priority

    mock_event_bus.assert_called()


@pytest.mark.asyncio
async def test_enqueue_content_dedup_existing_success(db_session):
    bot_chat = await _create_bot_chat(db_session, chat_id="sched_dedup")
    rule = await _create_rule(
        db_session, name="sched_dedup_rule",
        match_conditions={"platform": "weibo"},
    )
    await _create_target(db_session, rule_id=rule.id, bot_chat_id=bot_chat.id)
    content = await _create_content(
        db_session, url="https://sched-dedup.com", platform=Platform.WEIBO
    )
    await db_session.flush()

    existing = ContentQueueItem(
        content_id=content.id,
        rule_id=rule.id,
        bot_chat_id=bot_chat.id,
        target_platform="telegram",
        target_id=bot_chat.chat_id,
        status=QueueItemStatus.SUCCESS,
        priority=0,
    )
    db_session.add(existing)
    await db_session.commit()
    existing_id = existing.id

    await enqueue_content(content.id, session=db_session)

    # The existing SUCCESS item should remain unchanged (not duplicated or reset)
    await db_session.refresh(existing)
    assert existing.id == existing_id
    assert existing.status == QueueItemStatus.SUCCESS

    # No second queue item for the same (rule, bot_chat) combo
    from sqlalchemy import select
    result = await db_session.execute(
        select(ContentQueueItem).where(
            ContentQueueItem.content_id == content.id,
            ContentQueueItem.rule_id == rule.id,
            ContentQueueItem.bot_chat_id == bot_chat.id,
        )
    )
    items = result.scalars().all()
    assert len(items) == 1


@pytest.mark.asyncio
async def test_enqueue_content_force_reset_failed(db_session, mock_event_bus):
    bot_chat = await _create_bot_chat(db_session, chat_id="sched_force")
    rule = await _create_rule(db_session, name="sched_force_rule")
    await _create_target(db_session, rule_id=rule.id, bot_chat_id=bot_chat.id)
    content = await _create_content(db_session, url="https://sched-force.com")
    await db_session.flush()

    existing = ContentQueueItem(
        content_id=content.id,
        rule_id=rule.id,
        bot_chat_id=bot_chat.id,
        target_platform="telegram",
        target_id=bot_chat.chat_id,
        status=QueueItemStatus.FAILED,
        priority=0,
        last_error="old error",
        attempt_count=3,
    )
    db_session.add(existing)
    await db_session.commit()

    count = await enqueue_content(content.id, session=db_session, force=True)
    assert count >= 1

    await db_session.refresh(existing)
    assert existing.status == QueueItemStatus.SCHEDULED
    assert existing.attempt_count == 0
    assert existing.last_error is None


@pytest.mark.asyncio
async def test_enqueue_content_approval_required(db_session, mock_event_bus):
    bot_chat = await _create_bot_chat(db_session, chat_id="sched_appr")
    rule = await _create_rule(
        db_session, name="sched_approval_rule", approval_required=True
    )
    await _create_target(db_session, rule_id=rule.id, bot_chat_id=bot_chat.id)
    content = await _create_content(
        db_session,
        url="https://sched-approval.com",
        review_status=ReviewStatus.APPROVED,
    )
    await db_session.commit()

    count = await enqueue_content(content.id, session=db_session)
    assert count >= 1

    from sqlalchemy import select
    result = await db_session.execute(
        select(ContentQueueItem).where(
            ContentQueueItem.content_id == content.id,
            ContentQueueItem.rule_id == rule.id,
            ContentQueueItem.bot_chat_id == bot_chat.id,
        )
    )
    item = result.scalar_one_or_none()
    assert item is not None
    assert item.status == QueueItemStatus.SCHEDULED


# ---------- enqueue_content_background ----------


@pytest.mark.asyncio
async def test_enqueue_content_background_catches_exception(patch_session_local):
    with patch(
        "app.services.distribution.scheduler._enqueue_content_impl",
        new_callable=AsyncMock,
        side_effect=RuntimeError("boom"),
    ):
        # Should NOT raise
        await enqueue_content_background(999999)

