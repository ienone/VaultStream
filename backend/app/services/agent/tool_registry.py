from __future__ import annotations

from dataclasses import dataclass, field
from typing import Any, Awaitable, Callable, Dict

from sqlalchemy.ext.asyncio import AsyncSession


@dataclass
class AgentToolContext:
    db: AsyncSession
    app: Any | None = None


AgentToolHandler = Callable[[Dict[str, Any], AgentToolContext], Awaitable[Dict[str, Any]]]


@dataclass
class AgentToolSpec:
    name: str
    description: str
    args_schema: Dict[str, Any]
    handler: AgentToolHandler


@dataclass
class AgentToolRegistry:
    _tools: Dict[str, AgentToolSpec] = field(default_factory=dict)

    def register(
        self,
        *,
        name: str,
        description: str,
        args_schema: Dict[str, Any],
        handler: AgentToolHandler,
    ) -> None:
        if name in self._tools:
            raise ValueError(f"Tool already registered: {name}")
        self._tools[name] = AgentToolSpec(
            name=name,
            description=description,
            args_schema=args_schema,
            handler=handler,
        )

    def list_specs(self) -> list[AgentToolSpec]:
        return list(self._tools.values())

    def has_tool(self, name: str) -> bool:
        return name in self._tools

    async def invoke(self, name: str, args: Dict[str, Any], context: AgentToolContext) -> Dict[str, Any]:
        spec = self._tools.get(name)
        if spec is None:
            raise KeyError(f"Unknown tool: {name}")
        return await spec.handler(args, context)
