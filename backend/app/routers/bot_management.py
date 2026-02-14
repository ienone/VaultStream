"""
功能描述：Bot 管理 API
包含：Bot 群组/频道管理、状态查询、同步功能
调用方式：需要 API Token
"""
from typing import List, Optional
from datetime import datetime, timedelta
from fastapi import APIRouter, Depends, HTTPException, Query, BackgroundTasks
from sqlalchemy import select, func, desc, update
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.database import get_db
from app.core.dependencies import require_api_token
from app.core.logging import logger
from app.core.config import settings
from app.core.time_utils import utcnow
from app.models import (
    BotChat,
    BotChatType,
    PushedRecord,
    DistributionRule,
    DistributionTarget,
    BotRuntime,
    Task,
    TaskStatus,
    BotConfig,
    BotConfigPlatform,
    Content,
    ContentStatus,
    ContentQueueItem,
    QueueItemStatus,
)
from app.schemas import (
    BotChatCreate, BotChatUpdate, BotChatResponse,
    BotStatusResponse, BotSyncRequest, StorageStatsResponse, HealthDetailResponse,
    BotChatUpsert, BotHeartbeat, BotRuntimeResponse, BotSyncResult,
    RepushFailedRequest, RepushFailedResponse,
    BotChatRulesResponse, BotChatRuleAssignRequest, ChatRuleBindingInfo, BotChatRuleSummaryItem,
)
from app.core.events import event_bus
from app.services.bot_config_runtime import get_primary_bot_config

router = APIRouter()


def _empty_distribution_bucket() -> dict[str, int]:
    return {
        "will_push": 0,
        "filtered": 0,
        "pending_review": 0,
        "pushed": 0,
        "total": 0,
    }


def _classify_distribution_status(
    status: QueueItemStatus,
    needs_approval: bool,
    approved_at: Optional[datetime],
) -> str:
    # 业务语义：解析成功后的看板只保留四种分发状态。
    if status == QueueItemStatus.SUCCESS:
        return "pushed"
    if status in (QueueItemStatus.SKIPPED, QueueItemStatus.CANCELED):
        return "filtered"
    if status == QueueItemStatus.PENDING and needs_approval and approved_at is None:
        return "pending_review"
    # FAILED 归入 will_push，表示仍处于待处理队列（可重试或手动干预）。
    if status in (QueueItemStatus.PENDING, QueueItemStatus.SCHEDULED, QueueItemStatus.PROCESSING, QueueItemStatus.FAILED):
        return "will_push"
    return "filtered"


async def _build_pipeline_stats(db: AsyncSession) -> tuple[dict, dict, dict[str, dict]]:
    parse_stats = {
        "unprocessed": 0,
        "processing": 0,
        "parse_success": 0,
        "parse_failed": 0,
        "total": 0,
    }

    content_status_result = await db.execute(
        select(Content.status, func.count(Content.id)).group_by(Content.status)
    )
    for status, count in content_status_result.all():
        count_int = int(count or 0)
        parse_stats["total"] += count_int
        if status == ContentStatus.UNPROCESSED:
            parse_stats["unprocessed"] += count_int
        elif status == ContentStatus.PROCESSING:
            parse_stats["processing"] += count_int
        elif status == ContentStatus.PARSE_SUCCESS:
            parse_stats["parse_success"] += count_int
        elif status == ContentStatus.PARSE_FAILED:
            parse_stats["parse_failed"] += count_int

    distribution_stats = _empty_distribution_bucket()
    rule_breakdown: dict[str, dict] = {}

    queue_rows = await db.execute(
        select(
            ContentQueueItem.rule_id,
            ContentQueueItem.status,
            ContentQueueItem.needs_approval,
            ContentQueueItem.approved_at,
            func.count(ContentQueueItem.id),
        )
        .join(Content, Content.id == ContentQueueItem.content_id)
        .where(Content.status == ContentStatus.PARSE_SUCCESS)
        .group_by(
            ContentQueueItem.rule_id,
            ContentQueueItem.status,
            ContentQueueItem.needs_approval,
            ContentQueueItem.approved_at,
        )
    )

    for rule_id, status, needs_approval, approved_at, count in queue_rows.all():
        count_int = int(count or 0)
        bucket_key = _classify_distribution_status(status, bool(needs_approval), approved_at)

        distribution_stats[bucket_key] += count_int
        distribution_stats["total"] += count_int

        rule_key = str(rule_id)
        if rule_key not in rule_breakdown:
            rule_breakdown[rule_key] = _empty_distribution_bucket()
        rule_breakdown[rule_key][bucket_key] += count_int
        rule_breakdown[rule_key]["total"] += count_int

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


@router.get("/bot/chats/rules/summary", response_model=List[BotChatRuleSummaryItem])
async def get_bot_chat_rules_summary(
    db: AsyncSession = Depends(get_db),
    _: None = Depends(require_api_token),
):
    """获取所有群组的规则摘要（用于群组卡片展示）"""
    chats_result = await db.execute(select(BotChat.id, BotChat.chat_id).order_by(BotChat.id.asc()))
    chat_rows = chats_result.all()
    if not chat_rows:
        return []

    rule_map = await _load_chat_rule_map(db, [row.id for row in chat_rows])
    items: List[BotChatRuleSummaryItem] = []
    for row in chat_rows:
        info = rule_map.get(row.id) or {"ids": [], "names": []}
        items.append(BotChatRuleSummaryItem(
            chat_id=row.chat_id,
            rule_ids=info["ids"],
            rule_names=info["names"],
            rule_count=len(info["ids"]),
        ))
    return items


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
    from telegram import Bot
    from telegram.error import TelegramError

    cfg = await get_primary_bot_config(db, BotConfigPlatform.TELEGRAM, enabled_only=True)
    if not cfg or not cfg.bot_token:
        raise HTTPException(status_code=400, detail="未找到可用的主 Telegram BotConfig")
    
    # 构建查询
    query = select(BotChat).where(BotChat.bot_config_id == cfg.id)
    if request and request.chat_id:
        query = query.where(BotChat.chat_id == request.chat_id)
    else:
        query = query.where(BotChat.enabled == True)
    
    result = await db.execute(query)
    chats = result.scalars().all()
    
    if not chats:
        return BotSyncResult(total=0, updated=0, failed=0, inaccessible=0, details=[])
    
    # 创建 Bot 实例
    bot = Bot(token=cfg.bot_token)
    now = utcnow()
    
    updated = 0
    failed = 0
    inaccessible = 0
    details = []
    
    for chat in chats:
        try:
            # 获取群组信息
            tg_chat = await bot.get_chat(chat.chat_id)
            
            # 更新信息
            chat.title = tg_chat.title
            chat.username = tg_chat.username
            chat.description = tg_chat.description
            chat.chat_type = BotChatType(tg_chat.type)
            
            # 获取成员数（可能失败）
            try:
                chat.member_count = await bot.get_chat_member_count(chat.chat_id)
            except:
                pass
            
            # 获取 Bot 权限
            try:
                bot_member = await bot.get_chat_member(chat.chat_id, (await bot.get_me()).id)
                chat.is_admin = bot_member.status in ['administrator', 'creator']
                chat.can_post = getattr(bot_member, 'can_post_messages', True) if chat.is_admin else False
            except:
                pass
            
            chat.is_accessible = True
            chat.last_sync_at = now
            chat.sync_error = None
            updated += 1
            details.append({"chat_id": chat.chat_id, "title": chat.title, "status": "updated"})
            await event_bus.publish("bot_sync_progress", {
                "chat_id": chat.chat_id,
                "title": chat.title,
                "status": "updated",
                "updated": updated,
                "failed": failed,
                "inaccessible": inaccessible,
                "total": len(chats),
                "timestamp": now.isoformat(),
            })
            
        except TelegramError as e:
            error_msg = str(e)
            if "chat not found" in error_msg.lower() or "forbidden" in error_msg.lower():
                chat.is_accessible = False
                inaccessible += 1
            else:
                failed += 1
            chat.sync_error = error_msg
            chat.last_sync_at = now
            details.append({"chat_id": chat.chat_id, "title": chat.title, "status": "failed", "error": error_msg})
            await event_bus.publish("bot_sync_progress", {
                "chat_id": chat.chat_id,
                "title": chat.title,
                "status": "failed",
                "error": error_msg,
                "updated": updated,
                "failed": failed,
                "inaccessible": inaccessible,
                "total": len(chats),
                "timestamp": now.isoformat(),
            })
            logger.warning(f"同步群组失败 {chat.chat_id}: {e}")
        except Exception as e:
            failed += 1
            chat.sync_error = str(e)
            chat.last_sync_at = now
            details.append({"chat_id": chat.chat_id, "title": chat.title, "status": "error", "error": str(e)})
            await event_bus.publish("bot_sync_progress", {
                "chat_id": chat.chat_id,
                "title": chat.title,
                "status": "error",
                "error": str(e),
                "updated": updated,
                "failed": failed,
                "inaccessible": inaccessible,
                "total": len(chats),
                "timestamp": now.isoformat(),
            })
            logger.error(f"同步群组异常 {chat.chat_id}: {e}")
    
    await db.commit()
    await bot.close()

    await event_bus.publish("bot_sync_completed", {
        "total": len(chats),
        "updated": updated,
        "failed": failed,
        "inaccessible": inaccessible,
        "timestamp": now.isoformat(),
    })
    
    return BotSyncResult(
        total=len(chats),
        updated=updated,
        failed=failed,
        inaccessible=inaccessible,
        details=details,
    )


# ========== 重推失败任务 ==========

@router.post("/tasks/repush-failed", response_model=RepushFailedResponse)
async def repush_failed_tasks(
    request: RepushFailedRequest,
    db: AsyncSession = Depends(get_db),
    _: None = Depends(require_api_token),
):
    """重新推送失败的任务"""
    now = utcnow()
    cutoff_time = now - timedelta(minutes=request.older_than_minutes)
    
    # 构建查询
    query = select(Task).where(
        Task.status == TaskStatus.FAILED,
        Task.updated_at < cutoff_time,
    )
    
    if request.task_ids:
        query = query.where(Task.id.in_(request.task_ids))
    
    query = query.limit(request.limit)
    
    result = await db.execute(query)
    tasks = result.scalars().all()
    
    repushed_ids = []
    for task in tasks:
        task.status = TaskStatus.PENDING
        task.attempts = 0
        task.error = None
        task.next_run_at = now
        repushed_ids.append(task.id)
    
    await db.commit()
    
    logger.info(f"重新推送 {len(repushed_ids)} 个失败任务")
    
    return RepushFailedResponse(
        repushed_count=len(repushed_ids),
        task_ids=repushed_ids,
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


# ========== 健康检查详细 ==========

@router.get("/health/detail", response_model=HealthDetailResponse)
async def get_health_detail(
    db: AsyncSession = Depends(get_db),
    _: None = Depends(require_api_token),
):
    """获取详细健康检查信息"""
    from app.models import Task, TaskStatus
    import time
    
    # 数据库检查
    try:
        await db.execute(select(func.count()).select_from(BotChat))
        db_status = "healthy"
    except Exception as e:
        db_status = f"error: {e}"
    
    # 存储检查
    from pathlib import Path
    storage_path = Path(settings.storage_local_root)
    storage_status = "healthy" if storage_path.exists() else "missing"
    
    # Bot 状态
    bot_parts = []
    telegram_primary_result = await db.execute(
        select(func.count(BotConfig.id)).where(
            BotConfig.platform == BotConfigPlatform.TELEGRAM,
            BotConfig.enabled == True,
            BotConfig.is_primary == True,
        )
    )
    if (telegram_primary_result.scalar() or 0) > 0:
        bot_parts.append("telegram:enabled")
    qq_primary_result = await db.execute(
        select(func.count(BotConfig.id)).where(
            BotConfig.platform == BotConfigPlatform.QQ,
            BotConfig.enabled == True,
            BotConfig.is_primary == True,
        )
    )
    if (qq_primary_result.scalar() or 0) > 0:
        bot_parts.append("napcat:enabled")
    bot_status = ", ".join(bot_parts) if bot_parts else "disabled"
    
    # 队列状态
    result = await db.execute(
        select(func.count(Task.id)).where(Task.status == TaskStatus.PENDING)
    )
    queue_pending = result.scalar() or 0
    
    result = await db.execute(
        select(func.count(Task.id)).where(Task.status == TaskStatus.FAILED)
    )
    queue_failed = result.scalar() or 0
    
    return HealthDetailResponse(
        status="healthy" if db_status == "healthy" else "degraded",
        database=db_status,
        storage=storage_status,
        bot=bot_status,
        queue_pending=queue_pending,
        queue_failed=queue_failed,
        uptime_seconds=0,  # TODO: 从进程启动时间计算
        version="0.1.0",
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
