import asyncio
from datetime import timedelta
from uuid import uuid4

import pytest
from sqlalchemy import select, update

from app.core.db_adapter import AsyncSessionLocal
from app.core.time_utils import utcnow
from app.models import (
    BotChat,
    BotChatType,
    BotConfig,
    BotConfigPlatform,
    Content,
    ContentQueueItem,
    ContentSource,
    ContentStatus,
    DiscoveryState,
    DistributionRule,
    KnowledgeEvent,
    KnowledgeEventMember,
    KnowledgeEventMemberRole,
    KnowledgeEventStatus,
    Platform,
    PushedRecord,
)
from app.tasks.discovery_cleanup import DiscoveryCleanupTask


def _candidate(now, *, state=DiscoveryState.VISIBLE, expire_offset=-1) -> Content:
    identity = uuid4().hex
    return Content(
        platform=Platform.UNIVERSAL,
        url=f"https://cleanup.test/{identity}",
        canonical_url=identity,
        status=ContentStatus.PARSE_SUCCESS,
        discovery_state=state,
        expire_at=now + timedelta(seconds=expire_offset),
        title=f"候选-{identity}",
        body="必须保留或按规则清理的正文",
    )


@pytest.mark.parametrize("mode", ["hard_delete", "archive", "expire_only"])
async def test_cleanup_modes_share_dependency_retention_rule(db_session, monkeypatch, mode):
    now = utcnow()
    visible = _candidate(now)
    ignored = _candidate(now, state=DiscoveryState.IGNORED)
    boundary = _candidate(now, expire_offset=0)
    event_member = _candidate(now)
    saved = _candidate(now)
    sent = _candidate(now)
    queued = _candidate(now)
    parent = _candidate(now)
    child = _candidate(now)
    bot = BotConfig(platform=BotConfigPlatform.TELEGRAM, name=uuid4().hex)
    rule = DistributionRule(name=uuid4().hex, match_conditions={})
    db_session.add_all([
        visible, ignored, boundary, event_member, saved, sent, queued, parent, child, bot, rule
    ])
    await db_session.flush()
    child.parent_id = parent.id
    chat = BotChat(bot_config_id=bot.id, chat_id=uuid4().hex, chat_type=BotChatType.CHANNEL)
    db_session.add(chat)
    await db_session.flush()
    event = KnowledgeEvent(title="已归档事件", status=KnowledgeEventStatus.ARCHIVED)
    db_session.add(event)
    await db_session.flush()
    db_session.add_all([
        KnowledgeEventMember(
            event_id=event.id,
            content_id=event_member.id,
            role=KnowledgeEventMemberRole.COMMENTARY,
        ),
        ContentSource(content_id=saved.id, source="bilibili_favorites"),
        PushedRecord(
            content_id=sent.id,
            target_platform="telegram",
            target_id=uuid4().hex,
            message_id="sent-message",
        ),
        ContentQueueItem(
            content_id=queued.id,
            rule_id=rule.id,
            bot_chat_id=chat.id,
            target_platform="telegram",
            target_id=chat.chat_id,
        ),
    ])
    await db_session.commit()

    monkeypatch.setattr("app.tasks.discovery_cleanup.utcnow", lambda: now)
    monkeypatch.setattr(
        "app.tasks.discovery_cleanup.get_setting_value", lambda *_: asyncio.sleep(0, result=mode)
    )
    changed = await DiscoveryCleanupTask()._cleanup_expired()

    async with AsyncSessionLocal() as check:
        protected_ids = [
            boundary.id, event_member.id, saved.id, sent.id, queued.id, parent.id, child.id
        ]
        protected = (await check.execute(
            select(Content).where(Content.id.in_(protected_ids))
        )).scalars().all()
        assert {item.id for item in protected} == set(protected_ids)
        assert all(item.deleted_at is None for item in protected)
        assert all(item.discovery_state == DiscoveryState.VISIBLE for item in protected)
        assert (await check.execute(select(KnowledgeEventMember).where(
            KnowledgeEventMember.content_id == event_member.id
        ))).scalar_one() is not None

        if mode == "hard_delete":
            assert changed == 2
            assert await check.get(Content, visible.id) is None
            assert await check.get(Content, ignored.id) is None
        elif mode == "archive":
            assert changed == 2
            assert (await check.get(Content, visible.id)).deleted_at == now
            assert (await check.get(Content, ignored.id)).deleted_at == now
        else:
            assert changed == 0
            assert (await check.get(Content, visible.id)).discovery_state == DiscoveryState.EXPIRED
            assert (await check.get(Content, ignored.id)).discovery_state == DiscoveryState.IGNORED

    # The session-scoped real database is shared by regressions; retire this
    # fixture's TTL without bypassing its real foreign-key relationships.
    async with AsyncSessionLocal() as cleanup_db:
        await cleanup_db.execute(update(Content).where(
            Content.id.in_([visible.id, ignored.id, *protected_ids])
        ).values(expire_at=None))
        await cleanup_db.commit()


async def test_expired_unscored_candidate_is_cleaned(db_session, monkeypatch):
    now = utcnow()
    item = _candidate(now, state=DiscoveryState.INGESTED)
    db_session.add(item)
    await db_session.commit()
    identity = item.id
    monkeypatch.setattr('app.tasks.discovery_cleanup.get_setting_value',
                        lambda *_: asyncio.sleep(0, result='hard_delete'))
    assert await DiscoveryCleanupTask()._cleanup_expired() == 1
    async with AsyncSessionLocal() as check:
        assert await check.get(Content, identity) is None


async def test_media_cleanup_preserves_shared_references_and_fresh_downloads(db_session, tmp_path, monkeypatch):
    import os
    import time
    from app.core.config import settings
    from app.services.media_cleanup import cleanup_unreferenced_media
    monkeypatch.setattr(settings, 'storage_local_root', str(tmp_path))
    keys = [f'vaultstream/blobs/sha256/{x*2}/{x*2}/{x*64}.webp' for x in 'abc']
    for key in keys:
        path = tmp_path / key
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(b'image')
        os.utime(path, (time.time()-172800, time.time()-172800))
    os.utime(tmp_path / keys[2], None)
    item = _candidate(utcnow(), expire_offset=100)
    item.archive_metadata = {'archive': {'images': [{'stored_key': keys[0]}]}}
    db_session.add(item)
    await db_session.commit()
    assert await cleanup_unreferenced_media(db_session) == (1, 5)
    assert (tmp_path / keys[0]).exists()
    assert not (tmp_path / keys[1]).exists()
    assert (tmp_path / keys[2]).exists()
