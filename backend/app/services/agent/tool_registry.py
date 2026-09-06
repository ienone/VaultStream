from __future__ import annotations

from dataclasses import dataclass, field
from enum import Enum
from typing import Any, Awaitable, Callable, Dict, Type

from pydantic import BaseModel, ValidationError
from sqlalchemy.ext.asyncio import AsyncSession


@dataclass
class AgentToolContext:
    db: AsyncSession
    app: Any | None = None
    run_id: str | None = None
    session_id: str | None = None
    confirmed: bool = False


AgentToolHandler = Callable[[Dict[str, Any], AgentToolContext], Awaitable[Dict[str, Any]]]


class AgentToolPermission(str, Enum):
    READ = "read"
    WRITE = "write"
    EXTERNAL_SIDE_EFFECT = "external_side_effect"
    DANGEROUS = "dangerous"


class AgentToolError(Exception):
    """Structured tool error sent back to the model and API clients."""

    def __init__(
        self,
        *,
        error_code: str,
        message: str,
        retryable: bool = False,
        details: Dict[str, Any] | None = None,
        suggested_fix: str | None = None,
    ) -> None:
        super().__init__(message)
        self.error_code = error_code
        self.message = message
        self.retryable = retryable
        self.details = details or {}
        self.suggested_fix = suggested_fix

    def to_payload(self) -> Dict[str, Any]:
        return {
            "error_code": self.error_code,
            "message": self.message,
            "retryable": self.retryable,
            "details": self.details,
            "suggested_fix": self.suggested_fix,
        }


@dataclass
class AgentToolSpec:
    name: str
    description: str
    args_schema: Dict[str, Any]
    result_schema: Dict[str, Any]
    handler: AgentToolHandler
    permission_level: AgentToolPermission = AgentToolPermission.READ
    permissions: list[str] = field(default_factory=list)
    args_model: Type[BaseModel] | None = None

    @property
    def requires_confirmation(self) -> bool:
        return self.permission_level in {
            AgentToolPermission.WRITE,
            AgentToolPermission.EXTERNAL_SIDE_EFFECT,
            AgentToolPermission.DANGEROUS,
        }

    @property
    def risk_level(self) -> str:
        return self.permission_level.value


@dataclass
class AgentToolRegistry:
    _tools: Dict[str, AgentToolSpec] = field(default_factory=dict)

    def register(
        self,
        *,
        name: str,
        description: str,
        args_schema: Dict[str, Any] | None = None,
        result_schema: Dict[str, Any] | None = None,
        args_model: Type[BaseModel] | None = None,
        permission_level: AgentToolPermission | str = AgentToolPermission.READ,
        permissions: list[str] | None = None,
        handler: AgentToolHandler,
    ) -> None:
        if name in self._tools:
            raise ValueError(f"Tool already registered: {name}")
        if isinstance(permission_level, str):
            permission_level = AgentToolPermission(permission_level)
        if args_model is not None:
            args_schema = args_model.model_json_schema()
        self._tools[name] = AgentToolSpec(
            name=name,
            description=description,
            args_schema=args_schema or {"type": "object", "properties": {}},
            result_schema=result_schema or {"type": "object"},
            handler=handler,
            permission_level=permission_level,
            permissions=list(permissions or []),
            args_model=args_model,
        )

    def list_specs(self) -> list[AgentToolSpec]:
        return list(self._tools.values())

    def has_tool(self, name: str) -> bool:
        return name in self._tools

    def get(self, name: str) -> AgentToolSpec:
        spec = self._tools.get(name)
        if spec is None:
            raise AgentToolError(
                error_code="agent_tool_not_found",
                message=f"Unknown tool: {name}",
                retryable=False,
                suggested_fix="Use one of the tools returned by /agent/tools.",
            )
        return spec

    def validate_args(self, name: str, args: Dict[str, Any]) -> Dict[str, Any]:
        spec = self.get(name)
        try:
            if spec.args_model is not None:
                return spec.args_model.model_validate(args or {}).model_dump(exclude_none=True)
            return args or {}
        except ValidationError as exc:
            raise AgentToolError(
                error_code="agent_tool_invalid_args",
                message="Tool arguments failed schema validation",
                retryable=True,
                details={
                    "validation_errors": exc.errors(
                        include_url=False,
                        include_context=False,
                        include_input=False,
                    )
                },
                suggested_fix="Regenerate arguments from the tool JSON schema and required fields.",
            ) from exc

    async def invoke(self, name: str, args: Dict[str, Any], context: AgentToolContext) -> Dict[str, Any]:
        spec = self.get(name)
        args = self.validate_args(name, args)

        try:
            return await spec.handler(args, context)
        except AgentToolError:
            raise
        except ValueError as exc:
            raise AgentToolError(
                error_code="agent_tool_invalid_args",
                message=str(exc),
                retryable=True,
                suggested_fix="Inspect the tool schema and provide complete, valid arguments.",
            ) from exc
