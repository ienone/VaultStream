"""
Tests for app.services.dashboard_service — pure-function + DB integration tests.
"""
import pytest
import uuid
from datetime import datetime
from unittest.mock import AsyncMock, patch

from app.models import (
    Content,
    ContentQueueItem,
    ContentStatus,
    QueueItemStatus,
    DistributionRule,
    BotChat,
    BotConfig,
    BotChatType,
    BotConfigPlatform,
    Platform,
)
from app.services.dashboard_service import (
    classify_distribution_status,
    empty_distribution_bucket,
    build_parse_stats,
    build_distribution_stats,
)


@pytest.fixture(autouse=True)
def mock_event_bus():
    with patch("app.core.events.event_bus.publish", new_callable=AsyncMock) as mock:
        yield mock


# ── classify_distribution_status ──────────────────────────────────


def test_classify_success():
    assert classify_distribution_status(QueueItemStatus.SUCCESS, None) == "pushed"


def test_classify_scheduled():
    assert classify_distribution_status(QueueItemStatus.SCHEDULED, None) == "will_push"


def test_classify_processing():
    assert classify_distribution_status(QueueItemStatus.PROCESSING, None) == "will_push"


def test_classify_failed():
    assert classify_distribution_status(QueueItemStatus.FAILED, None) == "filtered"


def test_classify_failed_retrying():
    assert classify_distribution_status(QueueItemStatus.FAILED, datetime(2025, 1, 1)) == "will_push"


# ── empty_distribution_bucket ─────────────────────────────────────


def test_empty_distribution_bucket():
    bucket = empty_distribution_bucket()
    assert bucket == {"will_push": 0, "filtered": 0, "pushed": 0, "total": 0}
    # Ensure each call returns a new dict
    assert empty_distribution_bucket() is not bucket


# ── build_parse_stats (DB) ────────────────────────────────────────


@pytest.mark.asyncio
async def test_build_parse_stats(db_session):
    uid = uuid.uuid4().hex[:8]
    contents = [
        Content(platform=Platform.BILIBILI, url=f"https://b.com/1_{uid}", canonical_url=f"b1-parse-{uid}", status=ContentStatus.UNPROCESSED),
        Content(platform=Platform.BILIBILI, url=f"https://b.com/2_{uid}", canonical_url=f"b2-parse-{uid}", status=ContentStatus.UNPROCESSED),
        Content(platform=Platform.BILIBILI, url=f"https://b.com/3_{uid}", canonical_url=f"b3-parse-{uid}", status=ContentStatus.PARSE_SUCCESS),
        Content(platform=Platform.BILIBILI, url=f"https://b.com/4_{uid}", canonical_url=f"b4-parse-{uid}", status=ContentStatus.PARSE_FAILED),
    ]
    db_session.add_all(contents)
    await db_session.commit()

    stats = await build_parse_stats(db_session)
    assert stats["unprocessed"] >= 2
    assert stats["parse_success"] >= 1
    assert stats["parse_failed"] >= 1
    assert stats["total"] >= 4


# ── build_distribution_stats (DB) ─────────────────────────────────


async def _setup_distribution_data(db_session):
    """Helper: create BotConfig → BotChat → Rule → Content → QueueItems."""
    uid = uuid.uuid4().hex[:8]

    bot_config = BotConfig(platform=BotConfigPlatform.TELEGRAM, name=f"dash_bot_{uid}")
    db_session.add(bot_config)
    await db_session.flush()

    bot_chat = BotChat(
        bot_config_id=bot_config.id,
        chat_id=f"dash_chat_1_{uid}",
        chat_type=BotChatType.CHANNEL,
        enabled=True,
        is_accessible=True,
    )
    db_session.add(bot_chat)
    await db_session.flush()

    rule = DistributionRule(
        name=f"dash_rule_{uid}",
        match_conditions={"platform": ["bilibili"]},
    )
    db_session.add(rule)
    await db_session.flush()

    content = Content(
        platform=Platform.BILIBILI,
        url=f"https://b.com/dist_{uid}",
        canonical_url=f"dist-dash-{uid}",
        status=ContentStatus.PARSE_SUCCESS,
    )
    db_session.add(content)
    await db_session.flush()

    items = [
        ContentQueueItem(
            content_id=content.id,
            rule_id=rule.id,
            bot_chat_id=bot_chat.id,
            target_platform="telegram",
            target_id=f"dash_chat_1_{uid}",
            status=QueueItemStatus.SUCCESS,
        ),
    ]
    # Need unique bot_chat per queue item due to unique constraint
    for i, status in enumerate([QueueItemStatus.SCHEDULED, QueueItemStatus.FAILED], start=2):
        chat = BotChat(
            bot_config_id=bot_config.id,
            chat_id=f"dash_chat_{i}_{uid}",
            chat_type=BotChatType.CHANNEL,
            enabled=True,
            is_accessible=True,
        )
        db_session.add(chat)
        await db_session.flush()
        items.append(
            ContentQueueItem(
                content_id=content.id,
                rule_id=rule.id,
                bot_chat_id=chat.id,
                target_platform="telegram",
                target_id=f"dash_chat_{i}_{uid}",
                status=status,
                next_attempt_at=datetime(2025, 1, 1) if status == QueueItemStatus.FAILED else None,
            )
        )

    db_session.add_all(items)
    await db_session.commit()
    return rule.id


@pytest.mark.asyncio
async def test_build_distribution_stats(db_session):
    await _setup_distribution_data(db_session)

    dist_stats, rule_breakdown = await build_distribution_stats(db_session)
    assert dist_stats["pushed"] >= 1
    assert dist_stats["will_push"] >= 1
    assert dist_stats["total"] >= 3
    assert rule_breakdown == {}


@pytest.mark.asyncio
async def test_build_distribution_stats_with_rule_breakdown(db_session):
    rule_id = await _setup_distribution_data(db_session)

    dist_stats, rule_breakdown = await build_distribution_stats(
        db_session, include_rule_breakdown=True
    )
    assert dist_stats["total"] >= 3
    key = str(rule_id)
    assert key in rule_breakdown
    assert rule_breakdown[key]["total"] >= 3
