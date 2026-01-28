"""
功能描述：内容队列管理 API
包含：队列项查询、状态切换、排序
"""
from typing import Optional, List
from datetime import datetime
from fastapi import APIRouter, Depends, HTTPException, Query
from sqlalchemy import select, desc, and_, func
from sqlalchemy.ext.asyncio import AsyncSession
from pydantic import BaseModel

from app.core.database import get_db
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
    priority: int


def _determine_content_status(
    content: Content,
    rule: Optional[DistributionRule],
    last_pushed_record: Optional[PushedRecord]
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
        # 注意: 如果是 AUTO_APPROVED，理论上应该再次检查规则，但在入库时已经检查过了。
        # 如果是 APPROVED (人工)，则明确跳过规则检查(如NSFW)
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


@router.get("/queue/items", response_model=QueueListResponse)
async def get_queue_items(
    rule_id: Optional[int] = Query(None, description="规则ID筛选"),
    status: Optional[str] = Query(None, description="状态筛选: will_push, filtered, pending_review, pushed"),
    limit: int = Query(100, ge=1, le=500),
    db: AsyncSession = Depends(get_db),
    _: None = Depends(require_api_token),
):
    """获取内容队列"""
    rule = None
    if rule_id:
        result = await db.execute(select(DistributionRule).where(DistributionRule.id == rule_id))
        rule = result.scalar_one_or_none()
        if not rule:
            raise HTTPException(status_code=404, detail="Rule not found")
    
    content_query = select(Content).where(
        Content.status == ContentStatus.PULLED
    ).order_by(desc(Content.queue_priority), desc(Content.created_at)).limit(limit * 2)
    
    content_result = await db.execute(content_query)
    all_contents = content_result.scalars().all()
    
    items: List[QueueItem] = []
    counts = {"will_push": 0, "filtered": 0, "pending_review": 0, "pushed": 0}
    
    for content in all_contents:
        pushed_result = await db.execute(
            select(PushedRecord).where(PushedRecord.content_id == content.id).order_by(desc(PushedRecord.pushed_at)).limit(1)
        )
        last_pushed_record = pushed_result.scalar_one_or_none()
        
        item_status, reason = _determine_content_status(content, rule, last_pushed_record)
        counts[item_status] = counts.get(item_status, 0) + 1
        
        if status and item_status != status:
            continue
        
        pushed_at = last_pushed_record.pushed_at if last_pushed_record else None
        
        items.append(QueueItem(
            id=content.id,
            content_id=content.id,
            title=content.title or content.description[:50] if content.description else None,
            platform=content.platform.value,
            tags=content.tags or [],
            is_nsfw=content.is_nsfw or False,
            cover_url=content.cover_url,
            author_name=content.author_name,
            status=item_status,
            reason=reason,
            scheduled_time=content.created_at,
            pushed_at=pushed_at,
            priority=content.queue_priority or 0,
        ))
        
        if len(items) >= limit:
            break
    
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
    """获取队列统计"""
    rule = None
    if rule_id:
        result = await db.execute(select(DistributionRule).where(DistributionRule.id == rule_id))
        rule = result.scalar_one_or_none()
    
    content_query = select(Content).where(
        Content.status == ContentStatus.PULLED
    ).limit(500)
    
    content_result = await db.execute(content_query)
    all_contents = content_result.scalars().all()
    
    counts = {"will_push": 0, "filtered": 0, "pending_review": 0, "pushed": 0}
    
    for content in all_contents:
        pushed_result = await db.execute(
            select(PushedRecord).where(PushedRecord.content_id == content.id).order_by(desc(PushedRecord.pushed_at)).limit(1)
        )
        last_pushed_record = pushed_result.scalar_one_or_none()
        
        item_status, _ = _determine_content_status(content, rule, last_pushed_record)
        counts[item_status] = counts.get(item_status, 0) + 1
    
    return counts


@router.post("/queue/items/{content_id}/move")
async def move_queue_item(
    content_id: int,
    request: MoveItemRequest,
    db: AsyncSession = Depends(get_db),
    _: None = Depends(require_api_token),
):
    """移动内容到指定状态"""
    result = await db.execute(select(Content).where(Content.id == content_id))
    content = result.scalar_one_or_none()
    if not content:
        raise HTTPException(status_code=404, detail="Content not found")
    
    new_status = request.status
    
    if new_status == "will_push":
        content.review_status = ReviewStatus.APPROVED
        content.reviewed_at = datetime.utcnow()
        content.review_note = request.reason or "手动添加到推送队列"
        # 重置内容状态为 PULLED，确保调度器能扫到 (特别是从 FAILED 状态恢复时)
        content.status = ContentStatus.PULLED
    elif new_status == "filtered":
        content.review_status = ReviewStatus.REJECTED
        content.reviewed_at = datetime.utcnow()
        content.review_note = request.reason or "手动移除"
    elif new_status == "pending_review":
        content.review_status = ReviewStatus.PENDING
        content.reviewed_at = None
        content.review_note = None
    
    await db.commit()
    logger.info(f"内容状态已更新: id={content_id}, new_status={new_status}")
    
    return {"id": content_id, "status": new_status}


@router.post("/queue/items/{content_id}/reorder")
async def reorder_queue_item(
    content_id: int,
    request: ReorderRequest,
    db: AsyncSession = Depends(get_db),
    _: None = Depends(require_api_token),
):
    """调整内容排序优先级"""
    result = await db.execute(select(Content).where(Content.id == content_id))
    content = result.scalar_one_or_none()
    if not content:
        raise HTTPException(status_code=404, detail="Content not found")
    
    content.queue_priority = request.priority
    await db.commit()
    
    logger.info(f"内容排序已调整: id={content_id}, priority={request.priority}")
    
    return {"id": content_id, "priority": request.priority}
