"""Telegram user-account controls; distinct from Bot configuration."""
from pathlib import Path
from datetime import datetime
from typing import Literal
from fastapi import APIRouter, Depends, HTTPException, Request
from pydantic import BaseModel, ConfigDict, SecretStr, Field

from app.core.config import settings
from app.core.dependencies import require_api_token

router = APIRouter(prefix="/telegram-account", dependencies=[Depends(require_api_token)])


class TelegramSyncOptions(BaseModel):
    model_config = ConfigDict(extra="forbid")
    channels_enabled: bool
    saved_enabled: bool


class TelegramAccountStatus(TelegramSyncOptions):
    configured: bool
    session_present: bool
    running: bool


class TelegramSyncAccepted(BaseModel):
    run_id: str


def worker(request: Request):
    return request.app.state.telegram_account_sync_task


@router.get("/status", response_model=TelegramAccountStatus)
async def status(request: Request):
    task = worker(request)
    return TelegramAccountStatus(**await task.options(), running=task.running,
        configured=bool(settings.telegram_api_id and settings.telegram_api_hash.get_secret_value()),
        session_present=Path(settings.telegram_session_path).is_file())


@router.put("/options", response_model=TelegramSyncOptions)
async def configure(options: TelegramSyncOptions, request: Request):
    if not request.app.state.periodic_tasks_started:
        raise HTTPException(503, "当前进程不承担账号同步")
    await worker(request).configure(**options.model_dump())
    return options


@router.post("/sync", response_model=TelegramSyncAccepted, status_code=202)
async def sync(request: Request):
    if not request.app.state.periodic_tasks_started:
        raise HTTPException(503, "当前进程不承担账号同步")
    try:
        run_id = await worker(request).trigger()
    except ValueError as error:
        raise HTTPException(409, str(error)) from error
    return TelegramSyncAccepted(run_id=run_id)


class TelegramLoginStatus(BaseModel):
    login_id: str
    state: Literal["waiting", "qr", "password_required", "authorized", "expired", "failed", "cancelled"]
    qrcode_b64: str | None = None
    expires_at: datetime | None = None
    message: str | None = None


class TelegramLoginPassword(BaseModel):
    model_config = ConfigDict(extra="forbid")
    password: SecretStr = Field(min_length=1, max_length=1024)


def login_worker(request: Request):
    if not request.app.state.periodic_tasks_started:
        raise HTTPException(503, "当前进程不承担账号登录")
    return worker(request)


@router.post("/login", response_model=TelegramLoginStatus, status_code=202)
async def start_login(request: Request):
    try:
        return await login_worker(request).start_login()
    except ValueError as error:
        raise HTTPException(409, str(error)) from error


@router.get("/login/{login_id}", response_model=TelegramLoginStatus)
async def login_status(login_id: str, request: Request):
    try:
        return login_worker(request).login.get(login_id)
    except KeyError as error:
        raise HTTPException(404, "登录已结束，请重新发起") from error


@router.post("/login/{login_id}/password", response_model=TelegramLoginStatus)
async def login_password(login_id: str, body: TelegramLoginPassword, request: Request):
    try:
        return login_worker(request).login.password(login_id, body.password.get_secret_value())
    except KeyError as error:
        raise HTTPException(404, "登录已结束，请重新发起") from error
    except ValueError as error:
        raise HTTPException(409, str(error)) from error


@router.delete("/login/{login_id}", response_model=TelegramLoginStatus)
async def cancel_login(login_id: str, request: Request):
    task = login_worker(request)
    try:
        await task.login.cancel(login_id)
        return task.login.get(login_id)
    except KeyError as error:
        raise HTTPException(404, "登录已结束，请重新发起") from error
