"""Generated output cannot advance progress on invalid evidence or changed sources."""
import json
from datetime import timedelta
from types import SimpleNamespace
from unittest.mock import AsyncMock
from uuid import uuid4

import pytest
from sqlalchemy import select

from app.core.time_utils import utcnow
from app.models import Content, ContentStatus, Platform, KnowledgeEventMember
from app.services.config_service import ConfigService
from app.services.content_aggregation_service import ContentAggregationService


@pytest.mark.parametrize('case', ['success', 'bad_quote', 'unknown_source', 'changed_source', 'disabled', 'empty'])
async def test_atomic_aggregation_and_evidence(db_session, monkeypatch, case):
    cfg = ConfigService()
    reference = utcnow() + timedelta(days=1)
    stamp = reference - timedelta(hours=1)
    prefix = str(uuid4())
    rows = [Content(platform=Platform.UNIVERSAL, url=f'https://fixture.invalid/{prefix}/{n}',
        canonical_url=f'https://fixture.invalid/{prefix}/{n}', status=ContentStatus.PARSE_SUCCESS,
        title='同一事件', body=f'这是一段共同事件的原始报道内容{n}。', updated_at=stamp) for n in range(2)]
    db_session.add_all(rows)
    await db_session.commit()
    old_cursor = {'updated_at': (stamp - timedelta(seconds=1)).isoformat(), 'id': 0}
    await cfg.set_value('enable_content_aggregation', True)
    await cfg.set_value('enable_aggregation_push', False)
    await cfg.set_value('content_aggregation_cursor', old_cursor)
    await cfg.delete_value('content_aggregation_last_attempt')
    ids = [row.id for row in rows]
    output = {'groups': [{'title': '共同事件', 'source_ids': ids, 'tags': ['事件'],
        'claims': [{'text': '两个来源报道此事。', 'evidence': [
            {'content_id': row.id, 'quote': row.body} for row in rows]}]}]}
    if case == 'bad_quote':
        output['groups'][0]['claims'][0]['evidence'][0]['quote'] = '这段引句从未出现在原始材料中'
    if case == 'unknown_source':
        output['groups'][0]['source_ids'][0] = 99999999
        output['groups'][0]['claims'][0]['evidence'][0]['content_id'] = 99999999
    if case == 'empty':
        output = {'groups': []}

    async def invoke(*args, **kwargs):
        if case == 'changed_source':
            rows[0].body = '用户已经修改正文，旧引句不应保存'
            rows[0].updated_at = reference
            await db_session.commit()
        if case == 'disabled':
            await cfg.set_value('enable_content_aggregation', False)
        return SimpleNamespace(content=json.dumps(output, ensure_ascii=False))
    llm = SimpleNamespace(ainvoke=AsyncMock(side_effect=invoke))
    monkeypatch.setattr('app.services.content_aggregation_service.LLMFactory.get_text_llm', AsyncMock(return_value=llm))
    try:
        service = ContentAggregationService(config_service=cfg)
        result = await service.run_if_due(now=reference)
        cursor = await cfg.get_value_fresh('content_aggregation_cursor')
        if case in ('success', 'empty'):
            assert cursor == {'updated_at': stamp.isoformat(), 'id': ids[-1]}
            assert len(result['content_ids']) == (1 if case == 'success' else 0)
            if case == 'success':
                generated = await db_session.get(Content, result['content_ids'][0])
                assert generated.is_synthesis and generated.source_type == 'ai_aggregation'
                members = (await db_session.execute(select(KnowledgeEventMember).where(
                    KnowledgeEventMember.event_id == result['event_ids'][0]))).scalars().all()
                assert {member.content_id for member in members} == set(ids + result['content_ids'])
                assert all(member.evidence_state.value == 'unverified' for member in members)
                # Replaying the same source batch produces no duplicate event/content.
                await cfg.set_value('content_aggregation_cursor', old_cursor)
                replay = await service.run_if_due(now=reference + timedelta(hours=2))
                assert replay['content_ids'] == [] and replay['event_ids'] == []
        else:
            assert result['status'] == 'error'
            assert cursor == old_cursor
    finally:
        for row in rows:
            row.deleted_at = utcnow()
        await db_session.commit()
        for key in ('enable_content_aggregation', 'enable_aggregation_push', 'content_aggregation_cursor', 'content_aggregation_last_attempt'):
            await cfg.delete_value(key)


async def test_generated_delivery_obeys_switch_and_deduplicates(db_session, monkeypatch):
    from app.models import (BotConfig, BotConfigPlatform, BotChat, BotChatType, DistributionRule,
        DistributionTarget, ContentQueueItem, PushedRecord, QueueItemStatus, ReviewStatus)
    from app.services.distribution import DistributionService
    from app.tasks.distribution_worker import DistributionQueueWorker
    from app.services.agent.tools.push import _push_batch_tool

    cfg = ConfigService()
    await cfg.set_value('distribution_mode', 'auto')
    await cfg.set_value('enable_aggregation_push', False)
    suffix = str(uuid4())
    bot = BotConfig(platform=BotConfigPlatform.TELEGRAM, name=suffix)
    db_session.add(bot)
    await db_session.flush()
    chat = BotChat(bot_config_id=bot.id, chat_id=suffix, chat_type=BotChatType.CHANNEL)
    rule = DistributionRule(name=suffix, match_conditions={})
    content = Content(platform=Platform.UNIVERSAL, url=f'vaultstream://fixture/{suffix}',
        canonical_url=f'vaultstream://fixture/{suffix}', status=ContentStatus.PARSE_SUCCESS,
        source_type='ai_aggregation', is_synthesis=True, title='生成稿', body='尚未核实的事件综合')
    db_session.add_all([chat, rule, content])
    await db_session.flush()
    target = DistributionTarget(rule_id=rule.id, bot_chat_id=chat.id, backfill_watermark=utcnow() - timedelta(days=1))
    db_session.add(target)
    await db_session.commit()
    push = AsyncMock(return_value='fixture-message')
    monkeypatch.setattr('app.tasks.distribution_worker.get_push_service', lambda _: SimpleNamespace(push=push))
    worker = DistributionQueueWorker()
    # Render through the real distributor; only the external push is replaced.
    service = DistributionService(db_session)
    try:
        assert not await service.auto_approve_if_eligible(content)
        await service.refresh_queue_by_rules()
        assert content.review_status == ReviewStatus.PENDING
        await cfg.set_value('enable_aggregation_push', True)
        assert await service.auto_approve_if_eligible(content)
        item = (await db_session.execute(select(ContentQueueItem).where(ContentQueueItem.content_id == content.id))).scalar_one()
        await cfg.set_value('enable_aggregation_push', False)
        assert await service.enqueue_content(content.id, force=True) == 0
        agent_result = await _push_batch_tool({'content_ids': [content.id]}, SimpleNamespace(db=db_session))
        assert agent_result['scheduled_count'] == 0
        await worker._process_item(db_session, item, 'regression')
        assert item.last_error_type == 'aggregation_push_disabled'
        push.assert_not_awaited()
        await cfg.set_value('enable_aggregation_push', True)
        chat.enabled = False
        await db_session.commit()
        await worker._process_item(db_session, item, 'regression')
        assert item.last_error_type == 'target_unavailable'
        push.assert_not_awaited()
        chat.enabled = True
        item.status = QueueItemStatus.PROCESSING
        await db_session.commit()
        agent_result = await _push_batch_tool({'content_ids': [content.id]}, SimpleNamespace(db=db_session))
        assert agent_result['scheduled_count'] == 0
        await worker._process_item(db_session, item, 'regression')
        assert item.status == QueueItemStatus.SUCCESS
        assert push.await_count == 1
        await worker._process_item(db_session, item, 'regression')
        assert push.await_count == 1
        records = (await db_session.execute(select(PushedRecord).where(PushedRecord.content_id == content.id))).scalars().all()
        assert len(records) == 1 and records[0].message_id == 'fixture-message'
    finally:
        rule.enabled = False
        content.deleted_at = utcnow()
        await db_session.commit()
        await cfg.delete_value('enable_aggregation_push')
        await cfg.delete_value('distribution_mode')


@pytest.mark.parametrize('manual_edit', ['none', 'before_run', 'during_model', 'old_revision'])
async def test_late_source_extends_only_untouched_automatic_event(db_session, monkeypatch, manual_edit):
    from app.models import KnowledgeEvent
    cfg = ConfigService()
    reference = utcnow() + timedelta(days=5)
    stamp = reference - timedelta(minutes=1)
    prefix = str(uuid4())
    rows = [Content(platform=Platform.UNIVERSAL, url=f'https://fixture.invalid/{prefix}/{n}',
        canonical_url=f'https://fixture.invalid/{prefix}/{n}', status=ContentStatus.PARSE_SUCCESS,
        title='同一新闻事件', body=f'同一新闻事件的来源正文包含足够引句{n}。', updated_at=stamp) for n in range(2)]
    db_session.add_all(rows)
    await db_session.commit()
    await cfg.set_value('enable_content_aggregation', True)
    await cfg.set_value('enable_aggregation_push', False)
    await cfg.set_value('content_aggregation_cursor', {'updated_at': (stamp-timedelta(seconds=1)).isoformat(), 'id': 0})
    await cfg.delete_value('content_aggregation_last_attempt')
    event_id = None
    target_rows = rows[:]
    async def invoke(*args, **kwargs):
        if event_id and manual_edit == 'during_model':
            event = await db_session.get(KnowledgeEvent, event_id)
            event.title = '用户确认的事件名称'
            event.updated_at = reference + timedelta(minutes=10)
            await db_session.commit()
        output = {'groups': [{'event_id': event_id, 'title': '事件进展', 'source_ids': [row.id for row in target_rows], 'tags': [],
            'claims': [{'text': '这些来源报告同一事件的进展。', 'evidence': [{'content_id': row.id, 'quote': row.body} for row in target_rows]}]}]}
        return SimpleNamespace(content=json.dumps(output, ensure_ascii=False))
    monkeypatch.setattr('app.services.content_aggregation_service.LLMFactory.get_text_llm', AsyncMock(
        return_value=SimpleNamespace(ainvoke=AsyncMock(side_effect=invoke))))
    try:
        service = ContentAggregationService(config_service=cfg)
        first = await service.run_if_due(now=reference)
        event_id = first['event_ids'][0]
        previous = await cfg.get_value_fresh('content_aggregation_cursor')
        if manual_edit == 'before_run':
            event = await db_session.get(KnowledgeEvent, event_id)
            event.title = '用户确认的事件名称'
            event.updated_at = reference + timedelta(minutes=10)
            await db_session.commit()
        if manual_edit == 'old_revision':
            late = rows[1]
            late.body = '这是同一新闻事件原报道十天后修订的正文内容。'
            late.updated_at = reference + timedelta(days=10)
            await db_session.commit()
            second_reference = reference + timedelta(days=10, hours=2)
        else:
            late = Content(platform=Platform.UNIVERSAL, url=f'https://fixture.invalid/{prefix}/late',
                canonical_url=f'https://fixture.invalid/{prefix}/late', status=ContentStatus.PARSE_SUCCESS,
                title='晚到进展', body='这是同一新闻事件晚到的另一条报道正文。', updated_at=reference + timedelta(hours=1))
            db_session.add(late)
            await db_session.commit()
            rows.append(late)
            second_reference = reference + timedelta(hours=2)
        target_rows = [rows[0], late]
        second = await service.run_if_due(now=second_reference)
        members = (await db_session.execute(select(KnowledgeEventMember).where(KnowledgeEventMember.event_id == event_id))).scalars().all()
        if manual_edit in ('none', 'old_revision'):
            assert second['event_ids'] == [event_id]
            assert {member.content_id for member in members} == {row.id for row in rows} | set(first['content_ids'] + second['content_ids'])
            assert (await cfg.get_value_fresh('content_aggregation_cursor'))['id'] == late.id
        else:
            assert second['status'] == 'error'
            assert len(members) == 3
            assert await cfg.get_value_fresh('content_aggregation_cursor') == previous
            event = await db_session.get(KnowledgeEvent, event_id, populate_existing=True)
            assert event.title == '用户确认的事件名称'
    finally:
        for row in rows:
            row.deleted_at = utcnow()
        await db_session.commit()
        for key in ('enable_content_aggregation', 'enable_aggregation_push', 'content_aggregation_cursor', 'content_aggregation_last_attempt'):
            await cfg.delete_value(key)
