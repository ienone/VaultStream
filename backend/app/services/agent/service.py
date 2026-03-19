from __future__ import annotations

import re
from dataclasses import dataclass
from typing import Any, Dict, Tuple

from app.services.agent.tool_registry import AgentToolContext, AgentToolRegistry
from app.services.agent.tools import register_builtin_tools

_REGISTRY: AgentToolRegistry | None = None


def get_tool_registry() -> AgentToolRegistry:
    global _REGISTRY
    if _REGISTRY is None:
        registry = AgentToolRegistry()
        register_builtin_tools(registry)
        _REGISTRY = registry
    return _REGISTRY


def _infer_tool_from_message(message: str) -> Tuple[str, Dict[str, Any]]:
    text = (message or "").strip()
    lower = text.lower()
    if not text:
        return "search_content", {"query": ""}

    if "同步" in text and any(p in lower for p in ("zhihu", "知乎", "xiaohongshu", "小红书", "twitter", "推特", "x ")):
        if "zhihu" in lower or "知乎" in text:
            return "import_favorites", {"platform": "zhihu"}
        if "xiaohongshu" in lower or "小红书" in text:
            return "import_favorites", {"platform": "xiaohongshu"}
        return "import_favorites", {"platform": "twitter"}

    if any(token in text for token in ("统计", "看板", "dashboard", "概览")):
        return "get_stats", {}

    if any(token in text for token in ("创建规则", "新建规则", "自动推送", "自动发")):
        tags = re.findall(r"#([\w\-\u4e00-\u9fff]+)", text)
        platform = None
        for key, value in (
            ("bilibili", "bilibili"),
            ("b站", "bilibili"),
            ("zhihu", "zhihu"),
            ("知乎", "zhihu"),
            ("twitter", "twitter"),
            ("xiaohongshu", "xiaohongshu"),
            ("小红书", "xiaohongshu"),
            ("weibo", "weibo"),
            ("微博", "weibo"),
            ("douyin", "douyin"),
            ("抖音", "douyin"),
        ):
            if key in lower or key in text:
                platform = value
                break

        name = f"Agent规则-{text[:16]}"
        return "create_rule", {
            "name": name,
            "platform": platform,
            "tags": tags,
            "approval_required": False,
        }

    if any(token in text for token in ("标签", "tag")) and any(token in text for token in ("添加", "增加", "移除", "删除")):
        content_match = re.search(r"(?:内容|content|id)[^\d]{0,6}(\d+)", lower)
        tag_tokens = re.findall(r"#([\w\-\u4e00-\u9fff]+)", text)
        if content_match:
            cid = int(content_match.group(1))
            if any(token in text for token in ("移除", "删除")):
                return "manage_tags", {"content_id": cid, "remove_tags": tag_tokens}
            return "manage_tags", {"content_id": cid, "add_tags": tag_tokens}

    if any(token in text for token in ("推送", "发送", "批量")) and any(ch.isdigit() for ch in text):
        ids = [int(x) for x in re.findall(r"\d+", text)]
        if ids:
            return "push_batch", {"content_ids": ids}

    if any(token in text for token in ("群", "组", "频道", "group", "groups")):
        return "list_groups", {}

    return "search_content", {"query": text, "top_k": 10}


@dataclass
class AgentRunResult:
    tool: str
    result: Dict[str, Any]


async def run_agent_message(message: str, context: AgentToolContext) -> AgentRunResult:
    tool_name, args = _infer_tool_from_message(message)
    registry = get_tool_registry()
    result = await registry.invoke(tool_name, args, context)
    return AgentRunResult(tool=tool_name, result=result)
