"""
队列入队服务 - 事件驱动的内容入队逻辑。

根据分发规则匹配结果，为每个 (Content × Rule × BotChat) 组合创建队列项。
"""
from typing import Optional
from datetime import datetime, timedelta

from sqlalchemy import select, and_, insert, func
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.database import AsyncSessionLocal
from app.core.logging import logger
from app.core.time_utils import utcnow
from app.services.distribution.engine import DistributionEngine
from app.services.distribution.decision import evaluate_target_decision, DECISION_FILTERED, DECISION_PENDING_REVIEW
from app.core.events import event_bus
from app.models import (
    Content,
    DistributionRule,
    DistributionTarget,
    BotChat,
    ContentQueueItem,
    QueueItemStatus,
    ContentStatus,
    ReviewStatus,
    PushedRecord,
)


async def compute_auto_scheduled_at(
    *,
    session: AsyncSession,
    rule: DistributionRule,
    bot_chat_id: int,
    target_id: str,
) -> datetime:
    """根据规则限流配置计算自动排期时间。"""
    now = utcnow()

    if not rule.rate_limit or not rule.time_window or rule.rate_limit <= 0 or rule.time_window <= 0:
        return now

    min_interval_seconds = max(1, int(rule.time_window) // int(rule.rate_limit))

    latest_queue_result = await session.execute(
        select(func.max(ContentQueueItem.scheduled_at)).where(
            and_(
                ContentQueueItem.rule_id == rule.id,
                ContentQueueItem.bot_chat_id == bot_chat_id,
                ContentQueueItem.status.in_(
                    [
                        QueueItemStatus.PENDING,
                        QueueItemStatus.SCHEDULED,
                        QueueItemStatus.PROCESSING,
                        QueueItemStatus.FAILED,
                    ]
                ),
            )
        )
    )
    latest_queue_time = latest_queue_result.scalar_one_or_none()

    latest_pushed_result = await session.execute(
        select(func.max(PushedRecord.pushed_at)).where(
            and_(
                PushedRecord.target_id == target_id,
                PushedRecord.push_status == "success",
            )
        )
    )
    latest_pushed_time = latest_pushed_result.scalar_one_or_none()

    scheduled_at = now
    anchor = latest_queue_time or latest_pushed_time
    if anchor and anchor + timedelta(seconds=min_interval_seconds) > scheduled_at:
        scheduled_at = anchor + timedelta(seconds=min_interval_seconds)

    window_start = now - timedelta(seconds=int(rule.time_window))
    recent_result = await session.execute(
        select(PushedRecord.pushed_at)
        .where(
            and_(
                PushedRecord.target_id == target_id,
                PushedRecord.push_status == "success",
                PushedRecord.pushed_at >= window_start,
            )
        )
        .order_by(PushedRecord.pushed_at.asc())
    )
    recent_pushes = [p for p in recent_result.scalars().all() if p is not None]
    if len(recent_pushes) >= int(rule.rate_limit):
        throttle_until = recent_pushes[0] + timedelta(seconds=int(rule.time_window))
        if throttle_until > scheduled_at:
            scheduled_at = throttle_until

    return scheduled_at


async def enqueue_content(
    content_id: int,
    *,
    session: Optional[AsyncSession] = None,
    force: bool = False,
) -> int:
    """
    为指定内容创建分发队列项。

    根据规则匹配结果，为每个 (content, rule, bot_chat) 组合创建 ContentQueueItem。

    Args:
        content_id: 内容 ID
        session: 可选的数据库会话，若未提供则自动创建
        force: 若为 True，则重置已失败的队列项为 PENDING

    Returns:
        创建或更新的队列项数量
    """
    if session is not None:
        return await _enqueue_content_impl(content_id, session, force)

    async with AsyncSessionLocal() as session:
        return await _enqueue_content_impl(content_id, session, force)


async def _enqueue_content_impl(
    content_id: int,
    session: AsyncSession,
    force: bool,
) -> int:
    """入队核心实现。"""
    # 1. 加载内容
    result = await session.execute(
        select(Content).where(Content.id == content_id)
    )
    content = result.scalar_one_or_none()

    if not content:
        logger.warning(f"Content not found: content_id={content_id}")
        return 0

    # 2. 资格检查
    if content.status != ContentStatus.PARSE_SUCCESS:
        logger.info(
            f"Content not eligible (status): content_id={content_id}, status={content.status}"
        )
        return 0

    if content.review_status not in (
        ReviewStatus.APPROVED,
        ReviewStatus.AUTO_APPROVED,
        ReviewStatus.PENDING,
    ):
        logger.info(
            f"Content not eligible (review): content_id={content_id}, "
            f"review_status={content.review_status}"
        )
        return 0

    is_reviewed = content.review_status in (ReviewStatus.APPROVED, ReviewStatus.AUTO_APPROVED)

    # 3. 匹配规则
    engine = DistributionEngine(session)
    matched_rules = await engine.match_rules(content)

    if not matched_rules:
        logger.info(f"No matching rules for content: content_id={content_id}")
        return 0

    # 4. 批量查询所有匹配规则的目标（避免 N+1）
    rule_ids = [r.id for r in matched_rules]
    targets_result = await session.execute(
        select(DistributionTarget, BotChat)
        .join(BotChat, DistributionTarget.bot_chat_id == BotChat.id)
        .where(DistributionTarget.rule_id.in_(rule_ids))
        .where(DistributionTarget.enabled == True)
        .where(BotChat.enabled == True)
        .where(BotChat.is_accessible == True)
    )

    # 按 rule_id 组织
    rule_targets: dict[int, list[tuple[DistributionTarget, BotChat]]] = {}
    for target, bot_chat in targets_result.all():
        rule_targets.setdefault(target.rule_id, []).append((target, bot_chat))

    # 5. 批量查询已有的队列项（避免逐条查询）
    existing_result = await session.execute(
        select(ContentQueueItem).where(
            and_(
                ContentQueueItem.content_id == content_id,
                ContentQueueItem.rule_id.in_(rule_ids),
            )
        )
    )
    existing_items: dict[tuple[int, int], ContentQueueItem] = {
        (item.rule_id, item.bot_chat_id): item
        for item in existing_result.scalars().all()
    }

    # 6. 构建规则 ID -> 规则对象映射
    rules_map = {r.id: r for r in matched_rules}

    # 7. 逐目标创建/更新队列项
    count = 0

    for rule_id, pairs in rule_targets.items():
        rule = rules_map.get(rule_id)
        if not rule:
            continue

        for target, bot_chat in pairs:
            # 未审批内容只允许进入需要审批的规则队列
            if not is_reviewed and not rule.approval_required:
                continue
            
            decision = evaluate_target_decision(
                content=content,
                rule=rule,
                bot_chat=bot_chat,
                require_approval=not is_reviewed
            )
            
            if decision.bucket == DECISION_FILTERED:
                continue

            target_id = decision.target_id or bot_chat.chat_id

            key = (rule.id, bot_chat.id)
            existing = existing_items.get(key)

            if existing:
                # 已成功且非强制：跳过
                if existing.status == QueueItemStatus.SUCCESS and not force:
                    logger.debug(
                        f"Queue item already succeeded: content_id={content_id}, "
                        f"rule_id={rule.id}, bot_chat_id={bot_chat.id}"
                    )
                    continue

                # 已失败且强制：重置为 PENDING
                if existing.status == QueueItemStatus.FAILED and force:
                    existing.status = (
                        QueueItemStatus.PENDING
                        if decision.bucket == DECISION_PENDING_REVIEW
                        else QueueItemStatus.SCHEDULED
                    )
                    existing.attempt_count = 0
                    existing.last_error = None
                    existing.last_error_type = None
                    existing.last_error_at = None
                    existing.next_attempt_at = None
                    existing.target_id = target_id
                    existing.nsfw_routing_result = decision.nsfw_routing_result
                    
                    if existing.status == QueueItemStatus.SCHEDULED:
                        existing.scheduled_at = await compute_auto_scheduled_at(
                            session=session,
                            rule=rule,
                            bot_chat_id=bot_chat.id,
                            target_id=existing.target_id,
                        )
                    else:
                        existing.scheduled_at = utcnow()
                        
                    existing.updated_at = utcnow()
                    count += 1
                    logger.info(
                        f"Queue item reset to PENDING: content_id={content_id}, "
                        f"rule_id={rule.id}, bot_chat_id={bot_chat.id}"
                    )
                    continue

                # 其他状态（PENDING, SCHEDULED, PROCESSING 等）：跳过
                continue

            # 新建队列项
            needs_approval = decision.bucket == DECISION_PENDING_REVIEW
            status = QueueItemStatus.PENDING if needs_approval else QueueItemStatus.SCHEDULED
            if status == QueueItemStatus.SCHEDULED:
                scheduled_time = await compute_auto_scheduled_at(
                    session=session,
                    rule=rule,
                    bot_chat_id=bot_chat.id,
                    target_id=target_id,
                )
            else:
                scheduled_time = utcnow()

            item = ContentQueueItem(
                content_id=content_id,
                rule_id=rule.id,
                bot_chat_id=bot_chat.id,
                target_platform=bot_chat.platform_type,
                target_id=target_id,
                status=status,
                priority=rule.priority + content.queue_priority,
                scheduled_at=scheduled_time,
                needs_approval=needs_approval,
                nsfw_routing_result=decision.nsfw_routing_result,
            )
            session.add(item)
            count += 1

    if count > 0:
        await session.commit()
        await event_bus.publish("queue_updated", {
            "action": "enqueue",
            "content_id": content_id,
            "items_changed": count,
            "timestamp": utcnow().isoformat(),
        })
        logger.info(
            f"Enqueued content: content_id={content_id}, "
            f"rules_matched={len(matched_rules)}, items_created_or_updated={count}"
        )

    return count


async def enqueue_content_background(content_id: int) -> None:
    """
    后台入队包装器（fire-and-forget）。

    自动创建数据库会话，捕获并记录所有异常。
    """
    try:
        async with AsyncSessionLocal() as session:
            await _enqueue_content_impl(content_id, session, force=False)
    except Exception:
        logger.exception(f"Background enqueue failed: content_id={content_id}")


async def mark_historical_parse_success_as_pushed_for_rule(
    *,
    session: AsyncSession,
    rule_id: int,
    bot_chat_id: Optional[int] = None,
) -> int:
    """
    将历史 parse_success 内容在指定规则（可选限定到指定 bot_chat）下标记为已推送。

    用途：
    1) 处理脚本回填历史数据；
    2) 新增规则目标/规则绑定时，避免出现“历史内容悬空待推送”。

    Returns:
        新插入的 success 队列项数量
    """
    rule_result = await session.execute(
        select(DistributionRule).where(DistributionRule.id == rule_id)
    )
    rule = rule_result.scalar_one_or_none()
    if not rule:
        logger.warning("Backfill skipped, rule not found: rule_id=%s", rule_id)
        return 0

    target_query = (
        select(DistributionTarget, BotChat)
        .join(BotChat, DistributionTarget.bot_chat_id == BotChat.id)
        .where(DistributionTarget.rule_id == rule_id)
        .where(DistributionTarget.enabled == True)
        .where(BotChat.enabled == True)
        .where(BotChat.is_accessible == True)
    )
    if bot_chat_id is not None:
        target_query = target_query.where(DistributionTarget.bot_chat_id == bot_chat_id)

    targets_result = await session.execute(target_query)
    target_pairs = targets_result.all()
    if not target_pairs:
        return 0

    target_chat_ids = [int(chat.id) for _, chat in target_pairs]
    existing_result = await session.execute(
        select(ContentQueueItem.content_id, ContentQueueItem.bot_chat_id)
        .where(ContentQueueItem.rule_id == rule_id)
        .where(ContentQueueItem.bot_chat_id.in_(target_chat_ids))
    )
    existing_keys = {(int(content_id), int(chat_id)) for content_id, chat_id in existing_result.all()}

    contents_result = await session.execute(
        select(Content)
        .where(Content.status == ContentStatus.PARSE_SUCCESS)
        .order_by(Content.id.asc())
    )
    contents = contents_result.scalars().all()
    if not contents:
        return 0

    engine = DistributionEngine(session)
    now = utcnow()
    rows = []

    for content in contents:
        matched = await engine._check_match(content, rule)
        for _, bot_chat in target_pairs:
            key = (int(content.id), int(bot_chat.id))
            if key in existing_keys:
                continue

            decision = evaluate_target_decision(
                content=content,
                rule=rule,
                bot_chat=bot_chat,
                require_approval=True,
            )

            if decision.bucket != DECISION_FILTERED:
                status = QueueItemStatus.SUCCESS
                last_error = None
                last_error_type = None
                completed_at = now
                approved_at = now
            else:
                status = QueueItemStatus.SKIPPED
                last_error = decision.reason or "Filtered by unified decision"
                last_error_type = decision.reason_code or "filtered_by_decision"
                completed_at = now
                approved_at = None

            rows.append(
                {
                    "content_id": int(content.id),
                    "rule_id": int(rule_id),
                    "bot_chat_id": int(bot_chat.id),
                    "target_platform": bot_chat.platform_type,
                    "target_id": decision.target_id or bot_chat.chat_id,
                    "status": status,
                    "priority": 0,
                    "scheduled_at": now,
                    "needs_approval": False,
                    "approved_at": approved_at,
                    "started_at": now,
                    "completed_at": completed_at,
                    "last_error": last_error,
                    "last_error_type": last_error_type,
                    "nsfw_routing_result": decision.nsfw_routing_result,
                    "created_at": now,
                    "updated_at": now,
                }
            )

    if not rows:
        return 0

    await session.execute(insert(ContentQueueItem), rows)
    inserted = len(rows)
    if inserted > 0:
        logger.info(
            "Backfilled historical queue items by rule: rule_id={}, bot_chat_id={}, inserted={}",
            rule_id,
            bot_chat_id,
            inserted,
        )
    return inserted
