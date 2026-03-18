import pytest
from unittest.mock import AsyncMock, patch

from sqlalchemy import delete

from app.models import (
    Content, ContentStatus, ReviewStatus, Platform,
    DistributionRule, BotConfig, BotChat, BotChatType, BotConfigPlatform,
)
from app.core.time_utils import utcnow
from app.services.distribution.engine import DistributionEngine


@pytest.fixture(autouse=True)
def mock_event_bus():
    with patch("app.core.events.event_bus.publish", new_callable=AsyncMock) as mock:
        yield mock


@pytest.fixture(autouse=True)
async def clean_tables(db_session):
    """Clean up test data before each test to avoid leakage."""
    yield
    for model in (Content, DistributionRule, BotChat, BotConfig):
        await db_session.execute(delete(model))
    await db_session.commit()


async def _create_bot_chat(db_session) -> BotChat:
    bot_config = BotConfig(platform=BotConfigPlatform.TELEGRAM, name="test_bot")
    db_session.add(bot_config)
    await db_session.flush()

    bot_chat = BotChat(
        bot_config_id=bot_config.id,
        chat_id="123",
        chat_type=BotChatType.CHANNEL,
        enabled=True,
        is_accessible=True,
    )
    db_session.add(bot_chat)
    await db_session.flush()
    return bot_chat


async def _create_content(db_session, **kwargs) -> Content:
    defaults = dict(
        url="https://test.com",
        platform=Platform.BILIBILI,
        status=ContentStatus.PARSE_SUCCESS,
        review_status=ReviewStatus.PENDING,
        title="Test Content",
        body="Test Body",
    )
    defaults.update(kwargs)
    content = Content(**defaults)
    db_session.add(content)
    await db_session.flush()
    return content


async def _create_rule(db_session, **kwargs) -> DistributionRule:
    defaults = dict(
        name=f"rule_{utcnow().timestamp()}",
        match_conditions={},
        enabled=True,
    )
    defaults.update(kwargs)
    rule = DistributionRule(**defaults)
    db_session.add(rule)
    await db_session.flush()
    return rule


# --- match_rules tests ---


@pytest.mark.asyncio
async def test_match_rules_returns_matching(db_session):
    """Content with platform=bilibili matches rule with platform condition."""
    await _create_bot_chat(db_session)
    rule = await _create_rule(
        db_session,
        name="bilibili_rule",
        match_conditions={"platform": "bilibili"},
    )
    content = await _create_content(db_session, platform=Platform.BILIBILI)
    await db_session.commit()

    engine = DistributionEngine(db_session)
    matched = await engine.match_rules(content)

    assert any(r.id == rule.id for r in matched)


@pytest.mark.asyncio
async def test_match_rules_excludes_non_matching(db_session):
    """Content doesn't match rule conditions → empty list for that rule."""
    await _create_bot_chat(db_session)
    await _create_rule(
        db_session,
        name="twitter_only_rule",
        match_conditions={"platform": "twitter"},
    )
    content = await _create_content(db_session, platform=Platform.BILIBILI)
    await db_session.commit()

    engine = DistributionEngine(db_session)
    matched = await engine.match_rules(content)

    rule_names = [r.name for r in matched]
    assert "twitter_only_rule" not in rule_names


@pytest.mark.asyncio
async def test_match_rules_empty_conditions_matches_all(db_session):
    """Rule with empty match_conditions matches everything."""
    await _create_bot_chat(db_session)
    rule = await _create_rule(
        db_session,
        name="catch_all_rule",
        match_conditions={},
    )
    content = await _create_content(db_session, platform=Platform.TWITTER)
    await db_session.commit()

    engine = DistributionEngine(db_session)
    matched = await engine.match_rules(content)

    assert any(r.id == rule.id for r in matched)


@pytest.mark.asyncio
async def test_match_rules_only_enabled(db_session):
    """Disabled rules are not returned."""
    await _create_bot_chat(db_session)
    await _create_rule(
        db_session,
        name="disabled_rule",
        match_conditions={},
        enabled=False,
    )
    content = await _create_content(db_session, platform=Platform.BILIBILI)
    await db_session.commit()

    engine = DistributionEngine(db_session)
    matched = await engine.match_rules(content)

    rule_names = [r.name for r in matched]
    assert "disabled_rule" not in rule_names


# --- auto_approve_if_eligible tests ---


@pytest.mark.asyncio
async def test_auto_approve_if_eligible_approves(db_session):
    """Content matching a non-approval-required rule gets AUTO_APPROVED."""
    await _create_bot_chat(db_session)
    await _create_rule(
        db_session,
        name="auto_approve_rule",
        match_conditions={"platform": "bilibili"},
        approval_required=False,
    )
    content = await _create_content(
        db_session,
        platform=Platform.BILIBILI,
        review_status=ReviewStatus.PENDING,
    )
    await db_session.commit()

    with patch(
        "app.services.distribution.scheduler.enqueue_content_background",
        new_callable=AsyncMock,
    ):
        engine = DistributionEngine(db_session)
        result = await engine.auto_approve_if_eligible(content)

    assert result is True
    await db_session.refresh(content)
    assert content.review_status == ReviewStatus.AUTO_APPROVED
    assert "auto_approve_rule" in content.review_note


@pytest.mark.asyncio
async def test_auto_approve_if_eligible_no_match(db_session):
    """No non-approval-required rule matches → returns False, status unchanged."""
    await _create_bot_chat(db_session)
    await _create_rule(
        db_session,
        name="no_match_auto_rule",
        match_conditions={"platform": "twitter"},
        approval_required=False,
    )
    content = await _create_content(
        db_session,
        platform=Platform.BILIBILI,
        review_status=ReviewStatus.PENDING,
    )
    await db_session.commit()

    engine = DistributionEngine(db_session)
    result = await engine.auto_approve_if_eligible(content)

    assert result is False
    await db_session.refresh(content)
    assert content.review_status == ReviewStatus.PENDING


@pytest.mark.asyncio
async def test_auto_approve_triggers_enqueue(db_session):
    """After auto-approve, enqueue_content_background is called."""
    await _create_bot_chat(db_session)
    await _create_rule(
        db_session,
        name="enqueue_trigger_rule",
        match_conditions={"platform": "bilibili"},
        approval_required=False,
    )
    content = await _create_content(
        db_session,
        platform=Platform.BILIBILI,
        review_status=ReviewStatus.PENDING,
    )
    await db_session.commit()

    with patch(
        "app.services.distribution.scheduler.enqueue_content_background",
        new_callable=AsyncMock,
    ) as mock_enqueue:
        engine = DistributionEngine(db_session)
        await engine.auto_approve_if_eligible(content)

    mock_enqueue.assert_awaited_once_with(content.id)


# --- refresh_queue_by_rules tests ---


@pytest.mark.asyncio
async def test_refresh_queue_reverts_invalid_auto_approve(db_session):
    """AUTO_APPROVED content no longer matching → reverts to PENDING."""
    await _create_bot_chat(db_session)
    await _create_rule(
        db_session,
        name="revert_rule",
        match_conditions={"platform": "twitter"},
        approval_required=False,
    )
    content = await _create_content(
        db_session,
        platform=Platform.BILIBILI,
        review_status=ReviewStatus.AUTO_APPROVED,
        status=ContentStatus.PARSE_SUCCESS,
    )
    await db_session.commit()

    engine = DistributionEngine(db_session)
    await engine.refresh_queue_by_rules()

    await db_session.refresh(content)
    assert content.review_status == ReviewStatus.PENDING


@pytest.mark.asyncio
async def test_refresh_queue_promotes_pending_to_auto_approved(db_session):
    """PENDING content now matching auto_approve → promotes to AUTO_APPROVED."""
    await _create_bot_chat(db_session)
    await _create_rule(
        db_session,
        name="promote_rule",
        match_conditions={"platform": "bilibili"},
        approval_required=False,
    )
    content = await _create_content(
        db_session,
        platform=Platform.BILIBILI,
        review_status=ReviewStatus.PENDING,
        status=ContentStatus.PARSE_SUCCESS,
    )
    await db_session.commit()

    engine = DistributionEngine(db_session)
    await engine.refresh_queue_by_rules()

    await db_session.refresh(content)
    assert content.review_status == ReviewStatus.AUTO_APPROVED
    assert "auto-approved" in (content.review_note or "").lower()
