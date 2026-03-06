"""
Tests for Discovery & Patrol system models (Step 1)
"""
import pytest
from datetime import datetime, timedelta

from app.models import (
    Content, DiscoverySource, BotChat, BotConfig,
    DiscoveryState, DiscoverySourceKind, Platform, ContentStatus, BotChatType, BotConfigPlatform,
)
from app.core.time_utils import utcnow


class TestDiscoveryStateEnum:
    """DiscoveryState 枚举测试"""

    def test_all_states_defined(self):
        states = [s.value for s in DiscoveryState]
        assert states == ["ingested", "scored", "visible", "promoted", "ignored", "merged", "expired"]

    def test_state_is_string_enum(self):
        assert DiscoveryState.INGESTED == "ingested"
        assert isinstance(DiscoveryState.VISIBLE, str)


class TestDiscoverySourceKindEnum:
    """DiscoverySourceKind 枚举测试"""

    def test_all_kinds_defined(self):
        kinds = [k.value for k in DiscoverySourceKind]
        assert kinds == ["rss", "hackernews", "reddit", "github", "telegram_channel"]


class TestContentDiscoveryFields:
    """Content 模型发现流字段测试"""

    @pytest.mark.asyncio
    async def test_content_discovery_fields_writable(self, db_session):
        """验证新增的发现流字段可正常读写"""
        now = utcnow()
        content = Content(
            platform=Platform.UNIVERSAL,
            url="https://example.com/test-discovery",
            canonical_url="https://example.com/test-discovery",
            status=ContentStatus.UNPROCESSED,
            source_type="rss",
            discovery_state=DiscoveryState.INGESTED,
            ai_reason="Relevant to AI/ML interests",
            ai_tags=["ai", "machine-learning"],
            discovered_at=now,
            expire_at=now + timedelta(days=7),
        )
        db_session.add(content)
        await db_session.commit()
        await db_session.refresh(content)

        assert content.id is not None
        assert content.discovery_state == DiscoveryState.INGESTED
        assert content.ai_reason == "Relevant to AI/ML interests"
        assert content.ai_tags == ["ai", "machine-learning"]
        assert content.expire_at is not None
        assert content.promoted_at is None

    @pytest.mark.asyncio
    async def test_content_discovery_state_nullable(self, db_session):
        """discovery_state 为 null 表示主库内容（非发现流）"""
        content = Content(
            platform=Platform.UNIVERSAL,
            url="https://example.com/main-lib-content",
            canonical_url="https://example.com/main-lib-content",
            status=ContentStatus.PARSE_SUCCESS,
            source_type="user_submit",
        )
        db_session.add(content)
        await db_session.commit()
        await db_session.refresh(content)

        assert content.discovery_state is None

    @pytest.mark.asyncio
    async def test_content_state_transition_to_promoted(self, db_session):
        """验证状态可从 visible 更新为 promoted"""
        now = utcnow()
        content = Content(
            platform=Platform.UNIVERSAL,
            url="https://example.com/test-promote",
            canonical_url="https://example.com/test-promote",
            status=ContentStatus.UNPROCESSED,
            source_type="rss",
            discovery_state=DiscoveryState.VISIBLE,
            discovered_at=now,
        )
        db_session.add(content)
        await db_session.commit()

        content.discovery_state = DiscoveryState.PROMOTED
        content.promoted_at = utcnow()
        await db_session.commit()
        await db_session.refresh(content)

        assert content.discovery_state == DiscoveryState.PROMOTED
        assert content.promoted_at is not None


class TestDiscoverySourceModel:
    """DiscoverySource 模型测试"""

    @pytest.mark.asyncio
    async def test_create_rss_source(self, db_session):
        source = DiscoverySource(
            kind=DiscoverySourceKind.RSS,
            name="Simon Willison's Blog",
            enabled=True,
            config={"url": "https://simonwillison.net/atom/everything/", "category": "tech"},
            sync_interval_minutes=60,
        )
        db_session.add(source)
        await db_session.commit()
        await db_session.refresh(source)

        assert source.id is not None
        assert source.kind == DiscoverySourceKind.RSS
        assert source.config["url"] == "https://simonwillison.net/atom/everything/"
        assert source.last_sync_at is None
        assert source.last_cursor is None

    @pytest.mark.asyncio
    async def test_create_hackernews_source(self, db_session):
        source = DiscoverySource(
            kind=DiscoverySourceKind.HACKERNEWS,
            name="Hacker News Top",
            config={"fetch_top_stories": 30, "min_score": 100},
        )
        db_session.add(source)
        await db_session.commit()
        await db_session.refresh(source)

        assert source.kind == DiscoverySourceKind.HACKERNEWS
        assert source.config["min_score"] == 100

    @pytest.mark.asyncio
    async def test_update_sync_state(self, db_session):
        """验证同步状态可正常更新"""
        source = DiscoverySource(
            kind=DiscoverySourceKind.RSS,
            name="Test Feed",
            config={"url": "https://example.com/feed"},
        )
        db_session.add(source)
        await db_session.commit()

        source.last_sync_at = utcnow()
        source.last_cursor = "entry-id-12345"
        await db_session.commit()
        await db_session.refresh(source)

        assert source.last_sync_at is not None
        assert source.last_cursor == "entry-id-12345"

    @pytest.mark.asyncio
    async def test_record_sync_error(self, db_session):
        source = DiscoverySource(
            kind=DiscoverySourceKind.REDDIT,
            name="r/MachineLearning",
            config={"subreddit": "MachineLearning"},
        )
        db_session.add(source)
        await db_session.commit()

        source.last_error = "HTTP 429 Too Many Requests"
        await db_session.commit()
        await db_session.refresh(source)

        assert source.last_error == "HTTP 429 Too Many Requests"


class TestBotChatEnhancement:
    """BotChat 新增字段测试"""

    @pytest.mark.asyncio
    async def test_monitoring_and_push_target_defaults(self, db_session):
        """验证 is_monitoring / is_push_target 默认为 False"""
        bot_config = BotConfig(
            platform=BotConfigPlatform.TELEGRAM,
            name="Test Bot",
            bot_token="test-token",
        )
        db_session.add(bot_config)
        await db_session.commit()

        chat = BotChat(
            bot_config_id=bot_config.id,
            chat_id="-100123456",
            chat_type=BotChatType.SUPERGROUP,
            title="Test Group",
        )
        db_session.add(chat)
        await db_session.commit()
        await db_session.refresh(chat)

        assert chat.is_monitoring is False
        assert chat.is_push_target is False

    @pytest.mark.asyncio
    async def test_enable_monitoring(self, db_session):
        bot_config = BotConfig(
            platform=BotConfigPlatform.TELEGRAM,
            name="Test Bot 2",
            bot_token="test-token-2",
        )
        db_session.add(bot_config)
        await db_session.commit()

        chat = BotChat(
            bot_config_id=bot_config.id,
            chat_id="-100789012",
            chat_type=BotChatType.CHANNEL,
            title="Test Channel",
        )
        db_session.add(chat)
        await db_session.commit()

        chat.is_monitoring = True
        chat.is_push_target = True
        await db_session.commit()
        await db_session.refresh(chat)

        assert chat.is_monitoring is True
        assert chat.is_push_target is True
