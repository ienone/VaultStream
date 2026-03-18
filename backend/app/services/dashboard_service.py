"""
仪表盘统计服务 - 提供解析状态和分发状态的共享统计逻辑
"""
from datetime import datetime
from typing import Optional

from sqlalchemy import func, or_, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models import Content, ContentStatus, ContentQueueItem, QueueItemStatus, DiscoveryState


def _is_library_content():
    """已加入库的内容：普通订阅内容（discovery_state IS NULL）+ 已收录的 discovery 内容"""
    return or_(
        Content.discovery_state.is_(None),
        Content.discovery_state == DiscoveryState.PROMOTED,
    )


def classify_distribution_status(
    status: QueueItemStatus,
    next_attempt_at: Optional[datetime],
) -> str:
    """将队列项状态分类为看板分桶"""
    if status == QueueItemStatus.SUCCESS:
        return "pushed"
    if status in (QueueItemStatus.SCHEDULED, QueueItemStatus.PROCESSING):
        return "will_push"
    if status == QueueItemStatus.FAILED:
        return "will_push" if next_attempt_at is not None else "filtered"
    return "filtered"


def empty_distribution_bucket() -> dict[str, int]:
    return {"will_push": 0, "filtered": 0, "pushed": 0, "total": 0}


async def build_parse_stats(db: AsyncSession) -> dict:
    """构建解析阶段统计（订阅库内容 + 已收录的 discovery 内容）"""
    stats = {"unprocessed": 0, "processing": 0, "parse_success": 0, "parse_failed": 0, "total": 0}
    result = await db.execute(
        select(Content.status, func.count(Content.id))
        .where(_is_library_content())
        .group_by(Content.status)
    )
    for status, count in result.all():
        count_int = int(count or 0)
        stats["total"] += count_int
        if status == ContentStatus.UNPROCESSED:
            stats["unprocessed"] += count_int
        elif status == ContentStatus.PROCESSING:
            stats["processing"] += count_int
        elif status == ContentStatus.PARSE_SUCCESS:
            stats["parse_success"] += count_int
        elif status == ContentStatus.PARSE_FAILED:
            stats["parse_failed"] += count_int
    return stats


async def build_distribution_stats(
    db: AsyncSession, *, include_rule_breakdown: bool = False
) -> tuple[dict, dict[str, dict]]:
    """构建分发阶段统计，可选按规则拆分"""
    distribution_stats = empty_distribution_bucket()
    rule_breakdown: dict[str, dict] = {}

    cols = [
        ContentQueueItem.status,
        ContentQueueItem.next_attempt_at,
        func.count(ContentQueueItem.id),
    ]
    group_cols = [
        ContentQueueItem.status,
        ContentQueueItem.next_attempt_at,
    ]
    if include_rule_breakdown:
        cols.insert(0, ContentQueueItem.rule_id)
        group_cols.insert(0, ContentQueueItem.rule_id)

    query = (
        select(*cols)
        .join(Content, Content.id == ContentQueueItem.content_id)
        .where(
            Content.status == ContentStatus.PARSE_SUCCESS,
            _is_library_content(),
        )
        .group_by(*group_cols)
    )
    rows = (await db.execute(query)).all()

    for row in rows:
        if include_rule_breakdown:
            rule_id, status, next_attempt_at, count = row
        else:
            status, next_attempt_at, count = row
            rule_id = None

        count_int = int(count or 0)
        bucket = classify_distribution_status(status, next_attempt_at)

        distribution_stats[bucket] += count_int
        distribution_stats["total"] += count_int

        if include_rule_breakdown and rule_id is not None:
            key = str(rule_id)
            if key not in rule_breakdown:
                rule_breakdown[key] = empty_distribution_bucket()
            rule_breakdown[key][bucket] += count_int
            rule_breakdown[key]["total"] += count_int

    return distribution_stats, rule_breakdown
