from typing import Literal

from fastapi import APIRouter, HTTPException, Depends
from pydantic import BaseModel

from app.core.dependencies import require_api_token
from app.services.browser_auth_service import browser_auth_service, AuthSessionStatus, LoginCheckUnavailable
from app.services.notification_inbox import safely_sync_account_auth_notification

router = APIRouter(dependencies=[Depends(require_api_token)])


class CheckResponse(BaseModel):
    is_valid: bool
    platform: str


class AuthActionResponse(BaseModel):
    status: Literal["success"]
    message: str


@router.post("/session/{platform}", response_model=AuthSessionStatus)
async def start_auth_session(platform: str):
    """
    为给定平台启动新的交互式免密（扫码）鉴权会话。
    返回会话状态和 ID。
    """
    try:
        return await browser_auth_service.start_auth_session(platform)
    except ValueError as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc


@router.get("/session/{session_id}/status", response_model=AuthSessionStatus)
async def get_session_status(session_id: str):
    """
    获取鉴权会话的当前状态。
    """
    try:
        return await browser_auth_service.get_session_status(session_id)
    except ValueError as exc:
        raise HTTPException(status_code=404, detail=str(exc)) from exc


@router.delete("/session/{session_id}", response_model=AuthActionResponse)
async def cancel_auth_session(session_id: str):
    """取消二维码登录并释放对应平台网络资源。"""
    await browser_auth_service.cancel_session(session_id)
    return {"status": "success", "message": "登录会话已取消"}


@router.post("/{platform}/check", response_model=CheckResponse)
async def check_platform_status(platform: str):
    """
    检查此平台当前存储的 Cookie 是否有效。
    """
    try:
        is_valid = await browser_auth_service.check_platform_status(platform)
    except LoginCheckUnavailable as error:
        raise HTTPException(status_code=503, detail=str(error)) from error
    except ValueError as error:
        raise HTTPException(status_code=400, detail=str(error)) from error
    await safely_sync_account_auth_notification(platform, is_valid=is_valid)
    return CheckResponse(is_valid=is_valid, platform=platform)


@router.delete("/{platform}", response_model=AuthActionResponse)
async def logout_platform(platform: str):
    """
    删除 VaultStream 本地保存的 Cookie，不修改平台账号本身。
    """
    await browser_auth_service.logout_platform(platform)
    await safely_sync_account_auth_notification(
        platform,
        is_valid=False,
        configured=False,
    )
    return {"status": "success", "message": f"Successfully logged out of {platform}"}


@router.post("/zhihu/refresh-zse", response_model=AuthActionResponse)
async def refresh_zhihu_zse():
    """
    手动刷新知乎 __zse_ck 风控指纹
    """
    success = await browser_auth_service.refresh_zhihu_zse_cookie()
    if success:
        return {"status": "success", "message": "刷新成功"}
    raise HTTPException(
        status_code=503,
        detail="刷新失败，可能 Cookie 已过期、未配置或浏览器服务暂不可用",
    )
