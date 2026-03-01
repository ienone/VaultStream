from fastapi import APIRouter, HTTPException, Depends
from typing import Optional
from pydantic import BaseModel
from loguru import logger

from app.services.browser_auth_service import browser_auth_service, AuthSessionStatus

router = APIRouter()

class QRResponse(BaseModel):
    qrcode_b64: str

class CheckResponse(BaseModel):
    is_valid: bool
    platform: str

@router.post("/session/{platform}", response_model=AuthSessionStatus)
async def start_auth_session(platform: str):
    """
    为给定平台启动新的交互式免密（扫码）鉴权会话。
    返回会话状态和 ID。
    """
    try:
        return await browser_auth_service.start_auth_session(platform)
    except ValueError as e:
        raise HTTPException(status_code=400, detail=str(e))

@router.get("/session/{session_id}/qrcode", response_model=QRResponse)
async def get_session_qrcode(session_id: str):
    """
    获取会话所对应的 base64 编码格式的二维码。
    如果未准备好或未找到，则返回 404。
    """
    try:
        b64 = await browser_auth_service.get_session_qrcode(session_id)
        if not b64:
            raise HTTPException(status_code=404, detail="QR code not ready")
        return QRResponse(qrcode_b64=b64)
    except ValueError as e:
        raise HTTPException(status_code=404, detail=str(e))

@router.get("/session/{session_id}/status", response_model=AuthSessionStatus)
async def get_session_status(session_id: str):
    """
    获取鉴权会话的当前状态。
    """
    try:
        return await browser_auth_service.get_session_status(session_id)
    except ValueError as e:
        raise HTTPException(status_code=404, detail=str(e))

@router.post("/{platform}/check", response_model=CheckResponse)
async def check_platform_status(platform: str):
    """
    检查此平台当前存储的 Cookie 是否有效。
    """
    is_valid = await browser_auth_service.check_platform_status(platform)
    return CheckResponse(is_valid=is_valid, platform=platform)

@router.post("/{platform}/logout")
@router.delete("/{platform}")
async def logout_platform(platform: str):
    """
    删除本地 Cookie 并在平台侧彻底注销会话。
    """
    await browser_auth_service.logout_platform(platform)
    return {"status": "success", "message": f"Successfully logged out of {platform}"}
