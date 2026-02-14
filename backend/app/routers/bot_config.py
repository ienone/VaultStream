"""
Bot 配置管理 API（Phase 2）
包含：BotConfig CRUD、主 Bot 切换、二维码获取、按配置同步群组
"""
from typing import List, Dict, Any

import httpx
from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy import select, func
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.database import get_db
from app.core.dependencies import require_api_token
from app.core.logging import logger
from app.core.time_utils import utcnow
from app.core.events import event_bus
from app.models import BotConfig, BotConfigPlatform, BotChat, BotChatType
from app.schemas import (
    BotConfigCreate,
    BotConfigUpdate,
    BotConfigResponse,
    BotConfigActivateResponse,
    BotConfigSyncChatsResponse,
    BotConfigQrCodeResponse,
)

router = APIRouter(prefix="/bot-config", tags=["bot-config"])


def _mask_token(token: str | None) -> str | None:
    if not token:
        return None
    if len(token) <= 10:
        return "*" * len(token)
    return f"{token[:6]}***{token[-4:]}"


async def _validate_bot_config_payload(payload: BotConfigCreate | BotConfigUpdate, platform: str):
    if platform == BotConfigPlatform.TELEGRAM.value:
        token = getattr(payload, "bot_token", None)
        if token is not None and not token.strip():
            raise HTTPException(status_code=400, detail="bot_token cannot be empty")
    elif platform == BotConfigPlatform.QQ.value:
        # QQ 至少要求一个地址可用
        napcat_http_url = getattr(payload, "napcat_http_url", None)
        napcat_ws_url = getattr(payload, "napcat_ws_url", None)
        napcat_access_token = getattr(payload, "napcat_access_token", None)
        if napcat_http_url is not None and not napcat_http_url.strip():
            raise HTTPException(status_code=400, detail="napcat_http_url cannot be empty")
        if napcat_ws_url is not None and not napcat_ws_url.strip():
            raise HTTPException(status_code=400, detail="napcat_ws_url cannot be empty")
        if napcat_access_token is not None and not napcat_access_token.strip():
            raise HTTPException(status_code=400, detail="napcat_access_token cannot be empty")


async def _to_bot_config_response(db: AsyncSession, cfg: BotConfig) -> BotConfigResponse:
    count_result = await db.execute(
        select(func.count(BotChat.id)).where(BotChat.bot_config_id == cfg.id)
    )
    chat_count = int(count_result.scalar() or 0)
    return BotConfigResponse(
        id=cfg.id,
        platform=cfg.platform.value if cfg.platform else "telegram",
        name=cfg.name,
        bot_token_masked=_mask_token(cfg.bot_token),
        napcat_http_url=cfg.napcat_http_url,
        napcat_ws_url=cfg.napcat_ws_url,
        napcat_access_token_masked=_mask_token(cfg.napcat_access_token),
        enabled=bool(cfg.enabled),
        is_primary=bool(cfg.is_primary),
        bot_id=cfg.bot_id,
        bot_username=cfg.bot_username,
        chat_count=chat_count,
        created_at=cfg.created_at,
        updated_at=cfg.updated_at,
    )


@router.post("", response_model=BotConfigResponse, status_code=201)
async def create_bot_config(
    payload: BotConfigCreate,
    db: AsyncSession = Depends(get_db),
    _: None = Depends(require_api_token),
):
    await _validate_bot_config_payload(payload, payload.platform)

    db_cfg = BotConfig(
        platform=BotConfigPlatform(payload.platform),
        name=payload.name,
        bot_token=payload.bot_token,
        napcat_http_url=payload.napcat_http_url,
        napcat_ws_url=payload.napcat_ws_url,
        napcat_access_token=payload.napcat_access_token,
        enabled=payload.enabled,
        is_primary=payload.is_primary,
    )
    db.add(db_cfg)
    await db.flush()

    if payload.is_primary:
        await db.execute(
            BotConfig.__table__.update()
            .where(BotConfig.id != db_cfg.id)
            .where(BotConfig.platform == db_cfg.platform)
            .values(is_primary=False)
        )

    await db.commit()
    await db.refresh(db_cfg)

    logger.info("Bot 配置已创建: id={} name={} platform={}", db_cfg.id, db_cfg.name, db_cfg.platform.value)
    return await _to_bot_config_response(db, db_cfg)


@router.get("", response_model=List[BotConfigResponse])
async def list_bot_configs(
    db: AsyncSession = Depends(get_db),
    _: None = Depends(require_api_token),
):
    result = await db.execute(select(BotConfig).order_by(BotConfig.platform.asc(), BotConfig.id.asc()))
    configs = result.scalars().all()
    return [await _to_bot_config_response(db, cfg) for cfg in configs]


@router.patch("/{config_id}", response_model=BotConfigResponse)
async def update_bot_config(
    config_id: int,
    payload: BotConfigUpdate,
    db: AsyncSession = Depends(get_db),
    _: None = Depends(require_api_token),
):
    result = await db.execute(select(BotConfig).where(BotConfig.id == config_id))
    cfg = result.scalar_one_or_none()
    if not cfg:
        raise HTTPException(status_code=404, detail="Bot config not found")

    await _validate_bot_config_payload(payload, cfg.platform.value)

    update_data = payload.model_dump(exclude_unset=True)
    for key, value in update_data.items():
        setattr(cfg, key, value)

    if payload.is_primary is True:
        await db.execute(
            BotConfig.__table__.update()
            .where(BotConfig.id != cfg.id)
            .where(BotConfig.platform == cfg.platform)
            .values(is_primary=False)
        )

    cfg.updated_at = utcnow()
    await db.commit()
    await db.refresh(cfg)

    logger.info("Bot 配置已更新: id={} name={}", cfg.id, cfg.name)
    return await _to_bot_config_response(db, cfg)


@router.delete("/{config_id}", status_code=204)
async def delete_bot_config(
    config_id: int,
    db: AsyncSession = Depends(get_db),
    _: None = Depends(require_api_token),
):
    result = await db.execute(select(BotConfig).where(BotConfig.id == config_id))
    cfg = result.scalar_one_or_none()
    if not cfg:
        raise HTTPException(status_code=404, detail="Bot config not found")

    # 强制收口：每个 chat 必须隶属某个 bot_config，禁止删除仍被引用的配置
    chat_count_result = await db.execute(select(func.count(BotChat.id)).where(BotChat.bot_config_id == cfg.id))
    chat_count = int(chat_count_result.scalar() or 0)
    if chat_count > 0:
        raise HTTPException(status_code=400, detail=f"Bot config has bound chats: {chat_count}")

    await db.delete(cfg)
    await db.commit()

    logger.info("Bot 配置已删除: id={} name={}", config_id, cfg.name)


@router.post("/{config_id}/activate", response_model=BotConfigActivateResponse)
async def activate_bot_config(
    config_id: int,
    db: AsyncSession = Depends(get_db),
    _: None = Depends(require_api_token),
):
    result = await db.execute(select(BotConfig).where(BotConfig.id == config_id))
    cfg = result.scalar_one_or_none()
    if not cfg:
        raise HTTPException(status_code=404, detail="Bot config not found")

    await db.execute(
        BotConfig.__table__.update()
        .where(BotConfig.platform == cfg.platform)
        .values(is_primary=False)
    )
    cfg.is_primary = True
    cfg.updated_at = utcnow()
    await db.commit()

    logger.info("Bot 主配置已切换: id={} platform={}", cfg.id, cfg.platform.value)
    return BotConfigActivateResponse(
        id=cfg.id,
        platform=cfg.platform.value,
        is_primary=True,
    )


@router.get("/{config_id}/qr-code", response_model=BotConfigQrCodeResponse)
async def get_napcat_qr_code(
    config_id: int,
    db: AsyncSession = Depends(get_db),
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

    endpoint = cfg.napcat_http_url.rstrip("/") + "/get_qrcode"
    try:
        headers = {}
        if cfg.napcat_access_token:
            headers["Authorization"] = f"Bearer {cfg.napcat_access_token}"
        async with httpx.AsyncClient(timeout=10.0) as client:
            resp = await client.get(endpoint, headers=headers)
            if resp.status_code != 200:
                return BotConfigQrCodeResponse(
                    bot_config_id=cfg.id,
                    status="error",
                    message=f"Napcat response status={resp.status_code}",
                )
            payload = resp.json()
    except Exception as e:
        return BotConfigQrCodeResponse(
            bot_config_id=cfg.id,
            status="error",
            message=f"Napcat request failed: {e}",
        )

    data = payload.get("data") if isinstance(payload, dict) else None
    qr_code = None
    if isinstance(data, dict):
        qr_code = data.get("qr_code") or data.get("image") or data.get("url")

    return BotConfigQrCodeResponse(
        bot_config_id=cfg.id,
        status="ok" if qr_code else "pending",
        qr_code=qr_code,
        message="ok" if qr_code else "No qr_code in response",
    )


@router.post("/{config_id}/sync-chats", response_model=BotConfigSyncChatsResponse)
async def sync_bot_config_chats(
    config_id: int,
    db: AsyncSession = Depends(get_db),
    _: None = Depends(require_api_token),
):
    result = await db.execute(select(BotConfig).where(BotConfig.id == config_id))
    cfg = result.scalar_one_or_none()
    if not cfg:
        raise HTTPException(status_code=404, detail="Bot config not found")

    if cfg.platform == BotConfigPlatform.QQ:
        return await _sync_qq_chats(cfg, db)
    return await _sync_telegram_chats(cfg, db)


async def _sync_telegram_chats(cfg: BotConfig, db: AsyncSession) -> BotConfigSyncChatsResponse:
    """Telegram: 验证 token 并刷新该配置下已知 chat 的元信息"""
    from telegram import Bot
    from telegram.error import TelegramError

    if not cfg.bot_token:
        raise HTTPException(status_code=400, detail="bot_token is required for telegram sync")

    bot = Bot(token=cfg.bot_token)
    details: List[Dict[str, Any]] = []
    updated = 0
    failed = 0

    try:
        me = await bot.get_me()
        cfg.bot_id = str(me.id)
        cfg.bot_username = me.username
    except Exception as e:
        raise HTTPException(status_code=400, detail=f"Invalid telegram bot token: {e}")

    chats_result = await db.execute(select(BotChat).where(BotChat.bot_config_id == cfg.id))
    chats = chats_result.scalars().all()

    for chat in chats:
        try:
            tg_chat = await bot.get_chat(chat.chat_id)
            chat.title = tg_chat.title
            chat.username = tg_chat.username
            chat.description = tg_chat.description
            chat.chat_type = BotChatType(tg_chat.type)
            chat.last_sync_at = utcnow()
            chat.is_accessible = True
            chat.sync_error = None
            updated += 1
            details.append({"chat_id": chat.chat_id, "status": "updated"})
            await event_bus.publish("bot_sync_progress", {
                "bot_config_id": cfg.id,
                "chat_id": chat.chat_id,
                "status": "updated",
                "updated": updated,
                "failed": failed,
                "total": len(chats),
                "timestamp": utcnow().isoformat(),
            })
        except TelegramError as e:
            failed += 1
            chat.last_sync_at = utcnow()
            chat.is_accessible = False
            chat.sync_error = str(e)
            details.append({"chat_id": chat.chat_id, "status": "failed", "error": str(e)})
            await event_bus.publish("bot_sync_progress", {
                "bot_config_id": cfg.id,
                "chat_id": chat.chat_id,
                "status": "failed",
                "error": str(e),
                "updated": updated,
                "failed": failed,
                "total": len(chats),
                "timestamp": utcnow().isoformat(),
            })

    await db.commit()
    await bot.close()

    await event_bus.publish("bot_sync_completed", {
        "bot_config_id": cfg.id,
        "total": len(chats),
        "updated": updated,
        "failed": failed,
        "created": 0,
        "timestamp": utcnow().isoformat(),
    })

    return BotConfigSyncChatsResponse(
        bot_config_id=cfg.id,
        total=len(chats),
        updated=updated,
        created=0,
        failed=failed,
        details=details,
    )


async def _sync_qq_chats(cfg: BotConfig, db: AsyncSession) -> BotConfigSyncChatsResponse:
    """QQ/Napcat: 拉取群列表并 upsert 到 BotChat"""
    if not cfg.napcat_http_url:
        raise HTTPException(status_code=400, detail="napcat_http_url is required for qq sync")

    endpoint = cfg.napcat_http_url.rstrip("/") + "/get_group_list"
    details: List[Dict[str, Any]] = []
    created = 0
    updated = 0
    failed = 0

    try:
        headers = {}
        if cfg.napcat_access_token:
            headers["Authorization"] = f"Bearer {cfg.napcat_access_token}"
        async with httpx.AsyncClient(timeout=15.0) as client:
            resp = await client.get(endpoint, headers=headers)
            payload = resp.json()
    except Exception as e:
        raise HTTPException(status_code=400, detail=f"Failed to fetch napcat group list: {e}")

    groups = []
    if isinstance(payload, dict):
        data = payload.get("data")
        if isinstance(data, list):
            groups = data

    for item in groups:
        try:
            group_id = str(item.get("group_id") or "").strip()
            group_name = item.get("group_name") or f"QQ Group {group_id}"
            if not group_id:
                continue

            existing_result = await db.execute(
                select(BotChat).where(BotChat.bot_config_id == cfg.id, BotChat.chat_id == group_id)
            )
            chat = existing_result.scalar_one_or_none()
            if chat:
                chat.title = group_name
                chat.chat_type = BotChatType.QQ_GROUP
                chat.is_accessible = True
                chat.last_sync_at = utcnow()
                chat.sync_error = None
                updated += 1
            else:
                db.add(BotChat(
                    bot_config_id=cfg.id,
                    chat_id=group_id,
                    chat_type=BotChatType.QQ_GROUP,
                    title=group_name,
                    is_accessible=True,
                    last_sync_at=utcnow(),
                ))
                created += 1
            details.append({"chat_id": group_id, "title": group_name, "status": "ok"})
            await event_bus.publish("bot_sync_progress", {
                "bot_config_id": cfg.id,
                "chat_id": group_id,
                "title": group_name,
                "status": "ok",
                "updated": updated,
                "created": created,
                "failed": failed,
                "total": len(groups),
                "timestamp": utcnow().isoformat(),
            })
        except Exception as e:
            failed += 1
            details.append({"status": "failed", "error": str(e)})
            await event_bus.publish("bot_sync_progress", {
                "bot_config_id": cfg.id,
                "status": "failed",
                "error": str(e),
                "updated": updated,
                "created": created,
                "failed": failed,
                "total": len(groups),
                "timestamp": utcnow().isoformat(),
            })

    await db.commit()
    await event_bus.publish("bot_sync_completed", {
        "bot_config_id": cfg.id,
        "total": len(groups),
        "updated": updated,
        "created": created,
        "failed": failed,
        "timestamp": utcnow().isoformat(),
    })
    return BotConfigSyncChatsResponse(
        bot_config_id=cfg.id,
        total=len(groups),
        updated=updated,
        created=created,
        failed=failed,
        details=details,
    )
