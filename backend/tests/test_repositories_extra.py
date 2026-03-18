import pytest
from unittest.mock import AsyncMock, patch
from datetime import datetime

from sqlalchemy import delete

from app.models.system import SystemSetting, PushedRecord, ContentQueueItem, QueueItemStatus
from app.models.bot import BotConfig, BotChat, BotChatType, BotConfigPlatform, BotRuntime
from app.models.content import Content
from app.models.base import Platform, ContentStatus
from app.models.distribution import DistributionRule
from app.repositories.system_repository import SystemRepository
from app.repositories.bot_repository import BotRepository
from app.core.time_utils import utcnow


@pytest.fixture(autouse=True)
def mock_event_bus():
    with patch("app.core.events.event_bus.publish", new_callable=AsyncMock) as mock:
        yield mock


@pytest.fixture(autouse=True)
async def clean_tables(db_session):
    yield
    for model in (ContentQueueItem, PushedRecord, Content, DistributionRule, BotChat, BotConfig, BotRuntime, SystemSetting):
        await db_session.execute(delete(model))
    await db_session.commit()


# ========================
# SystemRepository Tests
# ========================

@pytest.mark.asyncio
async def test_system_repo_upsert_create(db_session):
    repo = SystemRepository(db_session)
    setting = await repo.upsert_setting("test_key", "test_value", category="general", description="desc")
    await db_session.commit()
    assert setting.key == "test_key"
    assert setting.value == "test_value"
    assert setting.category == "general"
    assert setting.description == "desc"


@pytest.mark.asyncio
async def test_system_repo_upsert_update(db_session):
    repo = SystemRepository(db_session)
    await repo.upsert_setting("upd_key", "old_val", category="general")
    await db_session.commit()

    updated = await repo.upsert_setting("upd_key", "new_val", category="general", description="updated")
    await db_session.commit()
    assert updated.value == "new_val"
    assert updated.description == "updated"


@pytest.mark.asyncio
async def test_system_repo_get_setting(db_session):
    repo = SystemRepository(db_session)
    await repo.upsert_setting("find_me", {"nested": True}, category="test")
    await db_session.commit()

    found = await repo.get_setting("find_me")
    assert found is not None
    assert found.value == {"nested": True}


@pytest.mark.asyncio
async def test_system_repo_get_setting_not_found(db_session):
    repo = SystemRepository(db_session)
    result = await repo.get_setting("nonexistent_key")
    assert result is None


@pytest.mark.asyncio
async def test_system_repo_list_settings(db_session):
    repo = SystemRepository(db_session)
    await repo.upsert_setting("k1", "v1", category="a")
    await repo.upsert_setting("k2", "v2", category="b")
    await db_session.commit()

    all_settings = await repo.list_settings()
    keys = {s.key for s in all_settings}
    assert "k1" in keys
    assert "k2" in keys


@pytest.mark.asyncio
async def test_system_repo_list_settings_by_category(db_session):
    repo = SystemRepository(db_session)
    await repo.upsert_setting("cat_a1", "v", category="alpha")
    await repo.upsert_setting("cat_a2", "v", category="alpha")
    await repo.upsert_setting("cat_b1", "v", category="beta")
    await db_session.commit()

    alpha = await repo.list_settings(category="alpha")
    assert len(alpha) == 2
    assert all(s.category == "alpha" for s in alpha)


@pytest.mark.asyncio
async def test_system_repo_delete_setting(db_session):
    repo = SystemRepository(db_session)
    setting = await repo.upsert_setting("del_key", "val", category="general")
    await db_session.commit()

    await repo.delete_setting(setting)
    await db_session.commit()

    result = await repo.get_setting("del_key")
    assert result is None


@pytest.mark.asyncio
async def test_system_repo_pushed_records(db_session):
    repo = SystemRepository(db_session)

    content = Content(title="Test", url="http://test.com", platform=Platform.TWITTER, created_at=utcnow())
    db_session.add(content)
    await db_session.flush()

    rec = await repo.create_pushed_record(
        content_id=content.id,
        target_platform="telegram",
        target_id="chan_1",
        push_status="success",
    )
    await db_session.commit()
    assert rec.id is not None
    assert rec.content_id == content.id

    records = await repo.list_pushed_records(content_id=content.id)
    assert len(records) == 1
    assert records[0].target_platform == "telegram"


@pytest.mark.asyncio
async def test_system_repo_queue_items(db_session):
    repo = SystemRepository(db_session)

    content = Content(title="Q", url="http://q.com", platform=Platform.TWITTER, created_at=utcnow())
    db_session.add(content)
    await db_session.flush()

    rule = DistributionRule(name="rule_q", match_conditions={"platform": "twitter"})
    db_session.add(rule)
    await db_session.flush()

    bot_cfg = BotConfig(platform=BotConfigPlatform.TELEGRAM, name="bot_q")
    db_session.add(bot_cfg)
    await db_session.flush()

    chat = BotChat(bot_config_id=bot_cfg.id, chat_id="q_chat", chat_type=BotChatType.CHANNEL, enabled=True)
    db_session.add(chat)
    await db_session.flush()

    item = ContentQueueItem(
        content_id=content.id,
        rule_id=rule.id,
        bot_chat_id=chat.id,
        target_platform="telegram",
        target_id="q_chat",
        status=QueueItemStatus.SCHEDULED,
        created_at=utcnow(),
    )
    db_session.add(item)
    await db_session.commit()

    found = await repo.get_queue_item(item.id)
    assert found is not None
    assert found.status == QueueItemStatus.SCHEDULED

    items, total = await repo.list_queue_items(status=QueueItemStatus.SCHEDULED)
    assert total >= 1
    assert any(i.id == item.id for i in items)


@pytest.mark.asyncio
async def test_system_repo_queue_stats(db_session):
    repo = SystemRepository(db_session)

    content = Content(title="S", url="http://s.com", platform=Platform.TWITTER, created_at=utcnow())
    db_session.add(content)
    await db_session.flush()

    rule = DistributionRule(name="rule_s", match_conditions={"platform": "twitter"})
    db_session.add(rule)
    await db_session.flush()

    bot_cfg = BotConfig(platform=BotConfigPlatform.TELEGRAM, name="bot_s")
    db_session.add(bot_cfg)
    await db_session.flush()

    chats = []
    for i in range(3):
        c = BotChat(bot_config_id=bot_cfg.id, chat_id=f"s_chat_{i}", chat_type=BotChatType.CHANNEL, enabled=True)
        db_session.add(c)
        chats.append(c)
    await db_session.flush()

    for chat_obj, st in zip(chats, [QueueItemStatus.SCHEDULED, QueueItemStatus.FAILED, QueueItemStatus.SUCCESS]):
        qi = ContentQueueItem(
            content_id=content.id,
            rule_id=rule.id,
            bot_chat_id=chat_obj.id,
            target_platform="telegram",
            target_id=chat_obj.chat_id,
            status=st,
            created_at=utcnow(),
        )
        db_session.add(qi)
    await db_session.commit()

    stats = await repo.get_queue_stats()
    assert stats["scheduled"] >= 1
    assert stats["failed"] >= 1
    assert stats["success"] >= 1
    for s in QueueItemStatus:
        assert s.value in stats


# ========================
# BotRepository Tests
# ========================

@pytest.mark.asyncio
async def test_bot_repo_create_config(db_session):
    repo = BotRepository(db_session)
    cfg = await repo.create_config(
        platform=BotConfigPlatform.TELEGRAM,
        name="my_bot",
        bot_token="tok123",
        enabled=True,
    )
    await db_session.commit()
    assert cfg.id is not None
    assert cfg.name == "my_bot"
    assert cfg.platform == BotConfigPlatform.TELEGRAM


@pytest.mark.asyncio
async def test_bot_repo_get_config_by_id(db_session):
    repo = BotRepository(db_session)
    cfg = await repo.create_config(platform=BotConfigPlatform.QQ, name="qq_bot")
    await db_session.commit()

    found = await repo.get_config_by_id(cfg.id)
    assert found is not None
    assert found.name == "qq_bot"


@pytest.mark.asyncio
async def test_bot_repo_list_configs(db_session):
    repo = BotRepository(db_session)
    await repo.create_config(platform=BotConfigPlatform.TELEGRAM, name="b1", enabled=True)
    await repo.create_config(platform=BotConfigPlatform.QQ, name="b2", enabled=False)
    await db_session.commit()

    all_cfgs = await repo.list_configs()
    names = {c.name for c in all_cfgs}
    assert "b1" in names
    assert "b2" in names


@pytest.mark.asyncio
async def test_bot_repo_list_configs_enabled(db_session):
    repo = BotRepository(db_session)
    await repo.create_config(platform=BotConfigPlatform.TELEGRAM, name="en1", enabled=True)
    await repo.create_config(platform=BotConfigPlatform.TELEGRAM, name="en2", enabled=False)
    await db_session.commit()

    enabled = await repo.list_configs(enabled=True)
    assert all(c.enabled for c in enabled)
    assert any(c.name == "en1" for c in enabled)


@pytest.mark.asyncio
async def test_bot_repo_get_primary_config(db_session):
    repo = BotRepository(db_session)
    await repo.create_config(platform=BotConfigPlatform.TELEGRAM, name="non_primary", enabled=True, is_primary=False)
    await repo.create_config(platform=BotConfigPlatform.TELEGRAM, name="primary_one", enabled=True, is_primary=True)
    await db_session.commit()

    primary = await repo.get_primary_config(BotConfigPlatform.TELEGRAM)
    assert primary is not None
    assert primary.name == "primary_one"


@pytest.mark.asyncio
async def test_bot_repo_get_primary_fallback(db_session):
    repo = BotRepository(db_session)
    await repo.create_config(platform=BotConfigPlatform.QQ, name="fallback_bot", enabled=True, is_primary=False)
    await db_session.commit()

    result = await repo.get_primary_config(BotConfigPlatform.QQ)
    assert result is not None
    assert result.name == "fallback_bot"


@pytest.mark.asyncio
async def test_bot_repo_delete_config(db_session):
    repo = BotRepository(db_session)
    cfg = await repo.create_config(platform=BotConfigPlatform.TELEGRAM, name="del_bot")
    await db_session.commit()

    await repo.delete_config(cfg)
    await db_session.commit()

    result = await repo.get_config_by_id(cfg.id)
    assert result is None


@pytest.mark.asyncio
async def test_bot_repo_create_chat(db_session):
    repo = BotRepository(db_session)
    cfg = await repo.create_config(platform=BotConfigPlatform.TELEGRAM, name="chat_bot")
    await db_session.flush()

    chat = await repo.create_chat(
        bot_config_id=cfg.id,
        chat_id="chat_001",
        chat_type=BotChatType.CHANNEL,
        title="Test Channel",
        enabled=True,
    )
    await db_session.commit()
    assert chat.id is not None
    assert chat.chat_id == "chat_001"
    assert chat.title == "Test Channel"


@pytest.mark.asyncio
async def test_bot_repo_get_chat_by_id(db_session):
    repo = BotRepository(db_session)
    cfg = await repo.create_config(platform=BotConfigPlatform.TELEGRAM, name="cbi_bot")
    await db_session.flush()

    chat = await repo.create_chat(bot_config_id=cfg.id, chat_id="cbi_1", chat_type=BotChatType.GROUP)
    await db_session.commit()

    found = await repo.get_chat_by_id(chat.id)
    assert found is not None
    assert found.chat_id == "cbi_1"


@pytest.mark.asyncio
async def test_bot_repo_get_chat_by_platform_id(db_session):
    repo = BotRepository(db_session)
    cfg = await repo.create_config(platform=BotConfigPlatform.TELEGRAM, name="plat_bot")
    await db_session.flush()

    await repo.create_chat(bot_config_id=cfg.id, chat_id="plat_chat", chat_type=BotChatType.SUPERGROUP)
    await db_session.commit()

    found = await repo.get_chat_by_platform_id(cfg.id, "plat_chat")
    assert found is not None
    assert found.chat_type == BotChatType.SUPERGROUP


@pytest.mark.asyncio
async def test_bot_repo_list_chats_for_config(db_session):
    repo = BotRepository(db_session)
    cfg = await repo.create_config(platform=BotConfigPlatform.TELEGRAM, name="list_chat_bot")
    await db_session.flush()

    await repo.create_chat(bot_config_id=cfg.id, chat_id="lc1", chat_type=BotChatType.CHANNEL, enabled=True)
    await repo.create_chat(bot_config_id=cfg.id, chat_id="lc2", chat_type=BotChatType.GROUP, enabled=False)
    await db_session.commit()

    all_chats = await repo.list_chats_for_config(cfg.id)
    assert len(all_chats) == 2

    enabled_chats = await repo.list_chats_for_config(cfg.id, enabled=True)
    assert len(enabled_chats) == 1
    assert enabled_chats[0].chat_id == "lc1"


@pytest.mark.asyncio
async def test_bot_repo_runtime_create(db_session):
    repo = BotRepository(db_session)

    runtime = await repo.update_runtime(bot_id="bot_99", bot_username="test_user")
    await db_session.commit()
    assert runtime.id == 1
    assert runtime.bot_id == "bot_99"
    assert runtime.bot_username == "test_user"


@pytest.mark.asyncio
async def test_bot_repo_runtime_update(db_session):
    repo = BotRepository(db_session)

    await repo.update_runtime(bot_id="bot_first", bot_username="first")
    await db_session.commit()

    updated = await repo.update_runtime(bot_username="updated_user", version="2.0")
    await db_session.commit()
    assert updated.bot_username == "updated_user"
    assert updated.version == "2.0"
