"""
仪表盘统计服务 - 提供解析状态和分发状态的共享统计逻辑
"""
from app.services.distribution.delivery_state import delivery_bucket, visible_queue_item

from sqlalchemy import func, or_, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models import Content, ContentStatus, ContentQueueItem, QueueItemStatus, DiscoveryState


def _is_library_content():
    """已加入库的内容：普通订阅内容（discovery_state IS NULL）+ 已收录的 discovery 内容"""
    return or_(
        Content.discovery_state.is_(None),
        Content.discovery_state == DiscoveryState.PROMOTED,
    )


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

    bucket_column = delivery_bucket()
    cols = [bucket_column, func.count(ContentQueueItem.id)]
    groups = [bucket_column]
    if include_rule_breakdown:
        cols.insert(0, ContentQueueItem.rule_id)
        groups.insert(0, ContentQueueItem.rule_id)
    rows = (await db.execute(select(*cols).where(visible_queue_item()).group_by(*groups))).all()
    for row in rows:
        if include_rule_breakdown:
            rule_id, bucket, count = row
        else:
            bucket, count = row
            rule_id = None
        count_int = int(count)
        distribution_stats[bucket] += count_int
        distribution_stats["total"] += count_int

        if include_rule_breakdown and rule_id is not None:
            key = str(rule_id)
            if key not in rule_breakdown:
                rule_breakdown[key] = empty_distribution_bucket()
            rule_breakdown[key][bucket] += count_int
            rule_breakdown[key]["total"] += count_int

    return distribution_stats, rule_breakdown
