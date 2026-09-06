from __future__ import annotations

from typing import Any, Dict, Literal, Optional

import httpx
from pydantic import BaseModel, Field, field_validator, model_validator

from app.core.config import settings
from app.services.agent.tool_registry import (
    AgentToolContext,
    AgentToolError,
    AgentToolRegistry,
)


_BLOCKED_PREFIXES = (
    "/api/v1/agent",
    "/api/v1/events/subscribe",
)
_BINARY_PREFIXES = (
    "/api/v1/media/",
    "/api/v1/proxy/image",
)
_SAFE_METHODS = {"GET"}
_MUTATION_METHODS = {"POST", "PUT", "PATCH", "DELETE"}
_PUBLIC_METHODS = _SAFE_METHODS | _MUTATION_METHODS
_READ_ALLOWED_PREFIXES = (
    "/api/v1/actions",
    "/api/v1/contents",
    "/api/v1/cards",
    "/api/v1/pushed-records",
    "/api/v1/tags",
    "/api/v1/dashboard",
    "/api/v1/background-tasks",
    "/api/v1/discovery",
    "/api/v1/distribution-rules",
    "/api/v1/distribution",
    "/api/v1/targets",
    "/api/v1/render-config-presets",
    "/api/v1/distribution-queue",
    "/api/v1/bot",
    "/api/v1/bot-config",
    "/api/v1/storage/stats",
    "/api/v1/search/semantic",
    "/api/v1/settings",
    "/api/v1/favorites-sync",
    "/api/v1/health",
    "/api/v1/init-status",
)
_MUTATION_OPERATIONS = {
    ("PATCH", "/api/v1/contents/{content_id}"),
    ("POST", "/api/v1/cards/{card_id}/review"),
    ("POST", "/api/v1/cards/batch-review"),
}


class ApiCatalogArgs(BaseModel):
    prefix: Optional[str] = Field(default=None, description="只列出指定路径前缀下的 API，例如 /api/v1/contents。")
    include_mutations: bool = Field(default=True)


class ApiGetArgs(BaseModel):
    path: str = Field(description="API path, for example /api/v1/contents or /contents.")
    query: Dict[str, Any] = Field(default_factory=dict)
    max_items: int = Field(default=20, ge=1, le=100)
    max_chars: int = Field(default=12000, ge=1000, le=50000)

    @field_validator("path")
    @classmethod
    def _path_must_not_be_blank(cls, value: str) -> str:
        value = value.strip()
        if not value:
            raise ValueError("path is required")
        return value


class ApiMutationArgs(ApiGetArgs):
    method: Literal["POST", "PUT", "PATCH", "DELETE", "post", "put", "patch", "delete"]
    body: Dict[str, Any] = Field(default_factory=dict)
    reason: str = Field(description="说明这次变更的业务目的，展示给用户确认。", min_length=1)

    @model_validator(mode="after")
    def _operation_must_be_explicitly_allowed(self):
        _validate_method_and_path(self.method.upper(), _normalize_path(self.path))
        return self


def register_api_bridge_tools(registry: AgentToolRegistry) -> None:
    registry.register(
        name="api_catalog",
        description=(
            "列出 VaultStream 允许 Agent 复用的受控 API 能力目录。只包含核心 GUI 业务域，不暴露内部/二进制/Agent 自身接口。"
        ),
        args_model=ApiCatalogArgs,
        result_schema={"type": "object", "required": ["count", "endpoints"], "properties": {"endpoints": {"type": "array"}}},
        permission_level="read",
        permissions=["api:catalog:read"],
        handler=_api_catalog_tool,
    )
    registry.register(
        name="api_get",
        description=(
            "调用 VaultStream 受控 allowlist 内的 GET API，复用客户端同一套后端实现完成只读查询。"
            "适合内容列表/详情、发现源、队列、规则、Bot、设置、Dashboard 等读取操作。"
        ),
        args_model=ApiGetArgs,
        result_schema={"type": "object", "required": ["status_code", "data"], "properties": {"data": {"type": "object"}}},
        permission_level="read",
        permissions=["api:read"],
        handler=_api_get_tool,
    )
    registry.register(
        name="api_mutation",
        description=(
            "调用 VaultStream 明确允许的本地内容编辑或审核 API。此工具会强制用户确认；"
            "外部同步、发送、服务控制、设置和队列操作不通过通用 API bridge 执行。"
        ),
        args_model=ApiMutationArgs,
        result_schema={"type": "object", "required": ["status_code", "data"], "properties": {"data": {"type": "object"}}},
        permission_level="dangerous",
        permissions=["api:write"],
        handler=_api_mutation_tool,
    )


async def _api_catalog_tool(args: Dict[str, Any], context: AgentToolContext) -> Dict[str, Any]:
    app = _require_app(context)
    prefix = str(args.get("prefix") or "").strip()
    include_mutations = bool(args.get("include_mutations", True))
    if prefix and not prefix.startswith("/"):
        prefix = "/" + prefix
    if prefix and not prefix.startswith("/api/v1"):
        prefix = "/api/v1" + prefix

    endpoints: list[dict[str, Any]] = []
    for path, path_item in app.openapi().get("paths", {}).items():
        if prefix and not path.startswith(prefix):
            continue
        if not isinstance(path_item, dict):
            continue
        for raw_method, operation in path_item.items():
            method = raw_method.upper()
            if method not in _PUBLIC_METHODS or not isinstance(operation, dict):
                continue
            if method not in _SAFE_METHODS and not include_mutations:
                continue
            if not _is_allowed_operation(method, path):
                continue
            endpoints.append(
                {
                    "method": method,
                    "path": path,
                    "name": str(operation.get("operationId") or ""),
                    "permission_hint": "read" if method in _SAFE_METHODS else "confirmation_required",
                }
            )
    endpoints.sort(key=lambda item: (item["path"], item["method"]))
    return {"count": len(endpoints), "endpoints": endpoints}


async def _api_get_tool(args: Dict[str, Any], context: AgentToolContext) -> Dict[str, Any]:
    return await _call_internal_api(
        context=context,
        method="GET",
        path=str(args.get("path") or ""),
        query=args.get("query") if isinstance(args.get("query"), dict) else {},
        body=None,
        max_items=int(args.get("max_items") or 20),
        max_chars=int(args.get("max_chars") or 12000),
    )


async def _api_mutation_tool(args: Dict[str, Any], context: AgentToolContext) -> Dict[str, Any]:
    method = str(args.get("method") or "").upper()
    return await _call_internal_api(
        context=context,
        method=method,
        path=str(args.get("path") or ""),
        query=args.get("query") if isinstance(args.get("query"), dict) else {},
        body=args.get("body") if isinstance(args.get("body"), dict) else {},
        max_items=int(args.get("max_items") or 20),
        max_chars=int(args.get("max_chars") or 12000),
    )


async def _call_internal_api(
    *,
    context: AgentToolContext,
    method: str,
    path: str,
    query: Dict[str, Any],
    body: Dict[str, Any] | None,
    max_items: int,
    max_chars: int,
) -> Dict[str, Any]:
    app = _require_app(context)
    method = method.upper().strip()
    path = _normalize_path(path)
    _validate_method_and_path(method, path)

    token = settings.api_token.get_secret_value() if settings.api_token else ""
    headers = {"X-API-Token": token} if token else {}
    transport = httpx.ASGITransport(app=app)

    # The Agent service records run/tool_call rows before tool execution. Commit
    # those audit rows before re-entering the FastAPI app so SQLite does not hold
    # a write lock while the target API endpoint performs its own write.
    await context.db.commit()

    async with httpx.AsyncClient(transport=transport, base_url="http://vaultstream-agent.local") as client:
        response = await client.request(method, path, params=query or None, json=body, headers=headers)

    data = _decode_response(response)
    if response.status_code >= 400:
        raise AgentToolError(
            error_code="agent_api_call_failed",
            message=f"{method} {path} returned HTTP {response.status_code}",
            retryable=response.status_code in {408, 409, 429, 500, 502, 503, 504},
            details={"status_code": response.status_code, "path": path, "response": _compact(data, max_items=max_items, max_chars=max_chars)},
            suggested_fix="Use api_catalog to confirm the endpoint, then retry with valid query/body fields.",
        )

    return {
        "method": method,
        "path": path,
        "status_code": response.status_code,
        "data": _compact(data, max_items=max_items, max_chars=max_chars),
    }


def _require_app(context: AgentToolContext):
    if context.app is None:
        raise AgentToolError(
            error_code="agent_api_app_unavailable",
            message="FastAPI app context is required for api_* tools",
            retryable=True,
            suggested_fix="Invoke this tool through /agent/run, /agent/tools/invoke, SSE or WebSocket.",
        )
    return context.app


def _normalize_path(path: str) -> str:
    value = path.strip()
    # Query values have their own argument. Reject ambiguous path syntax before
    # HTTPX or ASGI can decode or collapse it into a different permission scope.
    if (
        not value
        or any(char in value for char in "%?#\\")
        or any(char.isspace() or ord(char) < 32 for char in value)
        or "//" in value
        or any(segment in {".", ".."} for segment in value.split("/"))
    ):
        _raise_blocked_path(value)
    if not value.startswith("/"):
        value = "/" + value
    if value != "/api/v1" and not value.startswith("/api/v1/"):
        value = "/api/v1" + value
    if httpx.URL(value).path != value:
        _raise_blocked_path(value)
    return value


def _validate_method_and_path(method: str, path: str) -> None:
    if method not in _SAFE_METHODS | _MUTATION_METHODS:
        raise AgentToolError(
            error_code="agent_api_method_not_allowed",
            message=f"Unsupported API method: {method}",
            retryable=True,
            suggested_fix="Use GET with api_get, or POST/PUT/PATCH/DELETE with api_mutation.",
        )
    if not _is_allowed_operation(method, path):
        _raise_blocked_path(path)
    if method in _SAFE_METHODS and path.startswith(_BINARY_PREFIXES):
        _raise_blocked_path(path, "Binary/media endpoints are not exposed through api_get.")


def _is_allowed_operation(method: str, path: str) -> bool:
    if not path.startswith("/api/v1"):
        return False
    if path.startswith(_BLOCKED_PREFIXES):
        return False
    if path.startswith(_BINARY_PREFIXES):
        return False
    if method in _SAFE_METHODS:
        return any(
            _matches_prefix(path, prefix) for prefix in _READ_ALLOWED_PREFIXES
        )
    return any(
        method == allowed_method and _matches_path_template(path, template)
        for allowed_method, template in _MUTATION_OPERATIONS
    )


def _matches_prefix(path: str, prefix: str) -> bool:
    return path == prefix or path.startswith(prefix + "/")


def _matches_path_template(path: str, template: str) -> bool:
    actual_segments = path.strip("/").split("/")
    template_segments = template.strip("/").split("/")
    if len(actual_segments) != len(template_segments):
        return False
    return all(
        expected == actual
        or (expected.startswith("{") and expected.endswith("}") and bool(actual))
        for actual, expected in zip(actual_segments, template_segments)
    )


def _raise_blocked_path(path: str, message: str | None = None) -> None:
    raise AgentToolError(
        error_code="agent_api_path_not_allowed",
        message=message or f"API path is not exposed to Agent tools: {path}",
        retryable=True,
        details={"path": path},
        suggested_fix="Use api_catalog to choose a supported /api/v1 endpoint.",
    )


def _decode_response(response: httpx.Response) -> Any:
    content_type = response.headers.get("content-type", "")
    if "application/json" in content_type:
        return response.json()
    text = response.text
    return {"text": text[:4000], "content_type": content_type}


def _compact(value: Any, *, max_items: int, max_chars: int) -> Any:
    if isinstance(value, str):
        return value if len(value) <= max_chars else value[:max_chars] + "...[truncated]"
    if isinstance(value, list):
        items = [_compact(item, max_items=max_items, max_chars=max_chars) for item in value[:max_items]]
        if len(value) > max_items:
            items.append({"_truncated": len(value) - max_items})
        return items
    if isinstance(value, dict):
        return {
            str(key): _compact(item, max_items=max_items, max_chars=max_chars)
            for key, item in value.items()
        }
    return value
