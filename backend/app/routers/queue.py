"""
内容分发队列相关API。

包括队列项查询、状态转换和调度等。
"""
import asyncio
from typing import Optional, List
from datetime import datetime, timedelta, timezone
from fastapi import APIRouter, Depends, HTTPException, Query
from sqlalchemy import select, desc, func
from sqlalchemy.ext.asyncio import AsyncSession
from pydantic import BaseModel

from app.core.database import get_db
from app.core.events import event_bus
from app.models import Content, DistributionRule, PushedRecord, ReviewStatus, ContentStatus
from app.core.logging import logger
from app.core.dependencies import require_api_token

router = APIRouter()

class QueueItem(BaseModel):
    id: int
    content_id: int
    title: Optional[str] = None
    platform: str
    tags: List[str] = []
    is_nsfw: bool = False
    cover_url: Optional[str] = None
    author_name: Optional[str] = None
    status: str
    reason: Optional[str] = None
    scheduled_time: Optional[datetime] = None
    pushed_at: Optional[datetime] = None
    priority: int = 0

class QueueListResponse(BaseModel):
    items: List[QueueItem]
    total: int
    will_push_count: int = 0
    filtered_count: int = 0
    pending_review_count: int = 0
    pushed_count: int = 0

class MoveItemRequest(BaseModel):
    status: str
    reason: Optional[str] = None

class ReorderRequest(BaseModel):
    index: int


def _determine_content_status(
    content: Content,
    rule: Optional[DistributionRule],
    last_pushed_record: Optional[PushedRecord],
) -> tuple[str, Optional[str]]:
    """确定内容在队列中的状态"""
    # 如果已推送，检查是否在推送后重新审批通过（重推）
    if last_pushed_record:
        # 如果审核时间晚于最后推送时间，说明是重推，应视为待推送
        if content.reviewed_at and content.reviewed_at > last_pushed_record.pushed_at:
            pass  # 继续后续逻辑（通常会进入 approved 分支）
        else:
            return "pushed", None
    
    if content.review_status == ReviewStatus.REJECTED:
        return "filtered", "手动拒绝"
    
    # 优先检查批准状态 (手动批准优先级 > 规则限制)
    if content.review_status in [ReviewStatus.APPROVED, ReviewStatus.AUTO_APPROVED]:
        return "will_push", None

    if rule:
        if rule.approval_required and content.review_status == ReviewStatus.PENDING:
            return "pending_review", "需要人工审批"
        
        if content.is_nsfw and rule.nsfw_policy == "block":
            return "filtered", "NSFW内容被阻止"
        
        conditions = rule.match_conditions or {}
        if "tags" in conditions:
            required_tags = conditions.get("tags", [])
            exclude_tags = conditions.get("tags_exclude", [])
            content_tags = content.tags or []
            
            if exclude_tags and any(tag in content_tags for tag in exclude_tags):
                return "filtered", f"包含排除标签"
            
            if required_tags:
                tags_match_mode = conditions.get("tags_match_mode", "any")
                if tags_match_mode == "all":
                    if not all(tag in content_tags for tag in required_tags):
                        return "filtered", "标签不完全匹配"
                else:
                    if not any(tag in content_tags for tag in required_tags):
                        return "filtered", "标签不匹配"
        
        if "platform" in conditions:
            if conditions["platform"] != content.platform.value:
                return "filtered", f"平台不匹配"
    
    # 如果没有规则限制，或规则通过检查
    if content.review_status == ReviewStatus.PENDING:
        return "pending_review", "待审批"
    
    return "filtered", "未知状态"


class ScheduleUpdateRequest(BaseModel):
    scheduled_at: datetime

class BatchScheduleRequest(BaseModel):
    content_ids: List[int]
    start_time: Optional[datetime] = None
    interval_seconds: Optional[int] = 300

class BatchPushNowRequest(BaseModel):
    content_ids: List[int]

class MergeGroupRequest(BaseModel):
    content_ids: List[int]
    scheduled_at: Optional[datetime] = None

@router.get("/queue/items", response_model=QueueListResponse)
async def get_queue_items(
    rule_id: Optional[int] = Query(None, description="Rule filter"),
    status: Optional[str] = Query(None, description="Status filter"),
    limit: int = Query(100, ge=1, le=500),
    db: AsyncSession = Depends(get_db),
    _: None = Depends(require_api_token),
):
    """获取内容队列，严格按持久化的调度时间排序"""
    rule = None
    if rule_id:
        result = await db.execute(select(DistributionRule).where(DistributionRule.id == rule_id))
        rule = result.scalar_one_or_none()
        if not rule:
            raise HTTPException(status_code=404, detail="Rule not found")

    items: List[QueueItem] = []
    counts = {"will_push": 0, "filtered": 0, "pending_review": 0, "pushed": 0}
    
    # 如果请求"已推送"状态，从 PushedRecord 查询
    if status == "pushed":
        pushed_query = (
            select(Content, PushedRecord)
            .join(PushedRecord, Content.id == PushedRecord.content_id)
            .order_by(desc(PushedRecord.pushed_at))
            .limit(limit)
        )
        pushed_result = await db.execute(pushed_query)

        for content, pushed_record in pushed_result.all():
            pushed_at = pushed_record.pushed_at
            if pushed_at and pushed_at.tzinfo is None:
                pushed_at = pushed_at.replace(tzinfo=timezone.utc)

            items.append(QueueItem(
                id=content.id,
                content_id=content.id,
                title=content.title or (content.description[:50] if content.description else None),
                platform=content.platform.value,
                tags=content.tags or [],
                is_nsfw=content.is_nsfw or False,
                cover_url=content.cover_url,
                author_name=content.author_name,
                status="pushed",
                reason=None,
                scheduled_time=pushed_at,
                pushed_at=pushed_at,
                priority=0,
            ))
        
        # 统计已推送总数
        pushed_count_query = select(func.count(func.distinct(PushedRecord.content_id)))
        counts["pushed"] = (await db.execute(pushed_count_query)).scalar() or 0
    else:
        # 查询 PULLED 状态的内容
        content_query = (
            select(Content)
            .where(Content.status == ContentStatus.PULLED)
            .order_by(
                Content.scheduled_at.asc().nulls_last(),
                desc(Content.queue_priority),
                desc(Content.created_at),
            )
            .limit(limit * 2)
        )

        content_result = await db.execute(content_query)
        all_contents = content_result.scalars().all()

        for content in all_contents:
            pushed_result = await db.execute(
                select(PushedRecord)
                .where(PushedRecord.content_id == content.id)
                .order_by(desc(PushedRecord.pushed_at))
                .limit(1)
            )
            last_pushed_record = pushed_result.scalar_one_or_none()

            item_status, reason = _determine_content_status(content, rule, last_pushed_record)
            counts[item_status] = counts.get(item_status, 0) + 1

            if status and item_status != status:
                continue

            pushed_at = last_pushed_record.pushed_at if last_pushed_record else None

            item_scheduled_time = content.scheduled_at
            if not item_scheduled_time and item_status == "pushed":
                item_scheduled_time = pushed_at
            elif not item_scheduled_time:
                item_scheduled_time = content.created_at

            if item_scheduled_time and item_scheduled_time.tzinfo is None:
                item_scheduled_time = item_scheduled_time.replace(tzinfo=timezone.utc)
            if pushed_at and pushed_at.tzinfo is None:
                pushed_at = pushed_at.replace(tzinfo=timezone.utc)

            items.append(QueueItem(
                id=content.id,
                content_id=content.id,
                title=content.title or (content.description[:50] if content.description else None),
                platform=content.platform.value,
                tags=content.tags or [],
                is_nsfw=content.is_nsfw or False,
                cover_url=content.cover_url,
                author_name=content.author_name,
                status=item_status,
                reason=reason,
                scheduled_time=item_scheduled_time,
                pushed_at=pushed_at,
                priority=content.queue_priority or 0,
            ))

            if len(items) >= limit:
                break
    
    # 获取已推送总数用于统计
    if status != "pushed":
        pushed_count_query = select(func.count(func.distinct(PushedRecord.content_id)))
        counts["pushed"] = (await db.execute(pushed_count_query)).scalar() or 0

    return QueueListResponse(
        items=items,
        total=len(items),
        will_push_count=counts["will_push"],
        filtered_count=counts["filtered"],
        pending_review_count=counts["pending_review"],
        pushed_count=counts["pushed"],
    )

@router.get("/queue/stats")
async def get_queue_stats(
    rule_id: Optional[int] = Query(None),
    db: AsyncSession = Depends(get_db),
    _: None = Depends(require_api_token),
):
    """获取队列统计
    
    统计范围：
    - will_push/filtered/pending_review: 基于 PULLED 状态的内容
    - pushed: 基于有 PushedRecord 的已归档内容
    """
    rule = None
    if rule_id:
        result = await db.execute(select(DistributionRule).where(DistributionRule.id == rule_id))
        rule = result.scalar_one_or_none()

    content_query = select(Content).where(Content.status == ContentStatus.PULLED).limit(500)
    content_result = await db.execute(content_query)
    all_contents = content_result.scalars().all()

    counts = {"will_push": 0, "filtered": 0, "pending_review": 0, "pushed": 0}

    for content in all_contents:
        pushed_result = await db.execute(
            select(PushedRecord)
            .where(PushedRecord.content_id == content.id)
            .order_by(desc(PushedRecord.pushed_at))
            .limit(1)
        )
        last_pushed_record = pushed_result.scalar_one_or_none()

        item_status, _ = _determine_content_status(content, rule, last_pushed_record)
        counts[item_status] = counts.get(item_status, 0) + 1

    pushed_query = select(func.count(func.distinct(PushedRecord.content_id))).select_from(PushedRecord)
    counts["pushed"] = (await db.execute(pushed_query)).scalar() or 0

    return counts

@router.post("/queue/items/{content_id}/move")
async def move_queue_item(
    content_id: int,
    request: MoveItemRequest,
    db: AsyncSession = Depends(get_db),
    _: None = Depends(require_api_token),
):
    """移动内容到指定状态"""
    from app.distribution.engine import DistributionEngine
    result = await db.execute(select(Content).where(Content.id == content_id))
    content = result.scalar_one_or_none()
    if not content:
        raise HTTPException(status_code=404, detail="Content not found")

    new_status = request.status
    engine = DistributionEngine(db)

    if new_status == "will_push":
        content.review_status = ReviewStatus.APPROVED
        content.reviewed_at = datetime.utcnow()
        content.review_note = request.reason or "手动添加到推送队列"
        content.status = ContentStatus.PULLED
        content.is_manual_schedule = False  # 审核/恢复操作遵循规则频率限制
        
        # 计算动态间隔并寻找合适空档
        min_interval = await engine.get_min_interval_for_content(content)
        content.scheduled_at = await engine.calculate_scheduled_at(content, min_interval=min_interval)
        
        # 提交后触发全局紧凑重排，确保加入高优先级内容后队列依然有序紧凑
        await db.commit()
        await engine.compact_schedule()

    elif new_status == "filtered":
        content.review_status = ReviewStatus.REJECTED
        content.reviewed_at = datetime.utcnow()
        content.review_note = request.reason or "手动移除"
        content.scheduled_at = None
        # 移除条目后，触发时间压缩补位
        await engine.compact_schedule()

    elif new_status == "pending_review":
        content.review_status = ReviewStatus.PENDING
        content.reviewed_at = None
        content.review_note = None
        content.scheduled_at = None
        # 移除条目后，触发时间压缩补位
        await engine.compact_schedule()

    await db.commit()
    logger.info(f"内容状态已更新: id={content_id}, new_status={new_status}")
    
    return {
        "id": content_id,
        "status": new_status,
        "scheduled_at": content.scheduled_at.replace(tzinfo=timezone.utc) if content.scheduled_at else None,
    }

@router.post("/queue/items/{content_id}/reorder")
async def reorder_queue_item(
    content_id: int,
    request: ReorderRequest,
    db: AsyncSession = Depends(get_db),
    _: None = Depends(require_api_token),
):
    """重新排序队列项
    
    通过更新 scheduled_at 时间来实现正确的顺序显示
    """
    from app.distribution.engine import DistributionEngine

    result = await db.execute(select(Content).where(Content.id == content_id))
    content = result.scalar_one_or_none()
    if not content:
        raise HTTPException(status_code=404, detail="Content not found")

    await DistributionEngine(db).move_item_to_position(content_id, request.index)

    await event_bus.publish("queue_item_reordered", {
        "content_id": content_id,
        "new_index": request.index,
        "new_scheduled_at": content.scheduled_at.isoformat() if content.scheduled_at else None,
    })
    
    logger.info(f"队列项已重排: content_id={content_id}, index={request.index}, scheduled_at={content.scheduled_at}")
    
    return {
        "success": True,
        "new_index": request.index,
        "new_scheduled_at": content.scheduled_at.replace(tzinfo=timezone.utc) if content.scheduled_at else None,
    }

@router.post("/queue/items/{content_id}/schedule")
async def update_item_schedule(
    content_id: int,
    request: ScheduleUpdateRequest,
    db: AsyncSession = Depends(get_db),
    _: None = Depends(require_api_token),
):
    """手动调整预计推送时间，并自动触发重排"""
    from app.distribution.engine import DistributionEngine
    result = await db.execute(select(Content).where(Content.id == content_id))
    content = result.scalar_one_or_none()
    if not content:
        raise HTTPException(status_code=404, detail="Content not found")
    
    # 后端校验：如果时间早于现在，视为“立即推送”意图，设为过去的时间以排在最前
    now = datetime.utcnow()
    scheduled_at = request.scheduled_at.replace(tzinfo=None) # 转换为 naive UTC
    
    if scheduled_at <= now:
        content.scheduled_at = now - timedelta(hours=24)
    else:
        content.scheduled_at = scheduled_at
        
    content.is_manual_schedule = True  # 手动设定的时间标记为手动
    await db.commit()
    
    # 手动改时间后，触发全局紧凑重排，确保不留空档或重叠
    engine = DistributionEngine(db)
    await engine.compact_schedule()
    
    logger.info(f"内容推送时间已调整并重排: id={content_id}, scheduled_at={content.scheduled_at}")
    
    # 返回带有时区信息的时间，确保前端识别为 UTC
    return {
        "id": content_id,
        "scheduled_at": content.scheduled_at.replace(tzinfo=timezone.utc) if content.scheduled_at else None,
    }

@router.post("/queue/batch-reschedule")
async def batch_reschedule(
    request: BatchScheduleRequest,
    db: AsyncSession = Depends(get_db),
    _: None = Depends(require_api_token),
):
    """批量排期：从指定时间开始，按间隔排列选中内容"""
    now = datetime.now(timezone.utc)
    start_time = request.start_time or now
    # 统一为 UTC 时区进行比较
    if start_time.tzinfo is None:
        start_time = start_time.replace(tzinfo=timezone.utc)
    if start_time < now:
        start_time = now + timedelta(seconds=10)

    interval = request.interval_seconds or 300
    
    # 按请求中的顺序处理，如果没传顺序则按数据库现有顺序
    result = await db.execute(
        select(Content).where(Content.id.in_(request.content_ids))
    )
    content_map = {c.id: c for c in result.scalars().all()}

    updated_ids = []
    for i, cid in enumerate(request.content_ids):
        if cid in content_map:
            content = content_map[cid]
            content.scheduled_at = start_time + timedelta(seconds=interval * i)
            content.is_manual_schedule = True  # 批量排期标记为手动
            updated_ids.append(cid)

    await db.commit()
    
    # 批量排期后也触发一次重排，确保与队列中其他项不碰撞
    from app.distribution.engine import DistributionEngine
    engine = DistributionEngine(db)
    await engine.compact_schedule()

    return {
        "updated_count": len(updated_ids),
        "first_time": start_time.replace(tzinfo=timezone.utc) if start_time.tzinfo is None else start_time,
    }

@router.post("/queue/batch-push-now")
async def batch_push_now(
    request: BatchPushNowRequest,
    db: AsyncSession = Depends(get_db),
    _: None = Depends(require_api_token),
):
    """批量立即推送：将选中内容移至队首并紧凑排列"""
    from app.distribution.engine import DistributionEngine
    now = datetime.utcnow()
    
    # 1. 抓取选中的内容
    result = await db.execute(
        select(Content).where(Content.id.in_(request.content_ids))
    )
    content_map = {c.id: c for c in result.scalars().all()}
    selected_contents = [content_map[cid] for cid in request.content_ids if cid in content_map]
    
    # 2. 标记为批准并分配一个非常早的基础时间，彼此保留微小间隔以维持请求中的相对顺序
    # 设为过去的时间会使它们在 compact_schedule 的 order_by 中排在最前面
    base_time = now - timedelta(hours=24)
    for i, content in enumerate(selected_contents):
        content.review_status = ReviewStatus.APPROVED
        content.reviewed_at = now
        content.scheduled_at = base_time + timedelta(seconds=i)
        content.is_manual_schedule = True  # 立即推送标记为手动，以便使用紧凑间隔
            
    await db.commit()
    
    # 3. 触发全队列重排，并指定这些 ID 采用紧凑间隔 (10s)
    engine = DistributionEngine(db)
    await engine.compact_schedule(immediate_ids=request.content_ids)

    from app.distribution.scheduler import get_distribution_scheduler
    scheduler = get_distribution_scheduler()
    asyncio.ensure_future(scheduler.trigger_run())

    await event_bus.publish("queue_updated", {"action": "batch_push_now", "content_ids": request.content_ids})

    return {"updated_count": len(selected_contents)}


@router.post("/queue/merge-group")
async def merge_group(
    request: MergeGroupRequest,
    db: AsyncSession = Depends(get_db),
    _: None = Depends(require_api_token),
):
    """ 合并排期：将多个内容的 scheduled_at 对齐，视为一个组合单元"""
    from app.distribution.engine import DistributionEngine

    result = await db.execute(
        select(Content).where(Content.id.in_(request.content_ids))
    )
    contents = result.scalars().all()
    if not contents:
        raise HTTPException(status_code=404, detail="No contents found")

    if request.scheduled_at is not None:
        target_time = request.scheduled_at.replace(tzinfo=None)
    else:
        existing_times = [c.scheduled_at for c in contents if c.scheduled_at is not None]
        target_time = min(existing_times) if existing_times else datetime.utcnow()

    for content in contents:
        content.scheduled_at = target_time

    await db.commit()

    engine = DistributionEngine(db)
    await engine.compact_schedule()

    await event_bus.publish("queue_updated", {"action": "merge_group", "content_ids": request.content_ids})

    return {
        "merged_count": len(contents),
        "scheduled_at": target_time.replace(tzinfo=timezone.utc),
    }


@router.post("/queue/items/{content_id}/push-now")
async def push_now(
    content_id: int,
    db: AsyncSession = Depends(get_db),
    _: None = Depends(require_api_token),
):
    """立即推送一个队列条目"""
    from app.distribution.engine import DistributionEngine

    result = await db.execute(select(Content).where(Content.id == content_id))
    content = result.scalar_one_or_none()
    if not content:
        raise HTTPException(status_code=404, detail="Content not found")

    now = datetime.utcnow()
    content.scheduled_at = now - timedelta(hours=24)
    content.queue_priority = 9999
    content.review_status = ReviewStatus.APPROVED
    content.reviewed_at = now
    content.is_manual_schedule = True
    await db.commit()

    engine = DistributionEngine(db)
    await engine.compact_schedule(immediate_ids=[content_id])

    from app.distribution.scheduler import get_distribution_scheduler
    scheduler = get_distribution_scheduler()
    asyncio.ensure_future(scheduler.trigger_run())

    return {
        "id": content_id,
        "scheduled_at": content.scheduled_at.replace(tzinfo=timezone.utc) if content.scheduled_at else None,
        "queue_priority": content.queue_priority,
        "review_status": content.review_status.value if content.review_status else None,
    }
