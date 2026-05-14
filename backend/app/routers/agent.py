"""
Agent + Tool Calling API
"""
from __future__ import annotations

import json
from typing import Optional

from fastapi import APIRouter, Depends, HTTPException, WebSocket, WebSocketDisconnect
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.database import get_db
from app.core.dependencies import require_api_token
from app.core.config import settings
from app.core.api_errors import build_error_payload
from app.schemas import (
    AgentRunRequest,
    AgentRunResponse,
    AgentToolInfo,
    AgentToolInvokeRequest,
    AgentToolInvokeResponse,
)
from app.services.agent import AgentToolContext, get_tool_registry, run_agent_message

router = APIRouter()


def _extract_bearer(value: Optional[str]) -> Optional[str]:
    if not value:
        return None
    parts = value.split(" ", 1)
    if len(parts) == 2 and parts[0].lower() == "bearer":
        return parts[1].strip()
    return None


def _is_valid_token(
    *,
    header_token: Optional[str],
    auth_header: Optional[str],
) -> bool:
    expected = settings.api_token.get_secret_value() if settings.api_token else ""
    if not expected:
        return True
    provided = header_token or _extract_bearer(auth_header)
    return bool(provided and provided == expected)


@router.get("/agent/tools", response_model=list[AgentToolInfo])
async def list_agent_tools(_: None = Depends(require_api_token)):
    registry = get_tool_registry()
    return [
        AgentToolInfo(name=tool.name, description=tool.description, args_schema=tool.args_schema)
        for tool in registry.list_specs()
    ]


@router.post("/agent/tools/{tool_name}/invoke", response_model=AgentToolInvokeResponse)
async def invoke_agent_tool(
    tool_name: str,
    payload: AgentToolInvokeRequest,
    db: AsyncSession = Depends(get_db),
    _: None = Depends(require_api_token),
):
    registry = get_tool_registry()
    if not registry.has_tool(tool_name):
        raise HTTPException(
            status_code=404,
            detail=build_error_payload(
                message=f"Unknown tool: {tool_name}",
                code="agent_tool_not_found",
            ),
        )

    context = AgentToolContext(db=db)
    try:
        result = await registry.invoke(tool_name, payload.args, context)
    except ValueError as e:
        raise HTTPException(
            status_code=400,
            detail=build_error_payload(
                message=str(e),
                code="agent_tool_invalid_args",
            ),
        )
    except Exception as e:
        raise HTTPException(
            status_code=500,
            detail=build_error_payload(
                message="Tool execution failed",
                code="agent_tool_execution_failed",
            ),
        )

    return AgentToolInvokeResponse(tool=tool_name, ok=True, result=result)


@router.post("/agent/run", response_model=AgentRunResponse)
async def run_agent(
    payload: AgentRunRequest,
    db: AsyncSession = Depends(get_db),
    _: None = Depends(require_api_token),
):
    if not isinstance(payload.message, str) or not payload.message.strip():
        raise HTTPException(status_code=400, detail="message is required")

    context = AgentToolContext(db=db)
    try:
        result = await run_agent_message(payload.message, context)
    except ValueError as e:
        raise HTTPException(
            status_code=400,
            detail=build_error_payload(
                message=str(e),
                code="agent_invalid_message",
            ),
        )
    except Exception as e:
        raise HTTPException(
            status_code=500,
            detail=build_error_payload(
                message="Agent execution failed",
                code="agent_execution_failed",
            ),
        )
    return AgentRunResponse(tool=result.tool, result=result.result)


@router.websocket("/agent/ws")
async def agent_ws(websocket: WebSocket):
    header_token = websocket.headers.get("x-api-token")
    auth_header = websocket.headers.get("authorization")
    if not _is_valid_token(
        header_token=header_token,
        auth_header=auth_header,
    ):
        await websocket.close(code=4401, reason="unauthorized")
        return

    await websocket.accept()
    registry = get_tool_registry()
    session_id = websocket.query_params.get("session_id")

    try:
        while True:
            payload = await websocket.receive_json()
            await websocket.send_json({"type": "start", "session_id": session_id})

            tool_name = payload.get("tool")
            args = payload.get("args") or {}
            message = payload.get("message")

            if isinstance(tool_name, str) and tool_name.strip():
                if not registry.has_tool(tool_name):
                    await websocket.send_json(
                        {
                            "type": "error",
                            "error_code": "agent_tool_not_found",
                            "error": f"Unknown tool: {tool_name}",
                        }
                    )
                    continue
                async for event in _stream_tool_result(
                    tool_name=tool_name.strip(),
                    args=args if isinstance(args, dict) else {},
                    websocket=websocket,
                ):
                    if event == "done":
                        break
            else:
                if not isinstance(message, str) or not message.strip():
                    await websocket.send_json(
                        {
                            "type": "error",
                            "error_code": "agent_invalid_message",
                            "error": "message or tool is required",
                        }
                    )
                    continue
                async for event in _stream_agent_message(
                    message=message,
                    websocket=websocket,
                ):
                    if event == "done":
                        break
    except WebSocketDisconnect:
        return


async def _stream_tool_result(*, tool_name: str, args: dict, websocket: WebSocket):
    from app.core.database import AsyncSessionLocal

    await websocket.send_json({"type": "tool_call", "tool": tool_name, "args": args})
    async with AsyncSessionLocal() as db:
        context = AgentToolContext(db=db, app=websocket.app)
        try:
            result = await get_tool_registry().invoke(tool_name, args, context)
        except ValueError as e:
            await websocket.send_json(
                {
                    "type": "error",
                    "error_code": "agent_tool_invalid_args",
                    "error": str(e),
                }
            )
            yield "done"
            return
        except Exception as e:
            await websocket.send_json(
                {
                    "type": "error",
                    "error_code": "agent_tool_execution_failed",
                    "error": str(e),
                }
            )
            yield "done"
            return

        serialized = json.dumps(result, ensure_ascii=False)
        # 简单分块，模拟流式输出
        for i in range(0, len(serialized), 256):
            await websocket.send_json({"type": "delta", "content": serialized[i : i + 256]})

        await websocket.send_json({"type": "final", "tool": tool_name, "result": result})
        yield "done"


async def _stream_agent_message(*, message: str, websocket: WebSocket):
    from app.core.database import AsyncSessionLocal

    async with AsyncSessionLocal() as db:
        context = AgentToolContext(db=db, app=websocket.app)
        try:
            result = await run_agent_message(message, context)
        except ValueError as e:
            await websocket.send_json(
                {
                    "type": "error",
                    "error_code": "agent_invalid_message",
                    "error": str(e),
                }
            )
            yield "done"
            return
        except Exception as e:
            await websocket.send_json(
                {
                    "type": "error",
                    "error_code": "agent_execution_failed",
                    "error": str(e),
                }
            )
            yield "done"
            return

        await websocket.send_json({"type": "tool_call", "tool": result.tool})
        serialized = json.dumps(result.result, ensure_ascii=False)
        for i in range(0, len(serialized), 256):
            await websocket.send_json({"type": "delta", "content": serialized[i : i + 256]})
        await websocket.send_json({"type": "final", "tool": result.tool, "result": result.result})
        yield "done"
