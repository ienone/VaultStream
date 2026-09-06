from __future__ import annotations

from typing import List

from fastapi import APIRouter, BackgroundTasks, Depends, HTTPException
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.database import get_db
from app.core.dependencies import require_api_token
from app.models import BotConfig, BotConfigPlatform
from app.services.bot_config_service import (
    BotChatSyncService,
    BotConfigNotFoundError,
    BotConfigService,
    BotConfigValidationError,
    TelegramBotRuntimeService,
    get_bot_chat_sync_service,
    get_bot_runtime_service,
)
from app.schemas import (
    BotConfigCreate,
    BotConfigDeleteResponse,
    BotConfigMutationResponse,
    BotConfigUpdate,
    BotConfigResponse,
    BotRuntimeActionResponse,
    BotConfigSyncChatsResponse,
    BotConfigQrCodeResponse,
)

router = APIRouter(prefix="/bot-config", tags=["bot-config"])


def get_bot_config_service(
    runtime: TelegramBotRuntimeService = Depends(get_bot_runtime_service),
    chat_sync: BotChatSyncService = Depends(get_bot_chat_sync_service),
) -> BotConfigService:
    return BotConfigService(runtime=runtime, chat_sync=chat_sync)


def _raise_config_http_error(exc: Exception) -> None:
    if isinstance(exc, BotConfigNotFoundError):
        raise HTTPException(status_code=404, detail=str(exc)) from exc
    if isinstance(exc, BotConfigValidationError):
        raise HTTPException(status_code=400, detail=str(exc)) from exc
    raise exc


@router.post("", response_model=BotConfigMutationResponse, status_code=201)
async def create_bot_config(
    payload: BotConfigCreate,
    background_tasks: BackgroundTasks,
    db: AsyncSession = Depends(get_db),
    service: BotConfigService = Depends(get_bot_config_service),
    _: None = Depends(require_api_token),
):
    try:
        return await service.create(
            db,
            payload,
            add_task=background_tasks.add_task,
        )
    except (BotConfigNotFoundError, BotConfigValidationError) as exc:
        _raise_config_http_error(exc)


@router.get("", response_model=List[BotConfigResponse])
async def list_bot_configs(
    db: AsyncSession = Depends(get_db),
    service: BotConfigService = Depends(get_bot_config_service),
    _: None = Depends(require_api_token),
):
    return await service.list(db)


@router.patch("/{config_id}", response_model=BotConfigMutationResponse)
async def update_bot_config(
    config_id: int,
    payload: BotConfigUpdate,
    background_tasks: BackgroundTasks,
    db: AsyncSession = Depends(get_db),
    service: BotConfigService = Depends(get_bot_config_service),
    _: None = Depends(require_api_token),
):
    try:
        return await service.update(
            db,
            config_id,
            payload,
            add_task=background_tasks.add_task,
        )
    except (BotConfigNotFoundError, BotConfigValidationError) as exc:
        _raise_config_http_error(exc)


@router.post("/{config_id}/activate", response_model=BotConfigMutationResponse)
async def activate_bot_config(
    config_id: int,
    background_tasks: BackgroundTasks,
    db: AsyncSession = Depends(get_db),
    service: BotConfigService = Depends(get_bot_config_service),
    _: None = Depends(require_api_token),
):
    try:
        return await service.activate(
            db,
            config_id,
            add_task=background_tasks.add_task,
        )
    except BotConfigNotFoundError as exc:
        _raise_config_http_error(exc)


@router.delete(
    "/{config_id}",
    response_model=BotConfigDeleteResponse,
    status_code=200,
)
async def delete_bot_config(
    config_id: int,
    db: AsyncSession = Depends(get_db),
    service: BotConfigService = Depends(get_bot_config_service),
    _: None = Depends(require_api_token),
):
    try:
        return await service.delete(db, config_id)
    except BotConfigNotFoundError as exc:
        _raise_config_http_error(exc)


@router.post(
    "/service/telegram/start",
    response_model=BotRuntimeActionResponse,
)
async def start_telegram_service(
    runtime: TelegramBotRuntimeService = Depends(get_bot_runtime_service),
    _: None = Depends(require_api_token),
):
    return await runtime.start(reason="api_manual_start")


@router.post(
    "/service/telegram/stop",
    response_model=BotRuntimeActionResponse,
)
async def stop_telegram_service(
    runtime: TelegramBotRuntimeService = Depends(get_bot_runtime_service),
    _: None = Depends(require_api_token),
):
    return await runtime.stop(reason="api_manual_stop")


@router.post(
    "/service/telegram/restart",
    response_model=BotRuntimeActionResponse,
)
async def restart_telegram_service(
    db: AsyncSession = Depends(get_db),
    runtime: TelegramBotRuntimeService = Depends(get_bot_runtime_service),
    _: None = Depends(require_api_token),
):
    return await runtime.sync_process(db, reason="api_manual_restart")


@router.get("/{config_id}/qr-code", response_model=BotConfigQrCodeResponse)
async def get_napcat_qr_code(
    config_id: int,
    db: AsyncSession = Depends(get_db),
    chat_sync: BotChatSyncService = Depends(get_bot_chat_sync_service),
    _: None = Depends(require_api_token),
):
    """获取 Napcat 登录二维码（当前返回一次性查询结果）"""
    result = await db.execute(select(BotConfig).where(BotConfig.id == config_id))
    cfg = result.scalar_one_or_none()
    if not cfg:
        raise HTTPException(status_code=404, detail="Bot config not found")

    if cfg.platform != BotConfigPlatform.QQ:
        raise HTTPException(status_code=400, detail="Only QQ bot config supports QR code")
    if not cfg.napcat_http_url:
        raise HTTPException(status_code=400, detail="napcat_http_url is not configured")

    return await chat_sync.get_qr_code(cfg)


@router.post("/{config_id}/sync-chats", response_model=BotConfigSyncChatsResponse)
async def sync_bot_config_chats(
    config_id: int,
    db: AsyncSession = Depends(get_db),
    chat_sync: BotChatSyncService = Depends(get_bot_chat_sync_service),
    _: None = Depends(require_api_token),
):
    result = await db.execute(select(BotConfig).where(BotConfig.id == config_id))
    cfg = result.scalar_one_or_none()
    if not cfg:
        raise HTTPException(status_code=404, detail="Bot config not found")

    try:
        return await chat_sync.sync(cfg, db)
    except ValueError as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc
