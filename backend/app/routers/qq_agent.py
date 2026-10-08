"""Authenticated Koishi transport for administrator private Agent conversations."""
from fastapi import APIRouter, Depends, Query, Request
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.database import get_db
from app.core.dependencies import require_api_token
from app.schemas.qq_agent import QQAgentDecisionRequest, QQAgentRequest, QQAgentResponse, QQGroupCaptureRequest, QQGroupCaptureResponse
from app.services.qq_agent import QQAgentService

router = APIRouter(dependencies=[Depends(require_api_token)])


@router.post("/bot/qq/{config_id}/group-capture", response_model=QQGroupCaptureResponse)
async def capture_group_message(config_id: int, body: QQGroupCaptureRequest, request: Request,
                                db: AsyncSession = Depends(get_db)):
    result = await QQAgentService(db, app=request.app).receive(config_id, body, group_id=body.group_id)
    ids = [item.content_id for item in result.captures]
    # The group gets a save receipt, never pre-existing private collection text.
    message = f"已转存 {len(ids)} 项到 VaultStream。" if ids else result.message
    return QQGroupCaptureResponse(run_id=result.run_id, status=result.status,
                                  message=message, saved_content_ids=ids, duplicate=result.duplicate)


@router.post("/bot/qq/{config_id}/agent", response_model=QQAgentResponse)
async def receive_private_message(config_id: int, body: QQAgentRequest, request: Request,
                                  db: AsyncSession = Depends(get_db)):
    return await QQAgentService(db, app=request.app).receive(config_id, body)


@router.get("/bot/qq/{config_id}/agent/runs/{run_id}", response_model=QQAgentResponse)
async def get_private_receipt(config_id: int, run_id: str, request: Request,
                              user_id: str = Query(pattern=r"^[0-9]{5,20}$"),
                              db: AsyncSession = Depends(get_db)):
    return await QQAgentService(db, app=request.app).get_receipt(config_id, user_id, run_id)


@router.post("/bot/qq/{config_id}/agent/confirmations/{confirmation_id}", response_model=QQAgentResponse)
async def decide_private_confirmation(config_id: int, confirmation_id: str,
                                      body: QQAgentDecisionRequest, request: Request,
                                      db: AsyncSession = Depends(get_db)):
    return await QQAgentService(db, app=request.app).decide(config_id, body.user_id, confirmation_id, body.approved)
