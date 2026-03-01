"""
统一分发判定模块。

单一规则：相同输入必须得到相同分发决策。
"""
from __future__ import annotations

from dataclasses import dataclass
from typing import Any, Dict, Optional

from app.models import BotChat, Content, DistributionRule, ReviewStatus
from app.utils.tags import normalize_tags


DECISION_WILL_PUSH = "will_push"
DECISION_FILTERED = "filtered"
DECISION_PENDING_REVIEW = "pending_review"
DECISION_PUSHED = "pushed"


@dataclass
class DistributionDecision:
    bucket: str
    reason_code: Optional[str] = None
    reason: Optional[str] = None
    target_id: Optional[str] = None
    nsfw_routing_result: Optional[Dict[str, Any]] = None


def check_match_conditions(content: Content, conditions: Dict[str, Any]) -> DistributionDecision:
    conditions = conditions or {}

    platform = conditions.get("platform")
    if platform and platform != content.platform.value:
        return DistributionDecision(
            bucket=DECISION_FILTERED,
            reason_code="platform_mismatch",
            reason=f"平台不匹配: 需要 {platform}, 实际 {content.platform.value}",
        )

    content_tags = normalize_tags(content.tags or [], lower=True)

    exclude_tags = normalize_tags(conditions.get("tags_exclude", []), lower=True)
    if exclude_tags:
        hit_exclude = [tag for tag in exclude_tags if tag in content_tags]
        if hit_exclude:
            return DistributionDecision(
                bucket=DECISION_FILTERED,
                reason_code="tags_excluded",
                reason=f"包含排除标签: {hit_exclude}",
            )

    required_tags = normalize_tags(conditions.get("tags", []), lower=True)
    if required_tags:
        tags_match_mode = str(conditions.get("tags_match_mode", "any")).strip().lower() or "any"
        if tags_match_mode == "all":
            if not all(tag in content_tags for tag in required_tags):
                return DistributionDecision(
                    bucket=DECISION_FILTERED,
                    reason_code="tags_not_all_matched",
                    reason=f"标签不完全匹配: 需要全部 {required_tags}",
                )
        else:
            if not any(tag in content_tags for tag in required_tags):
                return DistributionDecision(
                    bucket=DECISION_FILTERED,
                    reason_code="tags_not_any_matched",
                    reason=f"标签不匹配: 需要任一 {required_tags}",
                )

    if "is_nsfw" in conditions and conditions["is_nsfw"] != content.is_nsfw:
        return DistributionDecision(
            bucket=DECISION_FILTERED,
            reason_code="nsfw_condition_mismatch",
            reason=f"NSFW状态不匹配: 规则要求 is_nsfw={conditions['is_nsfw']}",
        )

    return DistributionDecision(bucket=DECISION_WILL_PUSH)


def evaluate_target_decision(
    *,
    content: Content,
    rule: DistributionRule,
    bot_chat: Optional[BotChat],
    require_approval: bool = True,
) -> DistributionDecision:
    condition_decision = check_match_conditions(content, rule.match_conditions or {})
    if condition_decision.bucket == DECISION_FILTERED:
        return condition_decision

    target_id = bot_chat.chat_id if bot_chat else None
    nsfw_routing_result: Optional[Dict[str, Any]] = None

    if content.is_nsfw:
        nsfw_policy = str(rule.nsfw_policy or "block").strip().lower() or "block"
        if nsfw_policy == "block":
            return DistributionDecision(
                bucket=DECISION_FILTERED,
                reason_code="nsfw_blocked",
                reason="NSFW内容被阻止 (策略: block)",
            )

        if nsfw_policy == "separate_channel":
            routed_target = str(getattr(bot_chat, "nsfw_chat_id", "") or "").strip()
            if not routed_target:
                return DistributionDecision(
                    bucket=DECISION_FILTERED,
                    reason_code="nsfw_separate_unconfigured_blocked",
                    reason="NSFW分离路由未配置，按 block 处理",
                )

            target_id = routed_target
            nsfw_routing_result = {
                "policy": "separate_channel",
                "target_id": routed_target,
            }

    if require_approval and rule.approval_required:
        if content.review_status not in (ReviewStatus.APPROVED, ReviewStatus.AUTO_APPROVED):
            return DistributionDecision(
                bucket=DECISION_PENDING_REVIEW,
                reason_code="approval_required",
                reason=f"需要人工审批 (当前状态: {content.review_status.value})",
                target_id=target_id,
                nsfw_routing_result=nsfw_routing_result,
            )

    return DistributionDecision(
        bucket=DECISION_WILL_PUSH,
        reason_code="rule_matched",
        reason=None,
        target_id=target_id,
        nsfw_routing_result=nsfw_routing_result,
    )


def check_auto_approve_conditions(content: Content, conditions: Dict[str, Any]) -> bool:
    conditions = conditions or {}

    if "is_nsfw" in conditions and conditions["is_nsfw"] != content.is_nsfw:
        return False

    if "platform" in conditions and conditions["platform"] != content.platform.value:
        return False

    if "tags" in conditions:
        required_tags = normalize_tags(conditions.get("tags", []), lower=True)
        if required_tags:
            content_tags = normalize_tags(content.tags or [], lower=True)
            if not all(tag in content_tags for tag in required_tags):
                return False

    return True
