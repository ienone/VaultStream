import pytest
from unittest.mock import AsyncMock, patch

from sqlalchemy import delete

from fastapi import HTTPException

from app.models.content import Content
from app.models.base import Platform, ContentStatus, ReviewStatus
from app.models.distribution import DistributionRule, DistributionTarget
from app.models.bot import BotConfig, BotChat, BotChatType, BotConfigPlatform
from app.schemas.distribution import (
    DistributionRuleCreate,
    DistributionRuleUpdate,
    DistributionTargetCreate,
    DistributionTargetUpdate,
)
from app.core.time_utils import utcnow
from app.services.distribution_rule_service import DistributionRuleService


@pytest.fixture(autouse=True)
def mock_event_bus():
    with patch("app.core.events.event_bus.publish", new_callable=AsyncMock) as mock:
        yield mock


@pytest.fixture(autouse=True)
def mock_backfill():
    with patch(
        "app.services.distribution_rule_service.mark_historical_parse_success_as_pushed_for_rule",
        new_callable=AsyncMock,
        return_value=0,
    ) as mock:
        yield mock


@pytest.fixture(autouse=True)
async def clean_tables(db_session):
    yield
    for model in (DistributionTarget, DistributionRule, BotChat, BotConfig, Content):
        await db_session.execute(delete(model))
    await db_session.commit()


def _rule_create(name="test_rule", **kwargs):
    defaults = dict(
        name=name,
        match_conditions={"platform": "twitter"},
        enabled=True,
        priority=0,
        nsfw_policy="block",
    )
    defaults.update(kwargs)
    return DistributionRuleCreate(**defaults)


async def _make_chat(db_session) -> BotChat:
    cfg = BotConfig(platform=BotConfigPlatform.TELEGRAM, name="svc_bot", enabled=True)
    db_session.add(cfg)
    await db_session.flush()

    chat = BotChat(
        bot_config_id=cfg.id,
        chat_id="svc_chat_1",
        chat_type=BotChatType.CHANNEL,
        enabled=True,
        is_accessible=True,
    )
    db_session.add(chat)
    await db_session.flush()
    return chat


# ========================
# Rule CRUD
# ========================

@pytest.mark.asyncio
async def test_create_rule(db_session):
    svc = DistributionRuleService(db_session)
    rule = await svc.create_rule(_rule_create("create_happy"))
    assert rule.id is not None
    assert rule.name == "create_happy"


@pytest.mark.asyncio
async def test_create_rule_duplicate_name(db_session):
    svc = DistributionRuleService(db_session)
    await svc.create_rule(_rule_create("dup_name"))

    with pytest.raises(HTTPException) as exc_info:
        await svc.create_rule(_rule_create("dup_name"))
    assert exc_info.value.status_code == 400


@pytest.mark.asyncio
async def test_list_rules(db_session):
    svc = DistributionRuleService(db_session)
    await svc.create_rule(_rule_create("list_r1"))
    await svc.create_rule(_rule_create("list_r2"))

    rules = await svc.list_rules()
    names = {r.name for r in rules}
    assert "list_r1" in names
    assert "list_r2" in names


@pytest.mark.asyncio
async def test_get_rule(db_session):
    svc = DistributionRuleService(db_session)
    created = await svc.create_rule(_rule_create("get_me"))

    found = await svc.get_rule(created.id)
    assert found.name == "get_me"


@pytest.mark.asyncio
async def test_get_rule_not_found(db_session):
    svc = DistributionRuleService(db_session)
    with pytest.raises(HTTPException) as exc_info:
        await svc.get_rule(999999)
    assert exc_info.value.status_code == 404


@pytest.mark.asyncio
async def test_update_rule(db_session):
    svc = DistributionRuleService(db_session)
    rule = await svc.create_rule(_rule_create("upd_rule"))

    updated = await svc.update_rule(
        rule.id,
        DistributionRuleUpdate(description="new desc", priority=5),
    )
    assert updated.description == "new desc"
    assert updated.priority == 5


@pytest.mark.asyncio
async def test_delete_rule(db_session):
    svc = DistributionRuleService(db_session)
    rule = await svc.create_rule(_rule_create("del_rule"))

    await svc.delete_rule(rule.id)
    with pytest.raises(HTTPException) as exc_info:
        await svc.get_rule(rule.id)
    assert exc_info.value.status_code == 404


# ========================
# Target CRUD
# ========================

@pytest.mark.asyncio
async def test_list_rule_targets(db_session):
    svc = DistributionRuleService(db_session)
    rule = await svc.create_rule(_rule_create("tgt_list"))
    chat = await _make_chat(db_session)

    await svc.create_rule_target(rule.id, DistributionTargetCreate(bot_chat_id=chat.id))

    targets = await svc.list_rule_targets(rule.id)
    assert len(targets) == 1
    assert targets[0].bot_chat_id == chat.id


@pytest.mark.asyncio
async def test_create_rule_target(db_session, mock_backfill):
    svc = DistributionRuleService(db_session)
    rule = await svc.create_rule(_rule_create("tgt_create"))
    chat = await _make_chat(db_session)

    target, inserted = await svc.create_rule_target(
        rule.id,
        DistributionTargetCreate(bot_chat_id=chat.id),
    )
    assert target.id is not None
    assert target.rule_id == rule.id
    assert inserted == 0
    mock_backfill.assert_called_once()


@pytest.mark.asyncio
async def test_create_rule_target_chat_not_found(db_session):
    svc = DistributionRuleService(db_session)
    rule = await svc.create_rule(_rule_create("tgt_no_chat"))

    with pytest.raises(HTTPException) as exc_info:
        await svc.create_rule_target(
            rule.id,
            DistributionTargetCreate(bot_chat_id=999999),
        )
    assert exc_info.value.status_code == 404


@pytest.mark.asyncio
async def test_create_rule_target_duplicate(db_session):
    svc = DistributionRuleService(db_session)
    rule = await svc.create_rule(_rule_create("tgt_dup"))
    chat = await _make_chat(db_session)

    await svc.create_rule_target(rule.id, DistributionTargetCreate(bot_chat_id=chat.id))

    with pytest.raises(HTTPException) as exc_info:
        await svc.create_rule_target(rule.id, DistributionTargetCreate(bot_chat_id=chat.id))
    assert exc_info.value.status_code == 400


@pytest.mark.asyncio
async def test_update_rule_target(db_session):
    svc = DistributionRuleService(db_session)
    rule = await svc.create_rule(_rule_create("tgt_upd"))
    chat = await _make_chat(db_session)

    target, _ = await svc.create_rule_target(
        rule.id,
        DistributionTargetCreate(bot_chat_id=chat.id, merge_forward=False),
    )

    updated = await svc.update_rule_target(
        rule.id,
        target.id,
        DistributionTargetUpdate(merge_forward=True, summary="updated"),
    )
    assert updated.merge_forward is True
    assert updated.summary == "updated"


@pytest.mark.asyncio
async def test_delete_rule_target(db_session):
    svc = DistributionRuleService(db_session)
    rule = await svc.create_rule(_rule_create("tgt_del"))
    chat = await _make_chat(db_session)

    target, _ = await svc.create_rule_target(
        rule.id,
        DistributionTargetCreate(bot_chat_id=chat.id),
    )

    await svc.delete_rule_target(rule.id, target.id)
    targets = await svc.list_rule_targets(rule.id)
    assert len(targets) == 0


@pytest.mark.asyncio
async def test_delete_rule_target_not_found(db_session):
    svc = DistributionRuleService(db_session)
    rule = await svc.create_rule(_rule_create("tgt_del_nf"))

    with pytest.raises(HTTPException) as exc_info:
        await svc.delete_rule_target(rule.id, 999999)
    assert exc_info.value.status_code == 404


# ========================
# _resolve_preview_decision
# ========================

@pytest.mark.asyncio
async def test_resolve_preview_no_chats(db_session):
    svc = DistributionRuleService(db_session)
    rule = await svc.create_rule(_rule_create("prev_no_chats"))

    content = Content(
        title="No Chat Content",
        url="http://nochat.com",
        platform=Platform.TWITTER,
        status=ContentStatus.PARSE_SUCCESS,
        created_at=utcnow(),
    )
    db_session.add(content)
    await db_session.flush()

    decision = svc._resolve_preview_decision(content=content, rule=rule, chats=[])
    assert decision.bucket == "filtered"
    assert decision.reason_code == "no_enabled_targets"


@pytest.mark.asyncio
async def test_resolve_preview_will_push(db_session):
    svc = DistributionRuleService(db_session)
    rule = await svc.create_rule(_rule_create(
        "prev_push",
        match_conditions={"platform": "twitter"},
        nsfw_policy="block",
        approval_required=False,
    ))

    chat = await _make_chat(db_session)

    content = Content(
        title="Push Me",
        url="http://pushme.com",
        platform=Platform.TWITTER,
        status=ContentStatus.PARSE_SUCCESS,
        is_nsfw=False,
        tags=["tech"],
        review_status=ReviewStatus.APPROVED,
        created_at=utcnow(),
    )
    db_session.add(content)
    await db_session.flush()

    decision = svc._resolve_preview_decision(content=content, rule=rule, chats=[chat])
    assert decision.bucket == "will_push"
