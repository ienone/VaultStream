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
from app.models import BotChat, BotChatType, PushedRecord, DistributionRule, BotRuntime, Task, TaskStatus
from app.schemas import (
    BotChatCreate, BotChatUpdate, BotChatResponse,
    BotStatusResponse, BotSyncRequest, StorageStatsResponse, HealthDetailResponse,
    BotChatUpsert, BotHeartbeat, BotRuntimeResponse, BotSyncResult,
    RepushFailedRequest, RepushFailedResponse
)

router = APIRouter()


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
    
    return [_chat_to_response(chat) for chat in chats]


@router.post("/bot/chats", response_model=BotChatResponse)
async def create_bot_chat(
    chat: BotChatCreate,
    db: AsyncSession = Depends(get_db),
    _: None = Depends(require_api_token),
):
    """手动添加 Bot 群组/频道"""
    # 检查是否已存在
    result = await db.execute(
        select(BotChat).where(BotChat.chat_id == chat.chat_id)
    )
    if result.scalar_one_or_none():
        raise HTTPException(status_code=400, detail="Chat already exists")
    
    db_chat = BotChat(
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
    return _chat_to_response(chat)


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
    result = await db.execute(
        select(BotChat).where(BotChat.chat_id == chat.chat_id)
    )
    db_chat = result.scalar_one_or_none()
    
    now = utcnow()
    if db_chat:
        # 更新已存在的记录
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
    # 获取运行时状态
    runtime_result = await db.execute(select(BotRuntime).where(BotRuntime.id == 1))
    runtime = runtime_result.scalar_one_or_none()
    
    # 统计关联的群组数
    result = await db.execute(select(func.count(BotChat.id)).where(BotChat.enabled == True))
    chat_count = result.scalar() or 0
    
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
    bot_username = None
    bot_id = None
    now = utcnow()
    
    if runtime:
        bot_username = runtime.bot_username
        bot_id = int(runtime.bot_id) if runtime.bot_id else None
        if runtime.last_heartbeat_at:
            time_since_heartbeat = (now - runtime.last_heartbeat_at).total_seconds()
            is_running = time_since_heartbeat < 120
        if runtime.started_at and is_running:
            uptime_seconds = int((now - runtime.started_at).total_seconds())
    
    # Napcat 连接检查
    napcat_status = None
    if settings.enable_napcat and settings.napcat_api_base:
        import httpx
        try:
            headers = {}
            if settings.napcat_access_token:
                headers["Authorization"] = f"Bearer {settings.napcat_access_token.get_secret_value()}"
            async with httpx.AsyncClient(timeout=5.0) as client:
                resp = await client.get(f"{settings.napcat_api_base.rstrip('/')}/get_login_info", headers=headers)
                if resp.status_code == 200:
                    napcat_status = "online"
                else:
                    napcat_status = f"error:{resp.status_code}"
        except Exception as e:
            napcat_status = f"offline:{e}"
    elif settings.enable_napcat:
        napcat_status = "misconfigured"

    return BotStatusResponse(
        is_running=is_running,
        bot_username=bot_username,
        bot_id=bot_id,
        connected_chats=chat_count,
        total_pushed_today=today_pushed,
        uptime_seconds=uptime_seconds,
        napcat_status=napcat_status,
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
    
    if not settings.telegram_bot_token or not settings.telegram_bot_token.get_secret_value():
        raise HTTPException(status_code=400, detail="未配置 TELEGRAM_BOT_TOKEN")
    
    # 构建查询
    query = select(BotChat)
    if request and request.chat_id:
        query = query.where(BotChat.chat_id == request.chat_id)
    else:
        query = query.where(BotChat.enabled == True)
    
    result = await db.execute(query)
    chats = result.scalars().all()
    
    if not chats:
        return BotSyncResult(total=0, updated=0, failed=0, inaccessible=0, details=[])
    
    # 创建 Bot 实例
    bot = Bot(token=settings.telegram_bot_token.get_secret_value())
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
            logger.warning(f"同步群组失败 {chat.chat_id}: {e}")
        except Exception as e:
            failed += 1
            chat.sync_error = str(e)
            chat.last_sync_at = now
            details.append({"chat_id": chat.chat_id, "title": chat.title, "status": "error", "error": str(e)})
            logger.error(f"同步群组异常 {chat.chat_id}: {e}")
    
    await db.commit()
    await bot.close()
    
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
    if settings.enable_bot:
        bot_parts.append("telegram:enabled")
    if settings.enable_napcat:
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

def _chat_to_response(chat: BotChat) -> BotChatResponse:
    """将 BotChat 模型转换为响应对象"""
    return BotChatResponse(
        id=chat.id,
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
        created_at=chat.created_at,
        updated_at=chat.updated_at,
    )
