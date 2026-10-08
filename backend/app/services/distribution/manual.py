"""Explicit, target-scoped sends share the durable delivery queue."""
from fastapi import HTTPException
from sqlalchemy import select, text
from sqlalchemy.dialects.sqlite import insert
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.time_utils import utcnow
from app.models import BotChat, BotConfig, Content, ContentStatus, ContentQueueItem, PushedRecord, QueueItemStatus
from app.schemas.queue import ManualPushRequest, ManualPushResponse
from app.services.automation_policy import AutomationPolicyService


async def prepare_manual_push(db: AsyncSession, payload: ManualPushRequest) -> ManualPushResponse:
    content_ids = list(dict.fromkeys(payload.content_ids))
    chat_ids = list(dict.fromkeys(payload.bot_chat_ids))
    if len(content_ids) * len(chat_ids) > 100:
        raise HTTPException(422, "一次最多发送 100 个内容与目标组合")
    contents = list((await db.scalars(select(Content).where(Content.id.in_(content_ids)))).all())
    chats = list((await db.scalars(select(BotChat).join(BotConfig).where(
        BotChat.id.in_(chat_ids), BotChat.enabled.is_(True), BotChat.is_accessible.is_(True),
        BotChat.is_push_target.is_(True), BotConfig.enabled.is_(True), BotConfig.is_primary.is_(True),
    ))).all())
    if len(chats) != len(chat_ids):
        raise HTTPException(409, "所选推送目标不可用，请刷新目标列表")
    if len(contents) != len(content_ids) or any(c.deleted_at is not None or c.status != ContentStatus.PARSE_SUCCESS for c in contents):
        raise HTTPException(409, "所选内容已删除或尚未解析完成")
    for content in contents:
        policy = await AutomationPolicyService().aggregation_delivery(content)
        if not policy.allowed:
            raise HTTPException(409, policy.reason)
    item_ids, already_sent = [], 0
    for content in contents:
        for chat in chats:
            peers = list((await db.scalars(select(ContentQueueItem).where(
                ContentQueueItem.content_id == content.id,
                ContentQueueItem.target_platform == chat.platform_type,
                ContentQueueItem.target_id == chat.chat_id,
            ))).all())
            if any(p.status == QueueItemStatus.PROCESSING or p.last_error_type == "delivery_unknown" for p in peers):
                raise HTTPException(409, "内容正在发送或未收到发送回执，本次未发送")
            sent = await db.scalar(select(PushedRecord.id).where(
                PushedRecord.content_id == content.id, PushedRecord.target_platform == chat.platform_type,
                PushedRecord.target_id == chat.chat_id,
            ).limit(1))
            if sent:
                already_sent += 1
                continue
            await db.execute(insert(ContentQueueItem).values(
                content_id=content.id, rule_id=None, bot_chat_id=chat.id,
                target_platform=chat.platform_type, target_id=chat.chat_id,
                approved_by="manual", status=QueueItemStatus.FAILED,
                last_error_type="manual_ready", last_error="等待手动发送", scheduled_at=utcnow(),
            ).on_conflict_do_nothing(index_elements=["content_id", "bot_chat_id"],
                                     index_where=text("rule_id IS NULL AND (last_error_type IS NULL OR last_error_type != 'delivery_unknown')")))
            item = await db.scalar(select(ContentQueueItem).where(
                ContentQueueItem.content_id == content.id, ContentQueueItem.bot_chat_id == chat.id,
                ContentQueueItem.rule_id.is_(None),
            ))
            item_ids.append(item.id)
    await db.commit()
    return ManualPushResponse(item_ids=item_ids, already_sent=already_sent)
