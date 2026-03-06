"""
Tests for the Telegram monitoring hook (app.bot.monitoring).
"""
import pytest
from datetime import timedelta
from unittest.mock import AsyncMock, MagicMock, patch

from app.bot.monitoring import extract_urls, handle_monitored_message


# ---------------------------------------------------------------------------
# extract_urls tests
# ---------------------------------------------------------------------------

class TestExtractUrls:
    def test_single_url(self):
        assert extract_urls("check https://example.com") == ["https://example.com"]

    def test_multiple_urls(self):
        text = "see https://a.com and http://b.org/path?x=1"
        urls = extract_urls(text)
        assert urls == ["https://a.com", "http://b.org/path?x=1"]

    def test_no_urls(self):
        assert extract_urls("no links here") == []

    def test_empty_and_none(self):
        assert extract_urls("") == []
        assert extract_urls(None) == []

    def test_url_with_trailing_punctuation(self):
        # Regex grabs up to whitespace; trailing comma/period may be included
        urls = extract_urls("visit https://example.com/page, ok")
        assert len(urls) == 1
        assert urls[0].startswith("https://example.com/page")

    def test_url_with_query_and_fragment(self):
        text = "https://example.com/p?a=1&b=2#sec"
        urls = extract_urls(text)
        assert len(urls) == 1
        assert "a=1" in urls[0]


# ---------------------------------------------------------------------------
# handle_monitored_message tests
# ---------------------------------------------------------------------------

def _make_update(chat_id: int, text: str):
    """Helper to build a mocked Telegram Update."""
    update = MagicMock()
    update.effective_message.text = text
    update.effective_chat.id = chat_id
    return update


def _make_context(bot_config_id=1):
    ctx = MagicMock()
    ctx.bot_data = {"bot_config_id": bot_config_id}
    return ctx


@pytest.mark.asyncio
async def test_skips_non_monitoring_chat():
    """Non-monitoring chat → no Content created."""
    update = _make_update(-100, "https://example.com")
    context = _make_context()

    # DB returns no BotChat (is_monitoring=False or chat not found)
    fake_session = AsyncMock()
    fake_result = MagicMock()
    fake_result.scalars.return_value.first.return_value = None
    fake_session.execute.return_value = fake_result

    async_ctx = AsyncMock()
    async_ctx.__aenter__.return_value = fake_session

    with patch("app.bot.monitoring.AsyncSessionLocal", return_value=async_ctx):
        await handle_monitored_message(update, context)

    fake_session.add.assert_not_called()
    fake_session.commit.assert_not_called()


@pytest.mark.asyncio
async def test_creates_content_for_monitoring_chat():
    """Monitoring chat with a URL → Content record created and committed."""
    update = _make_update(-200, "look at https://news.example.com/article")
    context = _make_context()

    # First execute: BotChat query → returns a chat with is_monitoring
    bot_chat_mock = MagicMock()
    bot_chat_mock.is_monitoring = True

    # Second execute: dedup query → no duplicate
    dedup_result = MagicMock()
    dedup_result.scalars.return_value.first.return_value = None

    chat_result = MagicMock()
    chat_result.scalars.return_value.first.return_value = bot_chat_mock

    fake_session = AsyncMock()
    fake_session.execute.side_effect = [chat_result, dedup_result]

    async_ctx = AsyncMock()
    async_ctx.__aenter__.return_value = fake_session

    with patch("app.bot.monitoring.AsyncSessionLocal", return_value=async_ctx):
        await handle_monitored_message(update, context)

    fake_session.add.assert_called_once()
    content_obj = fake_session.add.call_args[0][0]

    from app.models import Platform, ContentStatus, DiscoveryState

    assert content_obj.platform == Platform.UNIVERSAL
    assert content_obj.status == ContentStatus.UNPROCESSED
    assert content_obj.discovery_state == DiscoveryState.INGESTED
    assert content_obj.source_type == "telegram_bot"
    assert content_obj.url == "https://news.example.com/article"
    assert content_obj.title.startswith("look at")
    assert content_obj.expire_at is not None

    fake_session.commit.assert_awaited_once()


@pytest.mark.asyncio
async def test_dedup_skips_existing_url():
    """If canonical_url already exists in DB, do not insert again."""
    update = _make_update(-300, "dup https://dup.example.com")
    context = _make_context()

    bot_chat_mock = MagicMock()
    bot_chat_mock.is_monitoring = True

    chat_result = MagicMock()
    chat_result.scalars.return_value.first.return_value = bot_chat_mock

    # Dedup query returns an existing id
    dedup_result = MagicMock()
    dedup_result.scalars.return_value.first.return_value = 42

    fake_session = AsyncMock()
    fake_session.execute.side_effect = [chat_result, dedup_result]

    async_ctx = AsyncMock()
    async_ctx.__aenter__.return_value = fake_session

    with patch("app.bot.monitoring.AsyncSessionLocal", return_value=async_ctx):
        await handle_monitored_message(update, context)

    fake_session.add.assert_not_called()
    fake_session.commit.assert_awaited_once()


@pytest.mark.asyncio
async def test_no_text_message_ignored():
    """Messages without text are silently ignored."""
    update = MagicMock()
    update.effective_message.text = None
    context = _make_context()

    with patch("app.bot.monitoring.AsyncSessionLocal") as mock_session:
        await handle_monitored_message(update, context)
    mock_session.assert_not_called()


@pytest.mark.asyncio
async def test_no_urls_in_text():
    """Monitoring chat message without URLs → commit but no add."""
    update = _make_update(-400, "just some text without links")
    context = _make_context()

    bot_chat_mock = MagicMock()
    bot_chat_mock.is_monitoring = True

    chat_result = MagicMock()
    chat_result.scalars.return_value.first.return_value = bot_chat_mock

    fake_session = AsyncMock()
    fake_session.execute.return_value = chat_result

    async_ctx = AsyncMock()
    async_ctx.__aenter__.return_value = fake_session

    with patch("app.bot.monitoring.AsyncSessionLocal", return_value=async_ctx):
        await handle_monitored_message(update, context)

    fake_session.add.assert_not_called()


@pytest.mark.asyncio
async def test_multiple_urls_creates_multiple_records():
    """Message with 2 URLs → 2 Content records added."""
    update = _make_update(-500, "https://a.com https://b.com")
    context = _make_context()

    bot_chat_mock = MagicMock()
    bot_chat_mock.is_monitoring = True

    chat_result = MagicMock()
    chat_result.scalars.return_value.first.return_value = bot_chat_mock

    # Both dedup checks return no match
    dedup_none_1 = MagicMock()
    dedup_none_1.scalars.return_value.first.return_value = None
    dedup_none_2 = MagicMock()
    dedup_none_2.scalars.return_value.first.return_value = None

    fake_session = AsyncMock()
    fake_session.execute.side_effect = [chat_result, dedup_none_1, dedup_none_2]

    async_ctx = AsyncMock()
    async_ctx.__aenter__.return_value = fake_session

    with patch("app.bot.monitoring.AsyncSessionLocal", return_value=async_ctx):
        await handle_monitored_message(update, context)

    assert fake_session.add.call_count == 2
    fake_session.commit.assert_awaited_once()


@pytest.mark.asyncio
async def test_exception_is_logged_not_raised():
    """DB errors are caught and logged, not propagated."""
    update = _make_update(-600, "https://err.example.com")
    context = _make_context()

    async_ctx = AsyncMock()
    async_ctx.__aenter__.side_effect = RuntimeError("db boom")

    with patch("app.bot.monitoring.AsyncSessionLocal", return_value=async_ctx), \
         patch("app.bot.monitoring.logger") as mock_logger:
        await handle_monitored_message(update, context)

    mock_logger.exception.assert_called_once()
