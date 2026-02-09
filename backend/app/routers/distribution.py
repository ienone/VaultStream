"""
功能描述：分发规则管理 API
包含：规则增删改查、规则预览、目标管理、渲染配置预设
调用方式：需要 API Token
"""
from typing import List, Optional, Dict, Any
from datetime import datetime, timedelta
from fastapi import APIRouter, Depends, HTTPException, Query
from sqlalchemy import select, desc, and_
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.database import get_db
from app.models import DistributionRule, Content, PushedRecord, ReviewStatus, ContentStatus
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


async def _check_target_conflicts(
    db: AsyncSession,
    targets: List[Dict[str, Any]],
    exclude_rule_id: Optional[int] = None
) -> List[str]:
    """
    检查目标配置是否与其他规则冲突
    
    Args:
        db: 数据库会话
        targets: 目标列表
        exclude_rule_id: 排除的规则ID（用于更新时忽略自己）
    
    Returns:
        冲突警告列表
    """
    warnings = []
    
    # 获取所有其他规则 (SQLite 暂不支持在该层面高效查询 JSON 数组内部项，先保持聚合逻辑)
    # 但我们可以优化内存循环
    query = select(DistributionRule)
    if exclude_rule_id:
        query = query.where(DistributionRule.id != exclude_rule_id)
    
    result = await db.execute(query)
    all_rules = result.scalars().all()
    
    # 构建现有目标的索引： (platform, target_id) -> list of rule names
    existing_target_index = {}
    for rule in all_rules:
        if not rule.targets:
            continue
        for t in rule.targets:
            key = (t.get('platform'), str(t.get('target_id')))
            if key not in existing_target_index:
                existing_target_index[key] = []
            existing_target_index[key].append(rule.name)
    
    # 检查输入的目标
    for target in targets:
        platform = target.get('platform')
        target_id = str(target.get('target_id'))
        key = (platform, target_id)
        
        conflicting_rules = existing_target_index.get(key, [])
        if conflicting_rules:
            warnings.append(
                f"Target {platform}:{target_id} is also configured in rules: {', '.join(conflicting_rules)}"
            )
    
    return warnings


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
    
    # 检查目标配置冲突
    if rule.targets:
        conflicts = await _check_target_conflicts(db, rule.targets)
        if conflicts:
            logger.warning(
                f"Creating rule '{rule.name}' with target conflicts: {'; '.join(conflicts)}"
            )
    
    db_rule = DistributionRule(**rule.model_dump())
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
    
    # 检查目标配置冲突（如果更新了targets）
    if 'targets' in update_data and update_data['targets']:
        conflicts = await _check_target_conflicts(db, update_data['targets'], exclude_rule_id=rule_id)
        if conflicts:
            logger.warning(
                f"Updating rule '{db_rule.name}' (ID: {rule_id}) with target conflicts: {'; '.join(conflicts)}"
            )
    
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
    result = await db.execute(select(DistributionRule).where(DistributionRule.id == rule_id))
    rule = result.scalar_one_or_none()
    if not rule:
        raise HTTPException(status_code=404, detail="Distribution rule not found")
    
    conditions = rule.match_conditions or {}
    
    content_query = select(Content).where(
        Content.status == ContentStatus.PULLED
    ).order_by(desc(Content.created_at)).limit(limit * 2)
    
    content_result = await db.execute(content_query)
    all_contents = content_result.scalars().all()
    
    preview_items: List[RulePreviewItem] = []
    will_push_count = 0
    filtered_count = 0
    pending_review_count = 0
    rate_limited_count = 0
    
    targets = rule.targets or []
    target_ids = [t.get("target_id") for t in targets if t.get("target_id") and t.get("enabled", True)]
    
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
            Content.status == ContentStatus.PULLED
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
    """手动触发分发任务"""
    from app.distribution import get_distribution_scheduler
    
    scheduler = get_distribution_scheduler()
    # 不等待任务完成，直接返回，避免阻塞
    # 但为了给前端反馈，我们可以等待一下，反正通常很快
    await scheduler.trigger_run()
    
    return {"status": "triggered", "message": "分发任务已触发"}


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
    result = await db.execute(select(DistributionRule))
    all_rules = result.scalars().all()
    
    # Aggregate targets from all rules
    target_map: Dict[tuple, Dict] = {}  # key: (platform, target_id)
    
    for rule in all_rules:
        if not rule.targets:
            continue
        
        for target in rule.targets:
            target_platform = target.get("platform", "")
            target_id = target.get("target_id", "")
            
            if not target_platform or not target_id:
                continue
            
            # Apply filters
            if platform and target_platform != platform:
                continue
            
            target_enabled = target.get("enabled", True)
            if enabled is not None and target_enabled != enabled:
                continue
            
            key = (target_platform, target_id)
            
            if key not in target_map:
                target_map[key] = {
                    "target_platform": target_platform,
                    "target_id": target_id,
                    "enabled": target_enabled,
                    "rule_count": 0,
                    "rule_ids": [],
                    "rule_names": [],
                    "merge_forward": target.get("merge_forward", False),
                    "use_author_name": target.get("use_author_name", False),
                    "summary": target.get("summary", ""),
                    "render_config": target.get("render_config"),
                    "total_pushed": 0,
                    "last_pushed_at": None,
                }
            
            target_map[key]["rule_count"] += 1
            target_map[key]["rule_ids"].append(rule.id)
            target_map[key]["rule_names"].append(rule.name)
    
    # Get push statistics for all targets (optimized: single query instead of N+1)
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
        # Fetch all candidate rules in one query
        result = await db.execute(
            select(DistributionRule).where(DistributionRule.id.in_(request.rule_ids))
        )
        rules = result.scalars().all()
        
        for rule in rules:
            targets = rule.targets or []
            rule_updated = False
            
            # Use a fresh list to ensure SQLAlchemy detects changes in JSON field
            new_targets = []
            for target in targets:
                if (target.get("platform") == request.target_platform and
                    str(target.get("target_id")) == str(request.target_id)):
                    
                    # Create a copy to modify
                    updated_target = dict(target)
                    modified = False
                    
                    if request.enabled is not None:
                        updated_target["enabled"] = request.enabled
                        modified = True
                    
                    if request.merge_forward is not None:
                        updated_target["merge_forward"] = request.merge_forward
                        modified = True
                    
                    if request.render_config is not None:
                        updated_target["render_config"] = request.render_config
                        modified = True
                    
                    if modified:
                        new_targets.append(updated_target)
                        rule_updated = True
                    else:
                        new_targets.append(target)
                else:
                    new_targets.append(target)
            
            if rule_updated:
                rule.targets = new_targets
                updated_rule_ids.append(rule.id)
                logger.info(f"Updated target {request.target_id} in rule {rule.id}")
        
        if updated_rule_ids:
            await db.commit()
            # No need to refresh all if we only updated the targets field 
            # and the user only needs the IDs back
        
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
