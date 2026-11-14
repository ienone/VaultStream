"""Explicit, target-scoped sends share the durable delivery queue."""
from fastapi import HTTPException
from sqlalchemy import select, text, tuple_
from sqlalchemy.dialects.sqlite import insert
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import load_only

from app.core.time_utils import utcnow
from app.models import BotChat, BotConfig, Content, ContentStatus, ContentQueueItem, PushedRecord, QueueItemStatus, ReviewStatus
from app.schemas.queue import ManualPushRequest, ManualPushResponse
from app.services.automation_policy import AutomationPolicyService
from app.services.distribution.receipt_policy import ITEM_APPROVAL


async def prepare_manual_push(db: AsyncSession, payload: ManualPushRequest) -> ManualPushResponse:
    content_ids = list(dict.fromkeys(payload.content_ids))
    chat_ids = list(dict.fromkeys(payload.bot_chat_ids))
    if len(content_ids) * len(chat_ids) > 100:
        raise HTTPException(422, "一次最多发送 100 个内容与目标组合")
    contents = list((await db.scalars(select(Content).options(load_only(Content.id, Content.deleted_at, Content.status, Content.source_type, Content.review_status)).where(Content.id.in_(content_ids)))).all())
    chats = list((await db.scalars(select(BotChat).join(BotConfig).where(
        BotChat.id.in_(chat_ids), BotChat.enabled.is_(True), BotChat.is_accessible.is_(True),
        BotChat.is_push_target.is_(True), BotConfig.enabled.is_(True), BotConfig.is_primary.is_(True),
    ))).all())
    if len(chats) != len(chat_ids):
        raise HTTPException(409, "所选推送目标不可用，请刷新目标列表")
    if len(contents) != len(content_ids) or any(c.deleted_at is not None or c.status != ContentStatus.PARSE_SUCCESS for c in contents):
        raise HTTPException(409, "所选内容已删除或尚未解析完成")
    if any(content.review_status == ReviewStatus.REJECTED for content in contents):
        raise HTTPException(409, "所选内容中有已拒绝的项目")
    synthesis = next((content for content in contents if content.source_type == "ai_aggregation"), None)
    if synthesis is not None:
        policy = await AutomationPolicyService().aggregation_delivery(synthesis)
        if not policy.allowed:
            raise HTTPException(409, policy.reason)

    targets = {(chat.platform_type, chat.chat_id) for chat in chats}
    peers = (await db.execute(select(
        ContentQueueItem.content_id, ContentQueueItem.target_platform,
        ContentQueueItem.target_id, ContentQueueItem.status, ContentQueueItem.last_error_type,
    ).where(ContentQueueItem.content_id.in_(content_ids),
            tuple_(ContentQueueItem.target_platform, ContentQueueItem.target_id).in_(targets)))).all()
    if any(peer.status == QueueItemStatus.PROCESSING or peer.last_error_type == "delivery_unknown" for peer in peers):
        raise HTTPException(409, "内容正在发送或未收到发送回执，本次未发送")
    sent = set((await db.execute(select(
        PushedRecord.content_id, PushedRecord.target_platform, PushedRecord.target_id,
    ).where(PushedRecord.content_id.in_(content_ids),
            tuple_(PushedRecord.target_platform, PushedRecord.target_id).in_(targets)))).all())
    pending = [(content.id, chat) for content in contents for chat in chats
               if (content.id, chat.platform_type, chat.chat_id) not in sent]
    already_sent = len(contents) * len(chats) - len(pending)
    if not pending:
        return ManualPushResponse(item_ids=[], already_sent=already_sent)
    now = utcnow()
    await db.execute(insert(ContentQueueItem).values([
        dict(content_id=content_id, rule_id=None, bot_chat_id=chat.id,
             target_platform=chat.platform_type, target_id=chat.chat_id,
             approved_by=ITEM_APPROVAL, status=QueueItemStatus.FAILED,
             last_error_type="manual_ready", last_error="等待手动发送", scheduled_at=now)
        for content_id, chat in pending
    ]).on_conflict_do_nothing(index_elements=["content_id", "bot_chat_id"],
        index_where=text("rule_id IS NULL AND (last_error_type IS NULL OR last_error_type != 'delivery_unknown')")))
    rows = (await db.execute(select(ContentQueueItem.content_id, ContentQueueItem.bot_chat_id,
                                   ContentQueueItem.id).where(
        ContentQueueItem.content_id.in_(content_ids), ContentQueueItem.bot_chat_id.in_(chat_ids),
        ContentQueueItem.rule_id.is_(None),
    ))).all()
    ids = {(row.content_id, row.bot_chat_id): row.id for row in rows}
    await db.commit()
    return ManualPushResponse(item_ids=[ids[(content_id, chat.id)] for content_id, chat in pending],
                              already_sent=already_sent)
