"""
队列入队服务 - 事件驱动的内容入队逻辑。

根据分发规则匹配结果，为每个 (Content × Rule × BotChat) 组合创建队列项。
"""
from typing import Optional

from sqlalchemy import select, and_
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.database import AsyncSessionLocal
from app.core.logging import logger
from app.core.time_utils import utcnow
from app.distribution.engine import DistributionEngine
from app.models import (
    Content,
    DistributionRule,
    DistributionTarget,
    BotChat,
    ContentQueueItem,
    QueueItemStatus,
    ContentStatus,
    ReviewStatus,
)


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
    if content.status != ContentStatus.PULLED:
        logger.info(
            f"Content not eligible (status): content_id={content_id}, status={content.status}"
        )
        return 0

    if content.review_status not in (ReviewStatus.APPROVED, ReviewStatus.AUTO_APPROVED):
        logger.info(
            f"Content not eligible (review): content_id={content_id}, "
            f"review_status={content.review_status}"
        )
        return 0

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
        .where(BotChat.can_post == True)
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
    scheduled_time = utcnow()

    for rule_id, pairs in rule_targets.items():
        rule = rules_map.get(rule_id)
        if not rule:
            continue

        for target, bot_chat in pairs:
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
                    existing.status = QueueItemStatus.PENDING
                    existing.attempt_count = 0
                    existing.last_error = None
                    existing.last_error_type = None
                    existing.last_error_at = None
                    existing.next_attempt_at = None
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
            needs_approval = (
                rule.approval_required
                and content.review_status == ReviewStatus.PENDING
            )
            status = QueueItemStatus.PENDING if needs_approval else QueueItemStatus.SCHEDULED

            item = ContentQueueItem(
                content_id=content_id,
                rule_id=rule.id,
                bot_chat_id=bot_chat.id,
                target_platform=bot_chat.platform_type,
                target_id=bot_chat.chat_id,
                status=status,
                priority=rule.priority + content.queue_priority,
                scheduled_at=scheduled_time,
                needs_approval=needs_approval,
            )
            session.add(item)
            count += 1

    if count > 0:
        await session.commit()
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
