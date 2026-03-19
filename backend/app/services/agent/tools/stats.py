from __future__ import annotations

from typing import Any, Dict

from sqlalchemy import func, select

from app.models import BotChat, DistributionRule
from app.services.agent.tool_registry import AgentToolContext, AgentToolRegistry
from app.services.dashboard_service import build_distribution_stats, build_parse_stats


def register_stats_tool(registry: AgentToolRegistry) -> None:
    registry.register(
        name="get_stats",
        description="获取系统解析/分发统计。",
        args_schema={
            "include_rule_breakdown": {"type": "boolean", "required": False, "default": False},
        },
        handler=_get_stats_tool,
    )


async def _get_stats_tool(args: Dict[str, Any], context: AgentToolContext) -> Dict[str, Any]:
    include_rule_breakdown = bool(args.get("include_rule_breakdown", False))

    parse_stats = await build_parse_stats(context.db)
    distribution_stats, rule_breakdown = await build_distribution_stats(
        context.db,
        include_rule_breakdown=include_rule_breakdown,
    )

    enabled_rules = (
        await context.db.execute(
            select(func.count(DistributionRule.id)).where(DistributionRule.enabled == True)  # noqa: E712
        )
    ).scalar() or 0
    enabled_groups = (
        await context.db.execute(
            select(func.count(BotChat.id)).where(BotChat.enabled == True)  # noqa: E712
        )
    ).scalar() or 0

    return {
        "parse": parse_stats,
        "distribution": distribution_stats,
        "enabled_rules": int(enabled_rules),
        "enabled_groups": int(enabled_groups),
        "rule_breakdown": rule_breakdown if include_rule_breakdown else {},
    }
