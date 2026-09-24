"""Telegram user-account controls; distinct from Bot configuration."""
from pathlib import Path
from fastapi import APIRouter, Depends, HTTPException, Request
from pydantic import BaseModel, ConfigDict

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
    task = worker(request)
    await task.config.set_value("enable_telegram_channel_sync", options.channels_enabled, category="telegram")
    await task.config.set_value("enable_telegram_saved_sync", options.saved_enabled, category="telegram")
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
