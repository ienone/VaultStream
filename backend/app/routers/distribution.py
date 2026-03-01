"""
功能描述：分发规则管理 API
包含：规则增删改查、规则预览、目标管理、渲染配置预设
调用方式：需要 API Token
"""
from typing import List, Optional, Dict, Any
from datetime import datetime
from fastapi import APIRouter, Depends, Query, HTTPException
from sqlalchemy import select, and_, update
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.database import get_db
from app.models import DistributionRule, Content, PushedRecord, ReviewStatus, ContentStatus, BotChat, DistributionTarget
from app.constants import Platform, DEFAULT_RENDER_CONFIG_PRESETS
from app.schemas import (
    DistributionRuleCreate, DistributionRuleUpdate, DistributionRuleResponse,
    RulePreviewResponse, RulePreviewStats,
    TargetUsageInfo, TargetListResponse, TargetTestRequest, TargetTestResponse,
    BatchTargetUpdateRequest, BatchTargetUpdateResponse,
    RenderConfigPreset,
    DistributionTargetCreate, DistributionTargetUpdate, DistributionTargetResponse,
)
from app.core.logging import logger
from app.core.dependencies import require_api_token


router = APIRouter()

_TELEGRAM_CHAT_TYPES = {"channel", "group", "supergroup", "private"}
_QQ_CHAT_TYPES = {"qq_group", "qq_private"}


def _normalize_chat_type(chat_type: Any) -> str:
    if isinstance(chat_type, str):
        return chat_type
    return str(getattr(chat_type, "value", chat_type))


def _platform_from_chat_type(chat_type: Any) -> str:
    normalized = _normalize_chat_type(chat_type)
    if normalized in _QQ_CHAT_TYPES:
        return Platform.QQ.value
    return Platform.TELEGRAM.value


def _chat_types_for_platform(platform: str) -> set[str]:
    if platform == Platform.TELEGRAM.value:
        return _TELEGRAM_CHAT_TYPES
    if platform == Platform.QQ.value:
        return _QQ_CHAT_TYPES
    raise HTTPException(status_code=400, detail=f"Unsupported platform: {platform}")





@router.post("/distribution-rules", response_model=DistributionRuleResponse)
async def create_distribution_rule(
    rule: DistributionRuleCreate,
    db: AsyncSession = Depends(get_db),
    _: None = Depends(require_api_token),
):
    """创建分发规则"""
    from app.services.distribution_rule_service import DistributionRuleService
    service = DistributionRuleService(db)
    
    db_rule = await service.create_rule(rule)
    
    # 规则变动后，自动刷新队列状态和排期
    from app.services.distribution import DistributionEngine
    engine = DistributionEngine(db)
    await engine.refresh_queue_by_rules()
    
    logger.info(f"分发规则已创建并刷新队列: {db_rule.name} (ID: {db_rule.id})")
    return db_rule

@router.get("/distribution-rules", response_model=List[DistributionRuleResponse])
async def list_distribution_rules(
    enabled: Optional[bool] = None,
    db: AsyncSession = Depends(get_db),
    _: None = Depends(require_api_token),
):
    """获取所有分发规则"""
    from app.services.distribution_rule_service import DistributionRuleService
    return await DistributionRuleService(db).list_rules(enabled)

@router.get("/distribution-rules/{rule_id}", response_model=DistributionRuleResponse)
async def get_distribution_rule(
    rule_id: int,
    db: AsyncSession = Depends(get_db),
    _: None = Depends(require_api_token),
):
    """获取单个分发规则"""
    from app.services.distribution_rule_service import DistributionRuleService
    return await DistributionRuleService(db).get_rule(rule_id)

@router.patch("/distribution-rules/{rule_id}", response_model=DistributionRuleResponse)
async def update_distribution_rule(
    rule_id: int,
    rule_update: DistributionRuleUpdate,
    db: AsyncSession = Depends(get_db),
    _: None = Depends(require_api_token),
):
    """更新分发规则"""
    from app.services.distribution_rule_service import DistributionRuleService
    service = DistributionRuleService(db)
    db_rule = await service.update_rule(rule_id, rule_update)
    
    # 规则变动后，自动刷新队列状态和排期
    from app.services.distribution import DistributionEngine
    engine = DistributionEngine(db)
    await engine.refresh_queue_by_rules()
    
    logger.info(f"分发规则已更新并刷新队列: {db_rule.name} (ID: {db_rule.id})")
    return db_rule

@router.delete("/distribution-rules/{rule_id}")
async def delete_distribution_rule(
    rule_id: int,
    db: AsyncSession = Depends(get_db),
    _: None = Depends(require_api_token),
):
    """删除分发规则"""
    from app.services.distribution_rule_service import DistributionRuleService
    await DistributionRuleService(db).delete_rule(rule_id)
    
    # 规则变动后，自动刷新队列状态和排期
    from app.services.distribution import DistributionEngine
    engine = DistributionEngine(db)
    await engine.refresh_queue_by_rules()
    
    logger.info(f"分发规则已删除并刷新队列: ID={rule_id}")
    return {"status": "deleted", "id": rule_id}


@router.get("/distribution-rules/{rule_id}/preview", response_model=RulePreviewResponse)
async def preview_distribution_rule(
    rule_id: int,
    hours_ahead: int = Query(default=24, ge=1, le=168, description="预览未来多少小时"),
    limit: int = Query(default=50, ge=1, le=200, description="最大返回条数"),
    db: AsyncSession = Depends(get_db),
    _: None = Depends(require_api_token),
):
    """预览规则下的内容分发情况（统一状态：will_push/filtered/pending_review）。"""
    from app.services.distribution_rule_service import DistributionRuleService
    return await DistributionRuleService(db).preview_rule(rule_id, hours_ahead=hours_ahead, limit=limit)


@router.get("/distribution-rules/preview/stats", response_model=List[RulePreviewStats])
async def get_all_rules_preview_stats(
    db: AsyncSession = Depends(get_db),
    _: None = Depends(require_api_token),
):
    """获取所有规则的预览统计（统一状态口径）。"""
    from app.services.distribution_rule_service import DistributionRuleService
    return await DistributionRuleService(db).get_all_rules_preview_stats()


@router.post("/distribution/trigger-run")
async def trigger_distribution_run(
    _: None = Depends(require_api_token),
):
    """手动触发分发任务（对所有已审批的 parse_success 内容入队）"""
    from app.core.database import AsyncSessionLocal
    
    async with AsyncSessionLocal() as session:
        result = await session.execute(
            select(Content).where(
                Content.status == ContentStatus.PARSE_SUCCESS,
                Content.review_status.in_([ReviewStatus.APPROVED, ReviewStatus.AUTO_APPROVED]),
            ).limit(100)
        )
        contents = result.scalars().all()
        
        from app.services.distribution import enqueue_content
        total = 0
        for content in contents:
            count = await enqueue_content(content.id, session=session)
            total += count
    
    return {"status": "triggered", "enqueued_count": total}


@router.get("/distribution-rules/{rule_id}/targets", response_model=List[DistributionTargetResponse])
async def list_rule_targets(
    rule_id: int,
    db: AsyncSession = Depends(get_db),
    _: None = Depends(require_api_token),
):
    """获取规则的所有分发目标"""
    from app.services.distribution_rule_service import DistributionRuleService
    targets = await DistributionRuleService(db).list_rule_targets(rule_id)
    return [DistributionTargetResponse.model_validate(t) for t in targets]


@router.post("/distribution-rules/{rule_id}/targets", response_model=DistributionTargetResponse, status_code=201)
async def create_rule_target(
    rule_id: int,
    target: DistributionTargetCreate,
    db: AsyncSession = Depends(get_db),
    _: None = Depends(require_api_token),
):
    """为规则添加分发目标"""
    from app.services.distribution_rule_service import DistributionRuleService
    db_target, inserted = await DistributionRuleService(db).create_rule_target(rule_id, target)
    
    logger.info(
        f"Created distribution target: rule_id={rule_id}, chat={target.bot_chat_id}, "
        f"enabled={db_target.enabled}, backfilled_success={inserted}"
    )

    return DistributionTargetResponse.model_validate(db_target)


@router.patch("/distribution-rules/{rule_id}/targets/{target_id}", response_model=DistributionTargetResponse)
async def update_rule_target(
    rule_id: int,
    target_id: int,
    update: DistributionTargetUpdate,
    db: AsyncSession = Depends(get_db),
    _: None = Depends(require_api_token),
):
    """更新分发目标配置"""
    from app.services.distribution_rule_service import DistributionRuleService
    db_target = await DistributionRuleService(db).update_rule_target(rule_id, target_id, update)
    
    logger.info(f"Updated distribution target: id={target_id}")
    return DistributionTargetResponse.model_validate(db_target)


@router.delete("/distribution-rules/{rule_id}/targets/{target_id}", status_code=204)
async def delete_rule_target(
    rule_id: int,
    target_id: int,
    db: AsyncSession = Depends(get_db),
    _: None = Depends(require_api_token),
):
    """删除分发目标"""
    from app.services.distribution_rule_service import DistributionRuleService
    await DistributionRuleService(db).delete_rule_target(rule_id, target_id)
    
    logger.info(f"Deleted distribution target: id={target_id}")


# ========== Target Management APIs ==========

@router.get("/targets", response_model=TargetListResponse)
async def list_all_targets(
    platform: Optional[str] = Query(None, description="Filter by platform: telegram/qq"),
    enabled: Optional[bool] = Query(None, description="Filter by enabled status"),
    db: AsyncSession = Depends(get_db),
    _: None = Depends(require_api_token),
):
    """
    List all distribution targets across all rules.
    
    Returns aggregated target information including:
    - Which rules use each target
    - Push statistics
    - Configuration details
    """
    # 适配 Phase 4: 使用关联查询直接从 distribution_targets 表获取数据
    stmt = (
        select(DistributionTarget, BotChat, DistributionRule)
        .join(BotChat, DistributionTarget.bot_chat_id == BotChat.id)
        .join(DistributionRule, DistributionTarget.rule_id == DistributionRule.id)
    )
    
    # 应用过滤条件
    if platform:
        stmt = stmt.where(BotChat.chat_type.in_(_chat_types_for_platform(platform)))
    
    if enabled is not None:
        stmt = stmt.where(DistributionTarget.enabled == enabled)
        
    result = await db.execute(stmt)
    all_records = result.all()
    
    # Aggregate targets by (platform, target_id)
    target_map: Dict[tuple, Dict] = {}  # key: (platform, target_id)
    
    for dt, chat, rule in all_records:
        target_platform = _platform_from_chat_type(chat.chat_type)
        target_id = chat.chat_id
        
        key = (target_platform, target_id)
        
        if key not in target_map:
            target_map[key] = {
                "target_platform": target_platform,
                "target_id": target_id,
                "enabled": dt.enabled,
                "rule_count": 0,
                "rule_ids": [],
                "rule_names": [],
                "merge_forward": dt.merge_forward,
                "use_author_name": dt.use_author_name,
                "summary": dt.summary,
                "render_config": dt.render_config,
                "total_pushed": 0,
                "last_pushed_at": None,
            }
        
        target_map[key]["rule_count"] += 1
        target_map[key]["rule_ids"].append(rule.id)
        target_map[key]["rule_names"].append(rule.name)
    
    # Get push statistics for all targets
    if target_map:
        from collections import defaultdict
        all_target_ids = [key[1] for key in target_map.keys()]
        
        # 统计该 target 的所有推送记录，不再按 content_id 过滤（移除硬编码 ID 依赖）
        push_result = await db.execute(
            select(PushedRecord).where(
                PushedRecord.target_id.in_(all_target_ids)
            )
        )
        all_pushes = push_result.scalars().all()
        
        # Group pushes by target_id
        pushes_by_target = defaultdict(list)
        for push in all_pushes:
            pushes_by_target[push.target_id].append(push)
        
        # Update statistics for each target
        for key, target_info in target_map.items():
            _, target_id = key
            pushes = pushes_by_target.get(target_id, [])
            target_info["total_pushed"] = len(pushes)
            
            # Get last push timestamp
            if pushes:
                last_push = max(pushes, key=lambda p: p.pushed_at)
                target_info["last_pushed_at"] = last_push.pushed_at
    
    targets_list = [TargetUsageInfo(**info) for info in target_map.values()]
    
    # Sort by rule count (most used first), then by last pushed
    targets_list.sort(
        key=lambda t: (t.rule_count, t.last_pushed_at or datetime.min),
        reverse=True
    )
    
    return TargetListResponse(
        total=len(targets_list),
        targets=targets_list
    )


@router.post("/targets/test", response_model=TargetTestResponse)
async def test_target_connection(
    request: TargetTestRequest,
    _: None = Depends(require_api_token),
):
    """
    Test connection to a distribution target.
    
    For Telegram: verifies bot can access the chat
    For QQ: verifies Napcat API connection
    """
    platform = request.platform.lower()
    target_id = request.target_id
    
    try:
        if platform == Platform.TELEGRAM.value:
            from app.push.telegram import TelegramPushService
            
            service = TelegramPushService()
            bot = await service._get_bot()
            
            # Try to get chat
            try:
                chat = await bot.get_chat(target_id)
                return TargetTestResponse(
                    platform=platform,
                    target_id=target_id,
                    status="ok",
                    message=f"Connected to chat: {chat.title or target_id}",
                    details={
                        "title": chat.title,
                        "type": chat.type,
                        "username": chat.username
                    }
                )
            except Exception as e:
                return TargetTestResponse(
                    platform=platform,
                    target_id=target_id,
                    status="error",
                    message=f"Unable to access chat: {str(e)}"
                )
        
        elif platform == Platform.QQ.value:
            from app.push.napcat import NapcatPushService
            
            service = NapcatPushService()
            
            # Try to get group info
            try:
                # Parse target_id (might be prefixed with group:)
                group_id = target_id
                if target_id.startswith("group:"):
                    group_id = target_id.split(":", 1)[1]
                
                # Validate group_id is numeric
                try:
                    group_id_int = int(group_id)
                except ValueError:
                    return TargetTestResponse(
                        platform=platform,
                        target_id=target_id,
                        status="error",
                        message=f"Invalid QQ group ID format: '{target_id}'. Must be numeric."
                    )
                
                client = await service._get_client()
                response = await client.post("/get_group_info", json={"group_id": group_id_int})
                data = response.json()
                
                if data.get("status") == "ok" and data.get("data"):
                    group_info = data["data"]
                    return TargetTestResponse(
                        platform=platform,
                        target_id=target_id,
                        status="ok",
                        message=f"Connected to group: {group_info.get('group_name', group_id)}",
                        details=group_info
                    )
                else:
                    return TargetTestResponse(
                        platform=platform,
                        target_id=target_id,
                        status="error",
                        message="Unable to get group information"
                    )
            except Exception as e:
                return TargetTestResponse(
                    platform=platform,
                    target_id=target_id,
                    status="error",
                    message=f"Connection failed: {str(e)}"
                )
        
        else:
            raise HTTPException(
                status_code=400,
                detail=f"Unsupported platform: {platform}"
            )
    
    except Exception as e:
        logger.error(f"Target connection test failed: {e}")
        return TargetTestResponse(
            platform=platform,
            target_id=target_id,
            status="error",
            message=f"Connection test failed: {str(e)}"
        )


@router.post("/targets/batch-update", response_model=BatchTargetUpdateResponse)
async def batch_update_targets(
    request: BatchTargetUpdateRequest,
    db: AsyncSession = Depends(get_db),
    _: None = Depends(require_api_token),
):
    """
    Batch update target settings across multiple rules.
    """
    updated_rule_ids = []
    
    try:
        # 适配 Phase 4: 使用 SQL 直接批量更新 distribution_targets 表
        # 1. 找到对应的 BotChat ID
        chat_types = _chat_types_for_platform(request.target_platform)
        chat_query = select(BotChat.id).where(
            and_(
                BotChat.chat_type.in_(chat_types),
                BotChat.chat_id == str(request.target_id)
            )
        )
        chat_result = await db.execute(chat_query)
        bot_chat_id = chat_result.scalar_one_or_none()
        if not bot_chat_id:
            raise HTTPException(status_code=404, detail="Target chat not found")

        # 2. 构建更新语句
        stmt = (
            update(DistributionTarget)
            .where(
                and_(
                    DistributionTarget.rule_id.in_(request.rule_ids),
                    DistributionTarget.bot_chat_id == bot_chat_id
                )
            )
        )
        
        update_values = {}
        if request.enabled is not None:
            update_values["enabled"] = request.enabled
        if request.merge_forward is not None:
            update_values["merge_forward"] = request.merge_forward
        if request.render_config is not None:
            update_values["render_config"] = request.render_config
            
        if update_values:
            await db.execute(stmt.values(**update_values))
            updated_rule_ids = list(request.rule_ids)
            await db.commit()
            logger.info(f"Batch updated {len(updated_rule_ids)} targets for chat {bot_chat_id}")
        
        return BatchTargetUpdateResponse(
            updated_count=len(updated_rule_ids),
            updated_rules=updated_rule_ids,
            message=f"Updated target in {len(updated_rule_ids)} rules"
        )
    
    except Exception as e:
        await db.rollback()
        logger.error(f"Batch update failed: {e}")
        raise HTTPException(
            status_code=500,
            detail=f"Batch update failed: {str(e)}"
        )


# ========== Render Config Preset APIs ==========

# Convert raw presets to Pydantic models for response consistency
BUILTIN_PRESETS: List[RenderConfigPreset] = [
    RenderConfigPreset(**p) for p in DEFAULT_RENDER_CONFIG_PRESETS
]


@router.get("/render-config-presets", response_model=List[RenderConfigPreset])
async def list_render_config_presets(
    _: None = Depends(require_api_token),
):
    """List all render config presets (built-in + custom)"""
    return BUILTIN_PRESETS


@router.get("/render-config-presets/{preset_id}", response_model=RenderConfigPreset)
async def get_render_config_preset(
    preset_id: str,
    _: None = Depends(require_api_token),
):
    """Get a specific render config preset"""
    for preset in BUILTIN_PRESETS:
        if preset.id == preset_id:
            return preset

    raise HTTPException(status_code=404, detail="Preset not found")
