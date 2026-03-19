from app.services.agent.tool_registry import AgentToolRegistry
from .favorites import register_favorites_tool
from .groups import register_groups_tool
from .push import register_push_tool
from .rules import register_rules_tool
from .search import register_search_tool
from .stats import register_stats_tool
from .tags import register_tags_tool


def register_builtin_tools(registry: AgentToolRegistry) -> None:
    register_search_tool(registry)
    register_groups_tool(registry)
    register_favorites_tool(registry)
    register_rules_tool(registry)
    register_tags_tool(registry)
    register_stats_tool(registry)
    register_push_tool(registry)
