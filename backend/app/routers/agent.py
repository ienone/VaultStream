"""
Agent + Tool Calling API.
"""
from __future__ import annotations

import json
from typing import Optional

from fastapi import APIRouter, Depends, HTTPException, Query, Request, WebSocket, WebSocketDisconnect
from fastapi.responses import StreamingResponse
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.api_errors import build_error_payload
from app.core.config import settings
from app.core.database import get_db
from app.core.dependencies import require_api_token
from app.schemas import (
    AgentConfirmationDecisionRequest,
    AgentConfirmationResponse,
    AgentMessageListResponse,
    AgentRunControlResponse,
    AgentRunRequest,
    AgentRunResponse,
    AgentSessionCreateRequest,
    AgentSessionItem,
    AgentSessionListResponse,
    AgentSessionUpdateRequest,
    AgentToolInfo,
    AgentToolInvokeRequest,
    AgentToolInvokeResponse,
)
from app.services.agent import AgentService, AgentToolContext, AgentToolError, get_tool_registry

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


def _raise_agent_error(exc: AgentToolError, *, status_code: int = 400) -> None:
    raise HTTPException(
        status_code=status_code,
        detail=build_error_payload(
            message=exc.message,
            code=exc.error_code,
            hint=exc.suggested_fix,
            extra={
                "retryable": exc.retryable,
                "details": exc.details,
            },
        ),
    )


def _run_response(result) -> AgentRunResponse:
    return AgentRunResponse(
        session_id=result.session_id,
        run_id=result.run_id,
        status=result.status,
        tool=result.tool,
        message=result.message,
        result=result.result,
        events=result.events,
        confirmation_required=result.confirmation_required,
        confirmation=result.confirmation,
        usage=result.usage,
    )


@router.get("/agent/tools", response_model=list[AgentToolInfo])
async def list_agent_tools(_: None = Depends(require_api_token)):
    registry = get_tool_registry()
    return [
        AgentToolInfo(
            name=tool.name,
            description=tool.description,
            permission_level=tool.permission_level.value,
            args_schema=tool.args_schema,
            result_schema=tool.result_schema,
        )
        for tool in registry.list_specs()
    ]


@router.post("/agent/tools/{tool_name}/invoke", response_model=AgentToolInvokeResponse)
async def invoke_agent_tool(
    tool_name: str,
    payload: AgentToolInvokeRequest,
    request: Request,
    db: AsyncSession = Depends(get_db),
    _: None = Depends(require_api_token),
):
    service = AgentService(db, app=request.app)
    try:
        result = await service.invoke_tool(
            tool_name=tool_name,
            args=payload.args,
            confirmed=payload.confirmed,
        )
    except AgentToolError as exc:
        status = 404 if exc.error_code == "agent_tool_not_found" else 400
        _raise_agent_error(exc, status_code=status)

    return AgentToolInvokeResponse(
        tool=tool_name,
        ok=result.status == "completed",
        result=result.result or None,
        confirmation_required=result.confirmation_required,
        confirmation=result.confirmation,
    )


@router.get("/agent/sessions", response_model=AgentSessionListResponse)
async def list_agent_sessions(
    limit: int = Query(50, ge=1, le=100),
    db: AsyncSession = Depends(get_db),
    _: None = Depends(require_api_token),
):
    sessions = await AgentService(db).list_sessions(limit=limit)
    return AgentSessionListResponse(sessions=[AgentSessionItem(**item) for item in sessions])


@router.post("/agent/sessions", response_model=AgentSessionItem)
async def create_agent_session(
    payload: AgentSessionCreateRequest,
    db: AsyncSession = Depends(get_db),
    _: None = Depends(require_api_token),
):
    service = AgentService(db)
    session = await service.ensure_session(None, title=payload.title or "新会话")
    await db.commit()
    await db.refresh(session)
    return AgentSessionItem.model_validate(session)


@router.patch("/agent/sessions/{session_id}", response_model=AgentSessionItem)
async def rename_agent_session(
    session_id: str,
    payload: AgentSessionUpdateRequest,
    db: AsyncSession = Depends(get_db),
    _: None = Depends(require_api_token),
):
    try:
        session = await AgentService(db).rename_session(session_id, payload.title)
    except AgentToolError as exc:
        _raise_agent_error(exc, status_code=404)
    return AgentSessionItem.model_validate(session)


@router.delete("/agent/sessions/{session_id}")
async def delete_agent_session(
    session_id: str,
    db: AsyncSession = Depends(get_db),
    _: None = Depends(require_api_token),
):
    try:
        await AgentService(db).delete_session(session_id)
    except AgentToolError as exc:
        _raise_agent_error(exc, status_code=404)
    return {"ok": True, "session_id": session_id}


@router.post("/agent/sessions/{session_id}/clear")
async def clear_agent_session(
    session_id: str,
    db: AsyncSession = Depends(get_db),
    _: None = Depends(require_api_token),
):
    try:
        await AgentService(db).clear_session(session_id)
    except AgentToolError as exc:
        _raise_agent_error(exc, status_code=404)
    return {"ok": True, "session_id": session_id}


@router.get("/agent/sessions/{session_id}/messages", response_model=AgentMessageListResponse)
async def list_agent_messages(
    session_id: str,
    limit: int = Query(50, ge=1, le=100),
    before_id: int | None = Query(None),
    db: AsyncSession = Depends(get_db),
    _: None = Depends(require_api_token),
):
    try:
        messages, next_before_id = await AgentService(db).list_messages(
            session_id,
            limit=limit,
            before_id=before_id,
        )
    except AgentToolError as exc:
        _raise_agent_error(exc, status_code=404)
    return AgentMessageListResponse(messages=messages, next_before_id=next_before_id)


@router.post("/agent/run", response_model=AgentRunResponse)
async def run_agent(
    payload: AgentRunRequest,
    request: Request,
    db: AsyncSession = Depends(get_db),
    _: None = Depends(require_api_token),
):
    service = AgentService(db, app=request.app)
    try:
        result = await service.run_message(message=payload.message, session_id=payload.session_id)
    except AgentToolError as exc:
        status = 400 if exc.error_code != "agent_execution_failed" else 500
        _raise_agent_error(exc, status_code=status)
    return _run_response(result)


@router.post("/agent/confirmations/{confirmation_id}/decide", response_model=AgentRunResponse)
async def decide_agent_confirmation(
    confirmation_id: str,
    payload: AgentConfirmationDecisionRequest,
    request: Request,
    db: AsyncSession = Depends(get_db),
    _: None = Depends(require_api_token),
):
    try:
        result = await AgentService(db, app=request.app).decide_confirmation(
            confirmation_id,
            approved=payload.approved,
        )
    except AgentToolError as exc:
        status = 404 if exc.error_code.endswith("not_found") else 400
        _raise_agent_error(exc, status_code=status)
    return _run_response(result)


@router.post("/agent/runs/{run_id}/stop", response_model=AgentRunControlResponse)
async def stop_agent_run(
    run_id: str,
    db: AsyncSession = Depends(get_db),
    _: None = Depends(require_api_token),
):
    try:
        run = await AgentService(db).stop_run(run_id)
    except AgentToolError as exc:
        _raise_agent_error(exc, status_code=404)
    return AgentRunControlResponse(run_id=run.id, session_id=run.session_id, status=run.status)


@router.post("/agent/sessions/{session_id}/redo", response_model=AgentRunResponse)
async def redo_agent_last_step(
    session_id: str,
    request: Request,
    db: AsyncSession = Depends(get_db),
    _: None = Depends(require_api_token),
):
    try:
        result = await AgentService(db, app=request.app).redo_last(session_id)
    except AgentToolError as exc:
        _raise_agent_error(exc, status_code=400)
    return _run_response(result)


@router.get("/agent/confirmations/{confirmation_id}", response_model=AgentConfirmationResponse)
async def get_agent_confirmation(
    confirmation_id: str,
    db: AsyncSession = Depends(get_db),
    _: None = Depends(require_api_token),
):
    from app.models import AgentConfirmation

    confirmation = await db.get(AgentConfirmation, confirmation_id)
    if confirmation is None:
        raise HTTPException(status_code=404, detail="confirmation not found")
    return AgentConfirmationResponse.model_validate(confirmation)


@router.get("/agent/sse")
async def agent_sse(
    request: Request,
    message: str = Query(..., min_length=1),
    session_id: str | None = Query(None),
    _: None = Depends(require_api_token),
):
    from app.core.database import AsyncSessionLocal

    async def _event_stream():
        async with AsyncSessionLocal() as db:
            service = AgentService(db, app=request.app)
            try:
                result = await service.run_message(message=message, session_id=session_id)
                for event in result.events:
                    yield f"event: {event.get('type', 'message')}\ndata: {json.dumps(event, ensure_ascii=False, default=str)}\n\n"
            except AgentToolError as exc:
                event = {"type": "error", **exc.to_payload()}
                yield f"event: error\ndata: {json.dumps(event, ensure_ascii=False, default=str)}\n\n"

    return StreamingResponse(_event_stream(), media_type="text/event-stream")


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
    session_id = websocket.query_params.get("session_id")

    try:
        while True:
            payload = await websocket.receive_json()
            tool_name = payload.get("tool")
            args = payload.get("args") if isinstance(payload.get("args"), dict) else {}
            message = payload.get("message")
            confirmed = bool(payload.get("confirmed", False))

            from app.core.database import AsyncSessionLocal

            async with AsyncSessionLocal() as db:
                service = AgentService(db, app=websocket.app)
                try:
                    if isinstance(tool_name, str) and tool_name.strip():
                        result = await service.invoke_tool(
                            tool_name=tool_name.strip(),
                            args=args,
                            confirmed=confirmed,
                            session_id=session_id,
                        )
                    else:
                        if not isinstance(message, str) or not message.strip():
                            raise AgentToolError(
                                error_code="agent_invalid_message",
                                message="message or tool is required",
                                retryable=True,
                            )
                        result = await service.run_message(message=message, session_id=session_id)
                    for event in result.events:
                        await websocket.send_json(event)
                except AgentToolError as exc:
                    await websocket.send_json({"type": "error", **exc.to_payload()})
    except WebSocketDisconnect:
        return
