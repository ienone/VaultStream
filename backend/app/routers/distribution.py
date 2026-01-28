"""
功能描述：分发规则管理 API
包含：规则增删改查、规则预览
调用方式：需要 API Token
"""
from typing import List, Optional
from datetime import datetime, timedelta
from fastapi import APIRouter, Depends, HTTPException, Query
from sqlalchemy import select, desc, and_
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.database import get_db
from app.models import DistributionRule, Content, PushedRecord, ReviewStatus, ContentStatus
from app.schemas import (
    DistributionRuleCreate, DistributionRuleUpdate, DistributionRuleResponse,
    RulePreviewResponse, RulePreviewItem, RulePreviewStats
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
    
    db_rule = DistributionRule(**rule.model_dump())
    db.add(db_rule)
    await db.commit()
    await db.refresh(db_rule)
    
    logger.info(f"分发规则已创建: {db_rule.name} (ID: {db_rule.id})")
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
    logger.info(f"分发规则已更新: {db_rule.name} (ID: {db_rule.id})")
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
    logger.info(f"分发规则已删除: {db_rule.name} (ID: {rule_id})")
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
