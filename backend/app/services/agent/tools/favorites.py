from __future__ import annotations

from typing import Any, Dict

from app.tasks.favorites_sync import FavoritesSyncTask
from app.services.agent.tool_registry import AgentToolContext, AgentToolRegistry


def register_favorites_tool(registry: AgentToolRegistry) -> None:
    registry.register(
        name="import_favorites",
        description="按平台触发一次收藏导入（zhihu/xiaohongshu/twitter）。",
        args_schema={
            "platform": {"type": "string", "required": True},
        },
        handler=_import_favorites_tool,
    )


async def _import_favorites_tool(args: Dict[str, Any], context: AgentToolContext) -> Dict[str, Any]:
    platform = str(args.get("platform") or "").strip().lower()
    if not platform:
        raise ValueError("platform is required")

    sync_task = None
    if context.app is not None:
        sync_task = getattr(context.app.state, "favorites_sync_task", None)
    if sync_task is None:
        sync_task = FavoritesSyncTask()

    result = await sync_task.sync_platform_by_name(platform)
    return {"platform": platform, "result": result}
