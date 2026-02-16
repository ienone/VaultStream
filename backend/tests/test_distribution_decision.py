import pytest

from app.distribution.decision import (
    DECISION_FILTERED,
    DECISION_PENDING_REVIEW,
    DECISION_WILL_PUSH,
    check_match_conditions,
    evaluate_target_decision,
)
from app.models import BotChat, Content, DistributionRule, Platform, ReviewStatus


@pytest.mark.asyncio
async def test_check_match_conditions_tags_case_insensitive():
    content = Content(
        platform=Platform.WEIBO,
        tags=["Tech", "AI"],
        is_nsfw=False,
        review_status=ReviewStatus.APPROVED,
    )
    conditions = {
        "tags": ["tech"],
        "tags_match_mode": "any",
        "tags_exclude": ["politics"],
    }

    decision = check_match_conditions(content, conditions)
    assert decision.bucket == DECISION_WILL_PUSH


@pytest.mark.asyncio
async def test_separate_channel_without_route_fallbacks_to_block():
    content = Content(
        platform=Platform.WEIBO,
        tags=["test"],
        is_nsfw=True,
        review_status=ReviewStatus.APPROVED,
    )
    rule = DistributionRule(
        name="nsfw-separate",
        match_conditions={},
        nsfw_policy="separate_channel",
        approval_required=False,
        enabled=True,
    )
    chat = BotChat(chat_id="-10001", enabled=True)

    decision = evaluate_target_decision(content=content, rule=rule, bot_chat=chat)

    assert decision.bucket == DECISION_FILTERED
    assert decision.reason_code == "nsfw_separate_unconfigured_blocked"


@pytest.mark.asyncio
async def test_separate_channel_with_route_will_push():
    content = Content(
        platform=Platform.WEIBO,
        tags=["test"],
        is_nsfw=True,
        review_status=ReviewStatus.APPROVED,
    )
    rule = DistributionRule(
        name="nsfw-separate-routed",
        match_conditions={},
        nsfw_policy="separate_channel",
        approval_required=False,
        enabled=True,
    )
    chat = BotChat(chat_id="-10001", nsfw_chat_id="-10099", enabled=True)

    decision = evaluate_target_decision(content=content, rule=rule, bot_chat=chat)

    assert decision.bucket == DECISION_WILL_PUSH
    assert decision.target_id == "-10099"
    assert decision.nsfw_routing_result is not None


@pytest.mark.asyncio
async def test_approval_required_maps_to_pending_review():
    content = Content(
        platform=Platform.WEIBO,
        tags=["test"],
        is_nsfw=False,
        review_status=ReviewStatus.PENDING,
    )
    rule = DistributionRule(
        name="approval-required",
        match_conditions={},
        nsfw_policy="allow",
        approval_required=True,
        enabled=True,
    )
    chat = BotChat(chat_id="-10001", enabled=True)

    decision = evaluate_target_decision(content=content, rule=rule, bot_chat=chat)

    assert decision.bucket == DECISION_PENDING_REVIEW
    assert decision.reason_code == "approval_required"
