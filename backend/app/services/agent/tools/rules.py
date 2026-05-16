from __future__ import annotations

from datetime import datetime
from typing import Any, Dict, Optional

from pydantic import BaseModel, Field

from app.models import Platform
from app.schemas.distribution import DistributionRuleCreate, DistributionTargetCreate
from app.services.agent.tool_registry import AgentToolContext, AgentToolRegistry
from app.services.distribution_rule_service import DistributionRuleService
from app.utils.tags import normalize_tags


class CreateRuleArgs(BaseModel):
    name: str = Field(min_length=1, max_length=200)
    platform: Optional[str] = None
    tags: list[str] = Field(default_factory=list)
    tags_match_mode: str = Field(default="any", pattern="^(any|all)$")
    approval_required: bool = False
    target_bot_chat_id: Optional[int] = None


def register_rules_tool(registry: AgentToolRegistry) -> None:
    registry.register(
        name="create_rule",
        description="创建分发规则，可选绑定目标群组。",
        args_model=CreateRuleArgs,
        result_schema={
            "type": "object",
            "required": ["rule_id", "name", "match_conditions", "approval_required", "enabled", "target"],
            "properties": {
                "rule_id": {"type": "integer"},
                "name": {"type": "string"},
                "match_conditions": {"type": "object"},
                "approval_required": {"type": "boolean"},
                "enabled": {"type": "boolean"},
                "target": {"type": ["object", "null"]},
            },
        },
        permission_level="write",
        permissions=["distribution_rules:write"],
        handler=_create_rule_tool,
    )


def _pick_platform(raw: Any) -> str | None:
    if raw is None:
        return None
    value = str(raw).strip().lower()
    if not value:
        return None
    valid = {item.value for item in Platform}
    if value not in valid:
        raise ValueError(f"invalid platform: {value}")
    return value


async def _create_rule_tool(args: Dict[str, Any], context: AgentToolContext) -> Dict[str, Any]:
    name = str(args.get("name") or "").strip()
    if not name:
        raise ValueError("name is required")

    platform = _pick_platform(args.get("platform"))
    tags = normalize_tags(args.get("tags") or [])
    tags_match_mode = str(args.get("tags_match_mode") or "any").strip().lower() or "any"
    if tags_match_mode not in {"any", "all"}:
        raise ValueError("tags_match_mode must be any or all")
    approval_required = bool(args.get("approval_required", False))
    target_bot_chat_id = args.get("target_bot_chat_id")

    match_conditions: Dict[str, Any] = {}
    if platform:
        match_conditions["platform"] = platform
    if tags:
        match_conditions["tags"] = tags
        match_conditions["tags_match_mode"] = tags_match_mode

    service = DistributionRuleService(context.db)
    rule = await service.create_rule(
        DistributionRuleCreate(
            name=name,
            description=f"Created by agent at {datetime.utcnow().isoformat()}",
            match_conditions=match_conditions,
            enabled=True,
            approval_required=approval_required,
        )
    )

    target = None
    if target_bot_chat_id is not None:
        target, _ = await service.create_rule_target(
            rule.id,
            DistributionTargetCreate(bot_chat_id=int(target_bot_chat_id)),
        )

    return {
        "rule_id": rule.id,
        "name": rule.name,
        "match_conditions": rule.match_conditions or {},
        "approval_required": bool(rule.approval_required),
        "enabled": bool(rule.enabled),
        "target": (
            {
                "target_id": target.id,
                "bot_chat_id": target.bot_chat_id,
                "enabled": bool(target.enabled),
            }
            if target
            else None
        ),
    }
