from __future__ import annotations

from fastapi import APIRouter, Depends, HTTPException, Request
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.dependencies import get_db, require_api_token
from app.schemas.actions import ActionInfo, ActionInvokeRequest, ActionInvokeResponse
from app.services.agent import AgentService
from app.services.agent.service import get_tool_registry
from app.services.agent.tool_registry import AgentToolError

router = APIRouter(prefix="/actions", tags=["actions"])


@router.get("", response_model=list[ActionInfo])
async def list_actions(_: None = Depends(require_api_token)):
    """列出 GUI 与 Agent 共用的受控业务动作。"""
    return [
        ActionInfo(
            name=spec.name,
            description=spec.description,
            input_schema=spec.args_schema,
            result_schema=spec.result_schema,
            risk_level=spec.risk_level,
            require_confirmation=spec.requires_confirmation,
            permissions=spec.permissions,
        )
        for spec in get_tool_registry().list_specs()
    ]


@router.get("/{action_name}", response_model=ActionInfo)
async def get_action(action_name: str, _: None = Depends(require_api_token)):
    """查看单个 Action 的输入 schema、风险等级与确认要求。"""
    try:
        spec = get_tool_registry().get(action_name)
    except AgentToolError as exc:
        raise HTTPException(status_code=404, detail=exc.to_payload())

    return ActionInfo(
        name=spec.name,
        description=spec.description,
        input_schema=spec.args_schema,
        result_schema=spec.result_schema,
        risk_level=spec.risk_level,
        require_confirmation=spec.requires_confirmation,
        permissions=spec.permissions,
    )


@router.post("/{action_name}", response_model=ActionInvokeResponse)
async def invoke_action(
    action_name: str,
    payload: ActionInvokeRequest,
    request: Request,
    db: AsyncSession = Depends(get_db),
    _: None = Depends(require_api_token),
):
    """通过统一 Action Registry 执行业务动作，和 Agent 使用同一套 Tool Executor。"""
    service = AgentService(db, app=request.app)
    try:
        result = await service.invoke_tool(
            tool_name=action_name,
            args=payload.input,
            session_id=payload.session_id,
        )
    except AgentToolError as exc:
        status = 404 if exc.error_code == "agent_tool_not_found" else 400
        raise HTTPException(status_code=status, detail=exc.to_payload())

    return ActionInvokeResponse(
        action_name=action_name,
        ok=result.status == "completed",
        status="requires_confirmation" if result.confirmation_required else result.status,
        session_id=result.session_id,
        run_id=result.run_id,
        result=result.result or None,
        steps=result.events,
        requires_confirmation=result.confirmation_required,
        pending_confirmation=result.confirmation,
    )
