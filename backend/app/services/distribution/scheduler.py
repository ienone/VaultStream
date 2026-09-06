"""Public distribution queue enqueueing helpers."""
from typing import Optional

from sqlalchemy.ext.asyncio import AsyncSession

from app.core.database import AsyncSessionLocal
from app.core.logging import logger
from app.services.distribution.service import DistributionService


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
        force: 若为 True，则重置已失败的队列项为 SCHEDULED

    Returns:
        创建或更新的队列项数量
    """
    if session is not None:
        return await DistributionService(session).enqueue_content(content_id, force=force)

    async with AsyncSessionLocal() as session:
        return await DistributionService(session).enqueue_content(content_id, force=force)


async def enqueue_content_background(content_id: int) -> None:
    """
    后台入队包装器（fire-and-forget）。

    自动创建数据库会话，捕获并记录所有异常。
    """
    try:
        async with AsyncSessionLocal() as session:
            await DistributionService(session).enqueue_content(content_id, force=False)
    except Exception:
        logger.exception(f"Background enqueue failed: content_id={content_id}")
