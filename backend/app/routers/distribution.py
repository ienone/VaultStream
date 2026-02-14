"""
功能描述：分发规则管理 API
包含：规则增删改查、规则预览、目标管理、渲染配置预设
调用方式：需要 API Token
"""
from typing import List, Optional, Dict, Any
from datetime import datetime, timedelta
from fastapi import APIRouter, Depends, HTTPException, Query
from sqlalchemy import select, desc, and_, update
from sqlalchemy.orm import selectinload
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.database import get_db
from app.models import DistributionRule, Content, PushedRecord, ReviewStatus, ContentStatus, DistributionTarget, BotChat
from app.constants import Platform, PREVIEW_CONTENT_IDS, DEFAULT_RENDER_CONFIG_PRESETS
from app.schemas import (
    DistributionRuleCreate, DistributionRuleUpdate, DistributionRuleResponse,
    RulePreviewResponse, RulePreviewItem, RulePreviewStats,
    TargetUsageInfo, TargetListResponse, TargetTestRequest, TargetTestResponse,
    BatchTargetUpdateRequest, BatchTargetUpdateResponse,
    RenderConfigPreset, RenderConfigPresetCreate, RenderConfigPresetUpdate
)
from app.core.logging import logger
from app.core.dependencies import require_api_token

router = APIRouter()


@router.post("/distribution-rules", response_model=DistributionRuleResponse)
async def create_distribution_rule(
    rule: DistributionRuleCreate,
    db: AsyncSession = Depends(get_db),
    _: None = Depends(require_api_token),
):
    """创建分发规则"""
    result = await db.execute(
        select(DistributionRule).where(DistributionRule.name == rule.name)
    )
    if result.scalar_one_or_none():
        raise HTTPException(status_code=400, detail="Rule name already exists")
    
    payload = rule.model_dump()
    db_rule = DistributionRule(**payload)
    db.add(db_rule)

    await db.commit()
    await db.refresh(db_rule)
    
    # 规则变动后，自动刷新队列状态和排期
    from app.distribution.engine import DistributionEngine
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
    query = select(DistributionRule).order_by(desc(DistributionRule.priority), DistributionRule.id)
    if enabled is not None:
        query = query.where(DistributionRule.enabled == enabled)
    result = await db.execute(query)
    return result.scalars().all()

@router.get("/distribution-rules/{rule_id}", response_model=DistributionRuleResponse)
async def get_distribution_rule(
    rule_id: int,
    db: AsyncSession = Depends(get_db),
    _: None = Depends(require_api_token),
):
    """获取单个分发规则"""
    result = await db.execute(select(DistributionRule).where(DistributionRule.id == rule_id))
    rule = result.scalar_one_or_none()
    if not rule:
        raise HTTPException(status_code=404, detail="Distribution rule not found")
    return rule

@router.patch("/distribution-rules/{rule_id}", response_model=DistributionRuleResponse)
async def update_distribution_rule(
    rule_id: int,
    rule_update: DistributionRuleUpdate,
    db: AsyncSession = Depends(get_db),
    _: None = Depends(require_api_token),
):
    """更新分发规则"""
    result = await db.execute(select(DistributionRule).where(DistributionRule.id == rule_id))
    db_rule = result.scalar_one_or_none()
    if not db_rule:
        raise HTTPException(status_code=404, detail="Distribution rule not found")
    
    update_data = rule_update.model_dump(exclude_unset=True)
    
    for key, value in update_data.items():
        setattr(db_rule, key, value)
    
    await db.commit()
    await db.refresh(db_rule)
    
    # 规则变动后，自动刷新队列状态和排期
    from app.distribution.engine import DistributionEngine
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
    result = await db.execute(select(DistributionRule).where(DistributionRule.id == rule_id))
    db_rule = result.scalar_one_or_none()
    if not db_rule:
        raise HTTPException(status_code=404, detail="Distribution rule not found")
    
    await db.delete(db_rule)
    await db.commit()
    
    # 规则变动后，自动刷新队列状态和排期
    from app.distribution.engine import DistributionEngine
    engine = DistributionEngine(db)
    await engine.refresh_queue_by_rules()
    
    logger.info(f"分发规则已删除并刷新队列: {db_rule.name} (ID: {rule_id})")
    return {"status": "deleted", "id": rule_id}


@router.get("/distribution-rules/{rule_id}/preview", response_model=RulePreviewResponse)
async def preview_distribution_rule(
    rule_id: int,
    hours_ahead: int = Query(default=24, ge=1, le=168, description="预览未来多少小时"),
    limit: int = Query(default=50, ge=1, le=200, description="最大返回条数"),
    db: AsyncSession = Depends(get_db),
    _: None = Depends(require_api_token),
):
    """
    预览规则下的内容分发情况
    
    返回匹配该规则的内容列表，包含每条内容的预计分发状态：
    - will_push: 将被推送
    - filtered_nsfw: 因 NSFW 策略被过滤
    - filtered_tag: 因标签不匹配被过滤
    - filtered_platform: 因平台不匹配被过滤
    - pending_review: 待人工审批
    - rate_limited: 因频率限制暂缓
    - already_pushed: 已推送过
    """
    # 加载关联的目标和 BotChat 以支持预览逻辑
    result = await db.execute(
        select(DistributionRule)
        .options(
            selectinload(DistributionRule.distribution_targets)
            .selectinload(DistributionTarget.bot_chat)
        )
        .where(DistributionRule.id == rule_id)
    )
    rule = result.scalar_one_or_none()
    if not rule:
        raise HTTPException(status_code=404, detail="Distribution rule not found")
    
    conditions = rule.match_conditions or {}
    
    content_query = select(Content).where(
        Content.status == ContentStatus.PARSE_SUCCESS
    ).order_by(desc(Content.created_at)).limit(limit * 2)
    
    content_result = await db.execute(content_query)
    all_contents = content_result.scalars().all()
    
    preview_items: List[RulePreviewItem] = []
    will_push_count = 0
    filtered_count = 0
    pending_review_count = 0
    rate_limited_count = 0
    
    # 适配 Phase 4: 使用 distribution_targets 关系表
    targets = rule.distribution_targets
    target_ids = [t.bot_chat.chat_id for t in targets if t.enabled and t.bot_chat.enabled]
    
    window_start = datetime.utcnow() - timedelta(seconds=rule.time_window or 3600)
    pushed_counts: dict[str, int] = {}
    if target_ids:
        for tid in target_ids:
            count_result = await db.execute(
                select(PushedRecord).where(
                    and_(
                        PushedRecord.target_id == tid,
                        PushedRecord.pushed_at >= window_start
                    )
                )
            )
            pushed_counts[tid] = len(count_result.scalars().all())
    
    for content in all_contents:
        if len(preview_items) >= limit:
            break
        
        status = "will_push"
        reason = None
        
        if "platform" in conditions:
            if conditions["platform"] != content.platform.value:
                status = "filtered_platform"
                reason = f"平台不匹配: 需要 {conditions['platform']}, 实际 {content.platform.value}"
        
        if status == "will_push" and "tags" in conditions:
            required_tags = conditions.get("tags", [])
            tags_match_mode = conditions.get("tags_match_mode", "any")
            exclude_tags = conditions.get("tags_exclude", [])
            content_tags = content.tags or []
            
            if exclude_tags and any(tag in content_tags for tag in exclude_tags):
                status = "filtered_tag"
                reason = f"包含排除标签: {[t for t in exclude_tags if t in content_tags]}"
            elif required_tags:
                if tags_match_mode == "all":
                    if not all(tag in content_tags for tag in required_tags):
                        status = "filtered_tag"
                        reason = f"标签不完全匹配: 需要全部 {required_tags}"
                else:
                    if not any(tag in content_tags for tag in required_tags):
                        status = "filtered_tag"
                        reason = f"标签不匹配: 需要任一 {required_tags}"
        
        if status == "will_push" and "is_nsfw" in conditions:
            if conditions["is_nsfw"] != content.is_nsfw:
                status = "filtered_nsfw"
                reason = f"NSFW状态不匹配: 规则要求 is_nsfw={conditions['is_nsfw']}"
        
        if status == "will_push" and content.is_nsfw:
            nsfw_policy = rule.nsfw_policy
            if nsfw_policy == "block":
                status = "filtered_nsfw"
                reason = "NSFW内容被阻止 (策略: block)"
        
        if status == "will_push" and rule.approval_required:
            if content.review_status not in [ReviewStatus.APPROVED, ReviewStatus.AUTO_APPROVED]:
                status = "pending_review"
                reason = f"需要人工审批 (当前状态: {content.review_status.value})"
        
        if status == "will_push" and target_ids:
            for tid in target_ids:
                pushed_result = await db.execute(
                    select(PushedRecord).where(
                        and_(
                            PushedRecord.content_id == content.id,
                            PushedRecord.target_id == tid
                        )
                    )
                )
                if pushed_result.scalar_one_or_none():
                    status = "already_pushed"
                    reason = f"已推送到 {tid}"
                    break
        
        if status == "will_push" and rule.rate_limit and target_ids:
            for tid in target_ids:
                if pushed_counts.get(tid, 0) >= rule.rate_limit:
                    status = "rate_limited"
                    reason = f"频率限制: {tid} 在 {rule.time_window or 3600}秒内已推送 {pushed_counts[tid]} 条 (限制 {rule.rate_limit})"
                    break
        
        if status == "will_push":
            will_push_count += 1
        elif status.startswith("filtered"):
            filtered_count += 1
        elif status == "pending_review":
            pending_review_count += 1
        elif status == "rate_limited":
            rate_limited_count += 1
        
        thumbnail = content.cover_url
        if not thumbnail and content.raw_metadata and isinstance(content.raw_metadata, dict):
            media_list = content.raw_metadata.get("media") or content.raw_metadata.get("pics") or []
            if media_list and isinstance(media_list, list) and len(media_list) > 0:
                first_media = media_list[0]
                if isinstance(first_media, dict):
                    thumbnail = first_media.get("thumbnail_url") or first_media.get("url")
                elif isinstance(first_media, str):
                    thumbnail = first_media
        
        preview_items.append(RulePreviewItem(
            content_id=content.id,
            title=content.title,
            platform=content.platform.value,
            tags=content.tags or [],
            is_nsfw=content.is_nsfw,
            status=status,
            reason=reason,
            scheduled_time=content.created_at,
            thumbnail_url=thumbnail
        ))
    
    return RulePreviewResponse(
        rule_id=rule.id,
        rule_name=rule.name,
        total_matched=len(preview_items),
        will_push_count=will_push_count,
        filtered_count=filtered_count,
        pending_review_count=pending_review_count,
        rate_limited_count=rate_limited_count,
        items=preview_items
    )


@router.get("/distribution-rules/preview/stats", response_model=List[RulePreviewStats])
async def get_all_rules_preview_stats(
    db: AsyncSession = Depends(get_db),
    _: None = Depends(require_api_token),
):
    """获取所有规则的预览统计"""
    result = await db.execute(
        select(DistributionRule)
        .where(DistributionRule.enabled == True)
        .order_by(desc(DistributionRule.priority))
    )
    rules = result.scalars().all()
    
    stats_list: List[RulePreviewStats] = []
    
    for rule in rules:
        conditions = rule.match_conditions or {}
        
        content_query = select(Content).where(
            Content.status == ContentStatus.PARSE_SUCCESS
        ).limit(100)
        
        content_result = await db.execute(content_query)
        contents = content_result.scalars().all()
        
        will_push = 0
        filtered = 0
        pending_review = 0
        rate_limited = 0
        
        for content in contents:
            matched = True
            
            if "platform" in conditions and conditions["platform"] != content.platform.value:
                matched = False
            
            if matched and "tags" in conditions:
                required_tags = conditions.get("tags", [])
                content_tags = content.tags or []
                if required_tags and not any(tag in content_tags for tag in required_tags):
                    matched = False
            
            if matched and "is_nsfw" in conditions and conditions["is_nsfw"] != content.is_nsfw:
                matched = False
            
            if not matched:
                continue
            
            if content.is_nsfw and rule.nsfw_policy == "block":
                filtered += 1
            elif rule.approval_required and content.review_status not in [ReviewStatus.APPROVED, ReviewStatus.AUTO_APPROVED]:
                pending_review += 1
            else:
                will_push += 1
        
        stats_list.append(RulePreviewStats(
            rule_id=rule.id,
            rule_name=rule.name,
            will_push=will_push,
            filtered=filtered,
            pending_review=pending_review,
            rate_limited=rate_limited
        ))
    
    return stats_list


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
        
        from app.distribution.queue_service import enqueue_content
        total = 0
        for content in contents:
            count = await enqueue_content(content.id, session=session)
            total += count
    
    return {"status": "triggered", "enqueued_count": total}


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
        stmt = stmt.where(BotChat.chat_type == platform)
    
    if enabled is not None:
        stmt = stmt.where(DistributionTarget.enabled == enabled)
        
    result = await db.execute(stmt)
    all_records = result.all()
    
    # Aggregate targets by (platform, target_id)
    target_map: Dict[tuple, Dict] = {}  # key: (platform, target_id)
    
    for dt, chat, rule in all_records:
        target_platform = chat.chat_type
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
        
        # Single query to fetch all push records (only for preview content types)
        push_result = await db.execute(
            select(PushedRecord).where(
                and_(
                    PushedRecord.target_id.in_(all_target_ids),
                    PushedRecord.content_id.in_(PREVIEW_CONTENT_IDS)
                )
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
        chat_query = select(BotChat.id).where(
            and_(
                BotChat.chat_type == request.target_platform,
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
    # For now, only return built-in presets
    # TODO: Add custom preset storage in database
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
    
    # TODO: Check custom presets in database
    
    raise HTTPException(status_code=404, detail="Preset not found")
