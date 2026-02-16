"""
功能描述：Bot 管理 API
包含：Bot 群组/频道管理、状态查询、同步功能
调用方式：需要 API Token
"""
from typing import List, Optional
from fastapi import APIRouter, Depends, HTTPException, Query, BackgroundTasks
from sqlalchemy import select, func, desc, update
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.database import get_db
from app.core.dependencies import require_api_token
from app.core.logging import logger
from app.core.config import settings
from app.core.time_utils import utcnow
from app.distribution.queue_service import mark_historical_parse_success_as_pushed_for_rule
from app.models import (
    BotChat,
    BotChatType,
    ContentQueueItem,
    PushedRecord,
    DistributionRule,
    DistributionTarget,
    BotRuntime,
    BotConfig,
    BotConfigPlatform,
    Content,
)
from app.schemas import (
    BotChatCreate, BotChatUpdate, BotChatResponse,
    BotStatusResponse, BotSyncRequest, StorageStatsResponse,
    BotChatUpsert, BotHeartbeat, BotRuntimeResponse, BotSyncResult,
    BotChatRulesResponse, BotChatRuleAssignRequest, ChatRuleBindingInfo,
)
from app.services.bot_config_runtime import get_primary_bot_config

router = APIRouter()


async def _build_pipeline_stats(db: AsyncSession) -> tuple[dict, dict, dict[str, dict]]:
    from app.services.dashboard_service import build_parse_stats, build_distribution_stats
    parse_stats = await build_parse_stats(db)
    distribution_stats, rule_breakdown = await build_distribution_stats(db, include_rule_breakdown=True)
    return parse_stats, distribution_stats, rule_breakdown


# ========== Bot Chat 管理 ==========

@router.get("/bot/chats", response_model=List[BotChatResponse])
async def list_bot_chats(
    enabled: Optional[bool] = None,
    chat_type: Optional[str] = None,
    db: AsyncSession = Depends(get_db),
    _: None = Depends(require_api_token),
):
    """获取所有 Bot 关联的群组/频道"""
    query = select(BotChat).order_by(BotChat.id)
    
    if enabled is not None:
        query = query.where(BotChat.enabled == enabled)
    if chat_type:
        query = query.where(BotChat.chat_type == chat_type)
    
    result = await db.execute(query)
    chats = result.scalars().all()

    rule_map = await _load_chat_rule_map(db, [c.id for c in chats])
    
    return [_chat_to_response(chat, rule_map.get(chat.id)) for chat in chats]


@router.post("/bot/chats", response_model=BotChatResponse)
async def create_bot_chat(
    chat: BotChatCreate,
    db: AsyncSession = Depends(get_db),
    _: None = Depends(require_api_token),
):
    """手动添加 Bot 群组/频道"""
    config_result = await db.execute(select(BotConfig).where(BotConfig.id == chat.bot_config_id))
    db_config = config_result.scalar_one_or_none()
    if not db_config:
        raise HTTPException(status_code=400, detail=f"Bot config not found: {chat.bot_config_id}")

    # 检查是否已存在
    result = await db.execute(
        select(BotChat).where(BotChat.chat_id == chat.chat_id)
    )
    if result.scalar_one_or_none():
        raise HTTPException(status_code=400, detail="Chat already exists")
    
    db_chat = BotChat(
        bot_config_id=chat.bot_config_id,
        chat_id=chat.chat_id,
        chat_type=BotChatType(chat.chat_type),
        title=chat.title,
        username=chat.username,
        description=chat.description,
        enabled=chat.enabled,
        nsfw_chat_id=chat.nsfw_chat_id,
    )
    db.add(db_chat)
    await db.commit()
    await db.refresh(db_chat)
    
    logger.info(f"Bot 群组已添加: {db_chat.title or db_chat.chat_id}")
    return _chat_to_response(db_chat)


@router.get("/bot/chats/{chat_id}", response_model=BotChatResponse)
async def get_bot_chat(
    chat_id: str,
    db: AsyncSession = Depends(get_db),
    _: None = Depends(require_api_token),
):
    """获取单个群组/频道详情"""
    result = await db.execute(
        select(BotChat).where(BotChat.chat_id == chat_id)
    )
    chat = result.scalar_one_or_none()
    if not chat:
        raise HTTPException(status_code=404, detail="Chat not found")
    rule_map = await _load_chat_rule_map(db, [chat.id])
    return _chat_to_response(chat, rule_map.get(chat.id))


@router.get("/bot/chats/{chat_id}/rules", response_model=BotChatRulesResponse)
async def get_bot_chat_rules(
    chat_id: str,
    db: AsyncSession = Depends(get_db),
    _: None = Depends(require_api_token),
):
    """获取某个群组绑定的规则"""
    chat_result = await db.execute(select(BotChat).where(BotChat.chat_id == chat_id))
    chat = chat_result.scalar_one_or_none()
    if not chat:
        raise HTTPException(status_code=404, detail="Chat not found")

    result = await db.execute(
        select(DistributionTarget, DistributionRule)
        .join(DistributionRule, DistributionRule.id == DistributionTarget.rule_id)
        .where(DistributionTarget.bot_chat_id == chat.id)
        .order_by(DistributionRule.priority.desc(), DistributionRule.id.asc())
    )

    rows = result.all()
    rules = [
        ChatRuleBindingInfo(
            rule_id=rule.id,
            name=rule.name,
            enabled=target.enabled,
        )
        for target, rule in rows
    ]
    return BotChatRulesResponse(
        chat_id=chat_id,
        rule_ids=[r.rule_id for r in rules],
        rules=rules,
    )


@router.put("/bot/chats/{chat_id}/rules", response_model=BotChatRulesResponse)
async def assign_bot_chat_rules(
    chat_id: str,
    payload: BotChatRuleAssignRequest,
    db: AsyncSession = Depends(get_db),
    _: None = Depends(require_api_token),
):
    """为群组批量配置规则（全量覆盖）"""
    chat_result = await db.execute(select(BotChat).where(BotChat.chat_id == chat_id))
    chat = chat_result.scalar_one_or_none()
    if not chat:
        raise HTTPException(status_code=404, detail="Chat not found")

    desired_ids = sorted({int(rule_id) for rule_id in payload.rule_ids})

    if desired_ids:
        rules_result = await db.execute(select(DistributionRule).where(DistributionRule.id.in_(desired_ids)))
        existing_rules = {r.id: r for r in rules_result.scalars().all()}
        missing = [rule_id for rule_id in desired_ids if rule_id not in existing_rules]
        if missing:
            raise HTTPException(status_code=400, detail=f"Invalid rule_id(s): {missing}")

    targets_result = await db.execute(
        select(DistributionTarget).where(DistributionTarget.bot_chat_id == chat.id)
    )
    existing_targets = targets_result.scalars().all()
    existing_ids = {t.rule_id for t in existing_targets}

    # 删除不需要的绑定
    added_rule_ids: list[int] = []
    for target in existing_targets:
        if target.rule_id not in desired_ids:
            await db.delete(target)

    # 创建新增绑定
    for rule_id in desired_ids:
        if rule_id not in existing_ids:
            db.add(DistributionTarget(
                rule_id=rule_id,
                bot_chat_id=chat.id,
                enabled=True,
                merge_forward=False,
                use_author_name=True,
            ))
            added_rule_ids.append(rule_id)

    for rule_id in added_rule_ids:
        await mark_historical_parse_success_as_pushed_for_rule(
            session=db,
            rule_id=rule_id,
            bot_chat_id=chat.id,
        )

    await db.commit()

    refreshed = await get_bot_chat_rules(chat_id=chat_id, db=db, _=None)
    return refreshed


@router.patch("/bot/chats/{chat_id}", response_model=BotChatResponse)
async def update_bot_chat(
    chat_id: str,
    update: BotChatUpdate,
    db: AsyncSession = Depends(get_db),
    _: None = Depends(require_api_token),
):
    """更新群组/频道配置"""
    result = await db.execute(
        select(BotChat).where(BotChat.chat_id == chat_id)
    )
    db_chat = result.scalar_one_or_none()
    if not db_chat:
        raise HTTPException(status_code=404, detail="Chat not found")
    
    update_data = update.model_dump(exclude_unset=True)

    if "chat_id" in update_data:
        new_chat_id = str(update_data["chat_id"] or "").strip()
        if not new_chat_id:
            raise HTTPException(status_code=400, detail="chat_id cannot be empty")

        duplicate_result = await db.execute(
            select(BotChat).where(
                BotChat.chat_id == new_chat_id,
                BotChat.id != db_chat.id,
            )
        )
        if duplicate_result.scalar_one_or_none():
            raise HTTPException(status_code=400, detail="Chat already exists")

        update_data["chat_id"] = new_chat_id

    for key, value in update_data.items():
        setattr(db_chat, key, value)
    
    await db.commit()
    await db.refresh(db_chat)
    
    logger.info(f"Bot 群组已更新: {db_chat.title or db_chat.chat_id}")
    return _chat_to_response(db_chat)


@router.delete("/bot/chats/{chat_id}")
async def delete_bot_chat(
    chat_id: str,
    db: AsyncSession = Depends(get_db),
    _: None = Depends(require_api_token),
):
    """删除群组/频道"""
    result = await db.execute(
        select(BotChat).where(BotChat.chat_id == chat_id)
    )
    db_chat = result.scalar_one_or_none()
    if not db_chat:
        raise HTTPException(status_code=404, detail="Chat not found")

    # 显式清理依赖记录，避免 ORM 在删除父记录时尝试将外键置空触发 NOT NULL 约束。
    await db.execute(
        DistributionTarget.__table__.delete().where(
            DistributionTarget.bot_chat_id == db_chat.id
        )
    )
    await db.execute(
        ContentQueueItem.__table__.delete().where(
            ContentQueueItem.bot_chat_id == db_chat.id
        )
    )
    
    await db.delete(db_chat)
    await db.commit()
    
    logger.info(f"Bot 群组已删除: {db_chat.title or chat_id}")
    return {"status": "deleted", "chat_id": chat_id}


@router.post("/bot/chats/{chat_id}/toggle")
async def toggle_bot_chat(
    chat_id: str,
    db: AsyncSession = Depends(get_db),
    _: None = Depends(require_api_token),
):
    """切换群组/频道启用状态"""
    result = await db.execute(
        select(BotChat).where(BotChat.chat_id == chat_id)
    )
    db_chat = result.scalar_one_or_none()
    if not db_chat:
        raise HTTPException(status_code=404, detail="Chat not found")
    
    db_chat.enabled = not db_chat.enabled
    await db.commit()
    
    status = "enabled" if db_chat.enabled else "disabled"
    logger.info(f"Bot 群组状态切换: {db_chat.title or chat_id} -> {status}")
    return {"status": status, "enabled": db_chat.enabled}


# ========== Bot Upsert (for Bot process) ==========

@router.put("/bot/chats:upsert", response_model=BotChatResponse)
async def upsert_bot_chat(
    chat: BotChatUpsert,
    db: AsyncSession = Depends(get_db),
    _: None = Depends(require_api_token),
):
    """Upsert Bot 群组/频道（用于 Bot 进程上报）"""
    config_result = await db.execute(select(BotConfig).where(BotConfig.id == chat.bot_config_id))
    db_config = config_result.scalar_one_or_none()
    if not db_config:
        raise HTTPException(status_code=400, detail=f"Bot config not found: {chat.bot_config_id}")

    result = await db.execute(
        select(BotChat).where(BotChat.chat_id == chat.chat_id)
    )
    db_chat = result.scalar_one_or_none()
    
    now = utcnow()
    if db_chat:
        # 更新已存在的记录
        db_chat.bot_config_id = chat.bot_config_id
        db_chat.chat_type = BotChatType(chat.chat_type)
        db_chat.title = chat.title
        db_chat.username = chat.username
        db_chat.description = chat.description
        db_chat.member_count = chat.member_count
        db_chat.is_admin = chat.is_admin
        db_chat.can_post = chat.can_post
        db_chat.is_accessible = True
        db_chat.last_sync_at = now
        db_chat.sync_error = None
        if chat.raw_data:
            db_chat.raw_data = chat.raw_data
        logger.info(f"Bot 群组已更新: {db_chat.title or db_chat.chat_id}")
    else:
        # 创建新记录
        db_chat = BotChat(
            bot_config_id=chat.bot_config_id,
            chat_id=chat.chat_id,
            chat_type=BotChatType(chat.chat_type),
            title=chat.title,
            username=chat.username,
            description=chat.description,
            member_count=chat.member_count,
            is_admin=chat.is_admin,
            can_post=chat.can_post,
            is_accessible=True,
            last_sync_at=now,
            raw_data=chat.raw_data,
        )
        db.add(db_chat)
        logger.info(f"Bot 群组已添加: {db_chat.title or db_chat.chat_id}")
    
    await db.commit()
    await db.refresh(db_chat)
    return _chat_to_response(db_chat)


# ========== Bot Heartbeat ==========

@router.post("/bot/heartbeat")
async def bot_heartbeat(
    heartbeat: BotHeartbeat,
    db: AsyncSession = Depends(get_db),
    _: None = Depends(require_api_token),
):
    """Bot 心跳上报"""
    now = utcnow()
    
    result = await db.execute(select(BotRuntime).where(BotRuntime.id == 1))
    runtime = result.scalar_one_or_none()
    
    if runtime:
        runtime.bot_id = heartbeat.bot_id
        runtime.bot_username = heartbeat.bot_username
        runtime.bot_first_name = heartbeat.bot_first_name
        runtime.last_heartbeat_at = now
        runtime.version = heartbeat.version
        if heartbeat.error:
            runtime.last_error = heartbeat.error
            runtime.last_error_at = now
    else:
        runtime = BotRuntime(
            id=1,
            bot_id=heartbeat.bot_id,
            bot_username=heartbeat.bot_username,
            bot_first_name=heartbeat.bot_first_name,
            started_at=now,
            last_heartbeat_at=now,
            version=heartbeat.version,
            last_error=heartbeat.error,
            last_error_at=now if heartbeat.error else None,
        )
        db.add(runtime)
    
    await db.commit()
    return {"status": "ok", "heartbeat_at": now.isoformat()}


@router.get("/bot/runtime", response_model=BotRuntimeResponse)
async def get_bot_runtime(
    db: AsyncSession = Depends(get_db),
    _: None = Depends(require_api_token),
):
    """获取 Bot 运行时状态"""
    result = await db.execute(select(BotRuntime).where(BotRuntime.id == 1))
    runtime = result.scalar_one_or_none()
    
    now = utcnow()
    
    if not runtime:
        return BotRuntimeResponse(
            bot_id=None,
            bot_username=None,
            bot_first_name=None,
            started_at=None,
            last_heartbeat_at=None,
            is_running=False,
            uptime_seconds=None,
            version=None,
            last_error=None,
            last_error_at=None,
        )
    
    # 判断是否在线：最后心跳在 2 分钟内
    is_running = False
    uptime_seconds = None
    if runtime.last_heartbeat_at:
        time_since_heartbeat = (now - runtime.last_heartbeat_at).total_seconds()
        is_running = time_since_heartbeat < 120  # 2分钟阈值
    if runtime.started_at and is_running:
        uptime_seconds = int((now - runtime.started_at).total_seconds())
    
    return BotRuntimeResponse(
        bot_id=runtime.bot_id,
        bot_username=runtime.bot_username,
        bot_first_name=runtime.bot_first_name,
        started_at=runtime.started_at,
        last_heartbeat_at=runtime.last_heartbeat_at,
        is_running=is_running,
        uptime_seconds=uptime_seconds,
        version=runtime.version,
        last_error=runtime.last_error,
        last_error_at=runtime.last_error_at,
    )


# ========== Bot 状态 ==========

@router.get("/bot/status", response_model=BotStatusResponse)
async def get_bot_status(
    db: AsyncSession = Depends(get_db),
    _: None = Depends(require_api_token),
):
    """获取 Bot 运行状态"""
    primary_tg_cfg = await get_primary_bot_config(db, BotConfigPlatform.TELEGRAM, enabled_only=False)

    # 获取运行时状态
    runtime_result = await db.execute(select(BotRuntime).where(BotRuntime.id == 1))
    runtime = runtime_result.scalar_one_or_none()
    
    # 统计主 Telegram 配置下关联且启用的群组数
    chat_count = 0
    if primary_tg_cfg and primary_tg_cfg.enabled:
        result = await db.execute(
            select(func.count(BotChat.id)).where(
                BotChat.bot_config_id == primary_tg_cfg.id,
                BotChat.enabled == True,
            )
        )
        chat_count = int(result.scalar() or 0)
    
    # 统计今日推送数
    today_start = utcnow().replace(hour=0, minute=0, second=0, microsecond=0)
    result = await db.execute(
        select(func.count(PushedRecord.id)).where(
            PushedRecord.pushed_at >= today_start
        )
    )
    today_pushed = result.scalar() or 0
    
    # 判断是否在线
    is_running = False
    uptime_seconds = None
    bot_username = primary_tg_cfg.bot_username if primary_tg_cfg else None
    bot_id = None
    now = utcnow()
    has_enabled_primary_tg = bool(primary_tg_cfg and primary_tg_cfg.enabled and (primary_tg_cfg.bot_token or '').strip())
    if primary_tg_cfg and primary_tg_cfg.bot_id:
        try:
            bot_id = int(primary_tg_cfg.bot_id)
        except (TypeError, ValueError):
            bot_id = None
    
    if runtime and has_enabled_primary_tg:
        bot_username = runtime.bot_username
        if runtime.bot_id:
            try:
                bot_id = int(runtime.bot_id)
            except (TypeError, ValueError):
                bot_id = None
        if runtime.last_heartbeat_at:
            time_since_heartbeat = (now - runtime.last_heartbeat_at).total_seconds()
            is_running = time_since_heartbeat < 120
        if runtime.started_at and is_running:
            uptime_seconds = int((now - runtime.started_at).total_seconds())
    
    # Napcat 连接检查
    napcat_status = None
    qq_cfg = await get_primary_bot_config(db, BotConfigPlatform.QQ, enabled_only=True)
    if qq_cfg and qq_cfg.napcat_http_url:
        import httpx
        try:
            headers = {}
            if qq_cfg.napcat_access_token:
                headers["Authorization"] = f"Bearer {qq_cfg.napcat_access_token}"
            async with httpx.AsyncClient(timeout=5.0) as client:
                resp = await client.get(f"{qq_cfg.napcat_http_url.rstrip('/')}/get_login_info", headers=headers)
                if resp.status_code == 200:
                    napcat_status = "online"
                else:
                    napcat_status = f"error:{resp.status_code}"
        except Exception as e:
            napcat_status = f"offline:{e}"
    elif qq_cfg:
        napcat_status = "misconfigured"

    parse_stats, distribution_stats, rule_breakdown = await _build_pipeline_stats(db)

    return BotStatusResponse(
        is_running=is_running,
        bot_username=bot_username,
        bot_id=bot_id,
        connected_chats=chat_count,
        total_pushed_today=today_pushed,
        uptime_seconds=uptime_seconds,
        napcat_status=napcat_status,
        parse_stats=parse_stats,
        distribution_stats=distribution_stats,
        rule_breakdown=rule_breakdown,
    )


# ========== Bot 群组同步 ==========

@router.post("/bot/chats/sync", response_model=BotSyncResult)
async def sync_bot_chats(
    request: BotSyncRequest = None,
    db: AsyncSession = Depends(get_db),
    _: None = Depends(require_api_token),
):
    """
    同步 Bot 群组元信息
    遍历数据库中已知的群组，调用 Telegram API 刷新信息
    """
    from app.services.telegram_sync import refresh_telegram_chats

    cfg = await get_primary_bot_config(db, BotConfigPlatform.TELEGRAM, enabled_only=True)
    if not cfg or not cfg.bot_token:
        logger.warning("跳过群组同步：未找到可用的主 Telegram BotConfig")
        return BotSyncResult(total=0, updated=0, failed=0, inaccessible=0, details=[])

    try:
        result = await refresh_telegram_chats(
            db,
            bot_config=cfg,
            chat_id_filter=(request.chat_id if request else None),
            enabled_only=(not (request and request.chat_id)),
            fetch_permissions=True,
        )
    except ValueError as e:
        raise HTTPException(status_code=400, detail=str(e))

    return BotSyncResult(
        total=result["total"],
        updated=result["updated"],
        failed=result["failed"],
        inaccessible=result.get("inaccessible", 0),
        details=result["details"],
    )


# ========== 存储统计 ==========

@router.get("/storage/stats", response_model=StorageStatsResponse)
async def get_storage_stats(
    db: AsyncSession = Depends(get_db),
    _: None = Depends(require_api_token),
):
    """获取存储统计信息"""
    import os
    from pathlib import Path
    from app.core.config import settings
    
    storage_path = Path(settings.storage_local_root)
    total_bytes = 0
    media_count = 0
    by_type: dict = {}
    
    if storage_path.exists():
        for file in storage_path.rglob("*"):
            if file.is_file():
                size = file.stat().st_size
                total_bytes += size
                media_count += 1
                
                ext = file.suffix.lower()
                by_type[ext] = by_type.get(ext, 0) + size
    
    # 按平台统计（从数据库）
    from app.models import Content
    result = await db.execute(
        select(Content.platform, func.count(Content.id)).group_by(Content.platform)
    )
    by_platform = {str(row[0].value): row[1] for row in result.all()}
    
    return StorageStatsResponse(
        total_bytes=total_bytes,
        media_count=media_count,
        by_platform=by_platform,
        by_type=by_type,
    )



# ========== 辅助函数 ==========

async def _load_chat_rule_map(db: AsyncSession, chat_ids: List[int]) -> dict[int, dict]:
    if not chat_ids:
        return {}

    result = await db.execute(
        select(DistributionTarget.bot_chat_id, DistributionRule.id, DistributionRule.name)
        .join(DistributionRule, DistributionRule.id == DistributionTarget.rule_id)
        .where(DistributionTarget.bot_chat_id.in_(chat_ids))
        .order_by(DistributionRule.priority.desc(), DistributionRule.id.asc())
    )

    rule_map: dict[int, dict] = {}
    for bot_chat_id, rule_id, rule_name in result.all():
        bucket = rule_map.setdefault(bot_chat_id, {"ids": [], "names": []})
        bucket["ids"].append(rule_id)
        bucket["names"].append(rule_name)
    return rule_map


def _chat_to_response(chat: BotChat, rule_info: Optional[dict] = None) -> BotChatResponse:
    """将 BotChat 模型转换为响应对象"""
    rule_ids = list((rule_info or {}).get("ids", []))
    rule_names = list((rule_info or {}).get("names", []))

    return BotChatResponse(
        id=chat.id,
        bot_config_id=chat.bot_config_id,
        chat_id=chat.chat_id,
        chat_type=chat.chat_type.value if chat.chat_type else "unknown",
        title=chat.title,
        username=chat.username,
        description=chat.description,
        member_count=chat.member_count,
        is_admin=chat.is_admin or False,
        can_post=chat.can_post or False,
        enabled=chat.enabled or False,
        nsfw_chat_id=chat.nsfw_chat_id,
        total_pushed=chat.total_pushed or 0,
        last_pushed_at=chat.last_pushed_at,
        is_accessible=chat.is_accessible if chat.is_accessible is not None else True,
        last_sync_at=chat.last_sync_at,
        sync_error=chat.sync_error,
        applied_rule_ids=rule_ids,
        applied_rule_names=rule_names,
        applied_rule_count=len(rule_ids),
        created_at=chat.created_at,
        updated_at=chat.updated_at,
    )
