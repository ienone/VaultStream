import pytest
from unittest.mock import MagicMock, AsyncMock, patch
from app.tasks.parsing import ContentParser
from app.models import Content, ContentStatus, Platform
from app.adapters.base import ParsedContent
from sqlalchemy import select

@pytest.fixture(autouse=True)
def mock_event_bus():
    with patch("app.core.events.event_bus.publish", new_callable=AsyncMock) as mock:
        yield mock

@pytest.mark.asyncio
async def test_process_parse_task_success(db_session, monkeypatch):
    # 1. Setup test data in DB
    content = Content(
        url="https://www.bilibili.com/video/BV1GJ411x7h7",
        platform=Platform.BILIBILI,
        status=ContentStatus.UNPROCESSED
    )
    db_session.add(content)
    await db_session.commit()
    await db_session.refresh(content)
    content_id = content.id

    # 2. Mock Adapter and Factory
    mock_parsed = ParsedContent(
        platform="bilibili",
        content_type="video",
        content_id="BV1GJ411x7h7",
        clean_url="https://www.bilibili.com/video/BV1GJ411x7h7",
        title="Mock Title",
        body="Mock Body",
        author_name="Mock Author",
        layout_type="gallery"
    )
    
    mock_adapter = AsyncMock()
    mock_adapter.parse.return_value = mock_parsed
    
    # 3. Patch dependencies
    # We need to monkeypatch AsyncSessionLocal used inside ContentParser
    from tests.conftest import TestingSessionLocal
    monkeypatch.setattr("app.tasks.parsing.AsyncSessionLocal", TestingSessionLocal)
    
    # Mock AdapterFactory
    with patch("app.tasks.parsing.AdapterFactory.create", return_value=mock_adapter), \
         patch("app.tasks.parsing.task_queue.mark_complete", new_callable=AsyncMock) as mock_mark_complete:
        
        parser = ContentParser()
        task_data = {"content_id": content_id, "action": "parse"}
        
        # 4. Execute
        await parser.process_parse_task(task_data, "test_task_id")
        
        # 5. Verify
        await db_session.refresh(content)
        assert content.status == ContentStatus.PARSE_SUCCESS
        assert content.title == "Mock Title"
        assert content.author_name == "Mock Author"
        mock_mark_complete.assert_called_once_with(content_id)

@pytest.mark.asyncio
async def test_process_parse_task_failure(db_session, monkeypatch):
    # 1. Setup test data
    content = Content(
        url="https://www.bilibili.com/video/invalid",
        platform=Platform.BILIBILI,
        status=ContentStatus.UNPROCESSED
    )
    db_session.add(content)
    await db_session.commit()
    await db_session.refresh(content)
    content_id = content.id

    # 2. Patch dependencies
    from tests.conftest import TestingSessionLocal
    monkeypatch.setattr("app.tasks.parsing.AsyncSessionLocal", TestingSessionLocal)
    
    with patch("app.tasks.parsing.AdapterFactory.create") as mock_factory, \
         patch("app.tasks.parsing.task_queue.mark_complete", new_callable=AsyncMock):
        
        mock_adapter = AsyncMock()
        mock_adapter.parse.side_effect = Exception("Parse error")
        mock_factory.return_value = mock_adapter
        
        parser = ContentParser()
        task_data = {"content_id": content_id, "action": "parse", "max_attempts": 1}
        
        # 3. Execute
        await parser.process_parse_task(task_data, "test_task_id")
        
        # 4. Verify
        await db_session.refresh(content)
        assert content.status == ContentStatus.PARSE_FAILED
        assert "Parse error" in content.last_error_detail["message"]


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def _make_parsed(**overrides):
    """Create a ParsedContent with sensible defaults, overridden as needed."""
    defaults = dict(
        platform="bilibili",
        content_type="video",
        content_id="BV_TEST",
        clean_url="https://www.bilibili.com/video/BV_TEST",
        title="Test Title",
        body="Test Body",
        author_name="Author",
        layout_type="gallery",
    )
    defaults.update(overrides)
    return ParsedContent(**defaults)


def _patch_common(monkeypatch, mock_adapter=None, parsed=None,
                  mark_complete=None, push_dead_letter=None, enqueue=None,
                  extract_cover_color=None, get_setting_value=None,
                  store_images=None, store_videos=None,
                  get_storage_backend=None, generate_summary=None,
                  auto_approve=None):
    """Apply common monkeypatches used by many tests.  Returns a dict of mocks."""
    from tests.conftest import TestingSessionLocal
    monkeypatch.setattr("app.tasks.parsing.AsyncSessionLocal", TestingSessionLocal)

    mocks = {}

    # Adapter
    if mock_adapter is None:
        mock_adapter = AsyncMock()
        if parsed is None:
            parsed = _make_parsed()
        mock_adapter.parse.return_value = parsed
    mocks["adapter"] = mock_adapter
    mocks["factory"] = patch("app.tasks.parsing.AdapterFactory.create", return_value=mock_adapter)

    # Queue helpers
    mocks["mark_complete"] = mark_complete or AsyncMock()
    monkeypatch.setattr("app.tasks.parsing.task_queue.mark_complete", mocks["mark_complete"])
    mocks["push_dead_letter"] = push_dead_letter or AsyncMock()
    monkeypatch.setattr("app.tasks.parsing.task_queue.push_dead_letter", mocks["push_dead_letter"])
    mocks["enqueue"] = enqueue or AsyncMock()
    monkeypatch.setattr("app.tasks.parsing.task_queue.enqueue", mocks["enqueue"])

    # extract_cover_color
    mocks["extract_cover_color"] = extract_cover_color or AsyncMock(return_value="#123456")
    monkeypatch.setattr("app.tasks.parsing.extract_cover_color", mocks["extract_cover_color"])

    # settings service
    if get_setting_value is None:
        get_setting_value = AsyncMock(return_value=False)
    mocks["get_setting_value"] = get_setting_value
    monkeypatch.setattr("app.services.settings_service.get_setting_value", mocks["get_setting_value"])

    # storage
    mocks["store_images"] = store_images or AsyncMock()
    monkeypatch.setattr("app.tasks.parsing.store_archive_images_as_webp", mocks["store_images"])
    mocks["store_videos"] = store_videos or AsyncMock()
    monkeypatch.setattr("app.tasks.parsing.store_archive_videos", mocks["store_videos"])

    mock_storage = get_storage_backend or MagicMock()
    mock_storage.ensure_bucket = AsyncMock()
    mocks["storage"] = mock_storage
    monkeypatch.setattr("app.tasks.parsing.get_storage_backend", lambda: mock_storage)

    # auto summary
    mocks["generate_summary"] = generate_summary or AsyncMock()

    # auto approve
    mocks["auto_approve"] = auto_approve or AsyncMock(return_value=False)

    return mocks


async def _make_content(db_session, **overrides):
    defaults = dict(
        url="https://www.bilibili.com/video/BV_TEST",
        platform=Platform.BILIBILI,
        status=ContentStatus.UNPROCESSED,
    )
    defaults.update(overrides)
    c = Content(**defaults)
    db_session.add(c)
    await db_session.commit()
    await db_session.refresh(c)
    return c


# ===================================================================
# process_parse_task edge cases
# ===================================================================

@pytest.mark.asyncio
async def test_process_parse_task_no_content_id(monkeypatch):
    """Missing content_id → early return, no crash."""
    mocks = _patch_common(monkeypatch)
    with mocks["factory"]:
        parser = ContentParser()
        await parser.process_parse_task({}, "tid")
    mocks["mark_complete"].assert_not_called()


@pytest.mark.asyncio
async def test_process_parse_task_content_not_found(db_session, monkeypatch):
    """content_id not in DB → mark_complete and return."""
    mocks = _patch_common(monkeypatch)
    with mocks["factory"]:
        parser = ContentParser()
        await parser.process_parse_task({"content_id": 999999}, "tid")
    # mark_complete is called inside the conditional return AND in `finally`
    assert mocks["mark_complete"].await_count >= 1
    mocks["mark_complete"].assert_any_await(999999)


@pytest.mark.asyncio
async def test_process_parse_task_already_parsed(db_session, monkeypatch):
    """PARSE_SUCCESS content → skip parse, call _handle_archived_media_fix, mark_complete."""
    content = await _make_content(db_session, status=ContentStatus.PARSE_SUCCESS)
    mocks = _patch_common(monkeypatch)
    with mocks["factory"]:
        parser = ContentParser()
        await parser.process_parse_task({"content_id": content.id}, "tid")
    # Adapter.parse should NOT have been called
    mocks["adapter"].parse.assert_not_called()
    # mark_complete is called in conditional return AND in finally block
    assert mocks["mark_complete"].await_count >= 1
    mocks["mark_complete"].assert_any_await(content.id)


# ===================================================================
# _execute_parse_with_retry
# ===================================================================

@pytest.mark.asyncio
async def test_execute_parse_retryable_error_then_success(db_session, monkeypatch):
    """First attempt retryable error, second succeeds."""
    from app.adapters.errors import RetryableAdapterError as RError
    content = await _make_content(db_session)

    parsed = _make_parsed()
    mock_adapter = AsyncMock()
    mock_adapter.parse.side_effect = [
        RError("transient"),
        parsed,
    ]
    monkeypatch.setattr("asyncio.sleep", AsyncMock())
    mocks = _patch_common(monkeypatch, mock_adapter=mock_adapter)

    with mocks["factory"]:
        parser = ContentParser()
        result_parsed, result_adapter = await parser._execute_parse_with_retry(content, 0, 3)
    assert result_parsed.title == "Test Title"
    assert mock_adapter.parse.call_count == 2


@pytest.mark.asyncio
async def test_execute_parse_non_retryable_error(db_session, monkeypatch):
    """Non-retryable AdapterError → raise immediately."""
    from app.adapters.errors import NonRetryableAdapterError
    content = await _make_content(db_session)

    mock_adapter = AsyncMock()
    mock_adapter.parse.side_effect = NonRetryableAdapterError("permanent")
    mocks = _patch_common(monkeypatch, mock_adapter=mock_adapter)

    with mocks["factory"]:
        parser = ContentParser()
        with pytest.raises(NonRetryableAdapterError):
            await parser._execute_parse_with_retry(content, 0, 3)
    assert mock_adapter.parse.call_count == 1


@pytest.mark.asyncio
async def test_execute_parse_max_retries_exhausted(db_session, monkeypatch):
    """All retries fail → RetryableAdapterError raised."""
    from app.adapters.errors import RetryableAdapterError as RError
    content = await _make_content(db_session)

    mock_adapter = AsyncMock()
    mock_adapter.parse.side_effect = RError("always fail")
    monkeypatch.setattr("asyncio.sleep", AsyncMock())
    mocks = _patch_common(monkeypatch, mock_adapter=mock_adapter)

    with mocks["factory"]:
        parser = ContentParser()
        with pytest.raises(RError, match="最大次数"):
            await parser._execute_parse_with_retry(content, 0, 2)
    assert mock_adapter.parse.call_count == 2


# ===================================================================
# _update_content
# ===================================================================

@pytest.mark.asyncio
async def test_update_content_body_truncation(db_session, monkeypatch):
    """Body > 200K chars gets truncated."""
    from tests.conftest import TestingSessionLocal
    content = await _make_content(db_session)
    big_body = "x" * 300_000
    parsed = _make_parsed(body=big_body)
    mock_adapter = AsyncMock()
    mock_adapter.map_stats_to_content = MagicMock()
    mocks = _patch_common(monkeypatch, mock_adapter=mock_adapter)

    async with TestingSessionLocal() as session:
        result = await session.execute(select(Content).where(Content.id == content.id))
        content_in_session = result.scalar_one()
        with mocks["factory"]:
            parser = ContentParser()
            await parser._update_content(session, content_in_session, parsed, mock_adapter)
        assert len(content_in_session.body) == 200_000


@pytest.mark.asyncio
async def test_update_content_archive_markdown_fallback(db_session, monkeypatch):
    """Uses archive markdown when _body_is_markdown is False."""
    from tests.conftest import TestingSessionLocal
    content = await _make_content(db_session)
    parsed = _make_parsed(body="original body")
    parsed._body_is_markdown = False
    parsed.archive_metadata = {"archive": {"markdown": "# Archive MD"}}
    mock_adapter = AsyncMock()
    mock_adapter.map_stats_to_content = MagicMock()
    mocks = _patch_common(monkeypatch, mock_adapter=mock_adapter)

    async with TestingSessionLocal() as session:
        result = await session.execute(select(Content).where(Content.id == content.id))
        content_in_session = result.scalar_one()
        with mocks["factory"]:
            parser = ContentParser()
            await parser._update_content(session, content_in_session, parsed, mock_adapter)
        assert content_in_session.body == "# Archive MD"


@pytest.mark.asyncio
async def test_update_content_auto_summary_enabled(db_session, monkeypatch):
    """Calls generate_summary_for_content when enable_auto_summary is True."""
    from tests.conftest import TestingSessionLocal
    content = await _make_content(db_session)
    parsed = _make_parsed()
    mock_adapter = AsyncMock()
    mock_adapter.map_stats_to_content = MagicMock()

    async def _setting_side_effect(key, default=None):
        if key == "enable_auto_summary":
            return True
        return False

    mock_gen = AsyncMock()
    mocks = _patch_common(monkeypatch, mock_adapter=mock_adapter,
                          get_setting_value=AsyncMock(side_effect=_setting_side_effect),
                          generate_summary=mock_gen)

    async with TestingSessionLocal() as session:
        result = await session.execute(select(Content).where(Content.id == content.id))
        content_in_session = result.scalar_one()
        with mocks["factory"], \
             patch("app.services.content_summary_service.generate_summary_for_content", mock_gen):
            parser = ContentParser()
            await parser._update_content(session, content_in_session, parsed, mock_adapter)
    mock_gen.assert_awaited_once()


@pytest.mark.asyncio
async def test_update_content_auto_summary_disabled(db_session, monkeypatch):
    """Skips summary generation when enable_auto_summary is False."""
    from tests.conftest import TestingSessionLocal
    content = await _make_content(db_session)
    parsed = _make_parsed()
    mock_adapter = AsyncMock()
    mock_adapter.map_stats_to_content = MagicMock()

    mock_gen = AsyncMock()
    mocks = _patch_common(monkeypatch, mock_adapter=mock_adapter,
                          get_setting_value=AsyncMock(return_value=False),
                          generate_summary=mock_gen)

    async with TestingSessionLocal() as session:
        result = await session.execute(select(Content).where(Content.id == content.id))
        content_in_session = result.scalar_one()
        with mocks["factory"], \
             patch("app.services.content_summary_service.generate_summary_for_content", mock_gen):
            parser = ContentParser()
            await parser._update_content(session, content_in_session, parsed, mock_adapter)
    mock_gen.assert_not_awaited()


# ===================================================================
# _handle_parse_error
# ===================================================================

@pytest.mark.asyncio
async def test_handle_parse_error_auth_required(db_session, monkeypatch):
    """AdapterError with auth_required → dead letter with reason auth_required."""
    from app.adapters.errors import AuthRequiredAdapterError
    content = await _make_content(db_session)
    mocks = _patch_common(monkeypatch)
    task_data = {"content_id": content.id}
    error = AuthRequiredAdapterError("need login")

    with mocks["factory"]:
        parser = ContentParser()
        await parser._handle_parse_error(db_session, content, task_data, error, 0, 3)

    assert content.status == ContentStatus.PARSE_FAILED
    mocks["push_dead_letter"].assert_awaited_once()
    call_args = mocks["push_dead_letter"].call_args
    assert call_args[1]["reason"] == "auth_required" or call_args[0][1] == "auth_required"


@pytest.mark.asyncio
async def test_handle_parse_error_non_retryable(db_session, monkeypatch):
    """Non-retryable AdapterError → dead letter with reason non_retryable."""
    from app.adapters.errors import NonRetryableAdapterError
    content = await _make_content(db_session)
    mocks = _patch_common(monkeypatch)
    task_data = {"content_id": content.id}
    error = NonRetryableAdapterError("permanent error")

    with mocks["factory"]:
        parser = ContentParser()
        await parser._handle_parse_error(db_session, content, task_data, error, 0, 3)

    assert content.status == ContentStatus.PARSE_FAILED
    mocks["push_dead_letter"].assert_awaited_once()
    call_args = mocks["push_dead_letter"].call_args
    assert call_args[1].get("reason") == "non_retryable" or call_args[0][1] == "non_retryable"


@pytest.mark.asyncio
async def test_handle_parse_error_max_attempts(db_session, monkeypatch):
    """attempt >= max_attempts → dead letter with reason max_attempts_reached."""
    content = await _make_content(db_session)
    mocks = _patch_common(monkeypatch)
    task_data = {"content_id": content.id}
    error = Exception("generic error")

    with mocks["factory"]:
        parser = ContentParser()
        await parser._handle_parse_error(db_session, content, task_data, error, 2, 3)

    mocks["push_dead_letter"].assert_awaited_once()
    call_args = mocks["push_dead_letter"].call_args
    assert call_args[1].get("reason") == "max_attempts_reached" or call_args[0][1] == "max_attempts_reached"


@pytest.mark.asyncio
async def test_handle_parse_error_normal(db_session, monkeypatch):
    """Normal failure (retryable, under max) → no dead letter."""
    content = await _make_content(db_session)
    mocks = _patch_common(monkeypatch)
    task_data = {"content_id": content.id}
    error = Exception("transient")

    with mocks["factory"]:
        parser = ContentParser()
        await parser._handle_parse_error(db_session, content, task_data, error, 0, 3)

    assert content.status == ContentStatus.PARSE_FAILED
    mocks["push_dead_letter"].assert_not_awaited()


# ===================================================================
# _check_auto_approval
# ===================================================================

@pytest.mark.asyncio
async def test_check_auto_approval_success(db_session, monkeypatch):
    """auto_approve_if_eligible is called."""
    content = await _make_content(db_session)
    mock_engine = AsyncMock()
    mock_engine.auto_approve_if_eligible = AsyncMock(return_value=True)

    with patch("app.services.distribution.DistributionEngine", return_value=mock_engine):
        parser = ContentParser()
        await parser._check_auto_approval(db_session, content)
    mock_engine.auto_approve_if_eligible.assert_awaited_once_with(content)


@pytest.mark.asyncio
async def test_check_auto_approval_exception(db_session, monkeypatch):
    """Exception in auto-approve is caught silently."""
    content = await _make_content(db_session)

    with patch("app.services.distribution.DistributionEngine", side_effect=RuntimeError("boom")):
        parser = ContentParser()
        # Should not raise
        await parser._check_auto_approval(db_session, content)


# ===================================================================
# Helper methods
# ===================================================================

def test_extract_archive_blob_from_archive():
    parser = ContentParser()
    meta = {"archive": {"markdown": "# Hello"}}
    assert parser._extract_archive_blob(meta) == {"markdown": "# Hello"}


def test_extract_archive_blob_from_processed():
    parser = ContentParser()
    meta = {"processed_archive": {"html": "<p>hi</p>"}}
    assert parser._extract_archive_blob(meta) == {"html": "<p>hi</p>"}


def test_extract_archive_blob_none():
    parser = ContentParser()
    assert parser._extract_archive_blob(None) == {}
    assert parser._extract_archive_blob("string") == {}
    assert parser._extract_archive_blob({"other_key": 1}) == {}


def test_truncate_archive_metadata_under_limit():
    parser = ContentParser()
    small = {"key": "value"}
    result = parser._truncate_archive_metadata(small, 1)
    assert result == small
    assert "_truncated" not in result


def test_truncate_archive_metadata_over_limit():
    parser = ContentParser()
    # Create metadata that exceeds 512KB
    big_value = "x" * 600_000
    meta = {"archive": {"markdown": big_value, "html": big_value, "images": [{"data": "base64data"}]}}
    result = parser._truncate_archive_metadata(meta, 1)
    assert result.get("_truncated") is True
    # markdown/html should be removed from archive
    archive = result.get("archive", {})
    assert "markdown" not in archive
    assert "html" not in archive


def test_get_platform_cookies_bilibili(monkeypatch):
    from pydantic import SecretStr
    monkeypatch.setattr("app.core.config.settings.bilibili_sessdata", SecretStr("sess123"))
    monkeypatch.setattr("app.core.config.settings.bilibili_bili_jct", SecretStr("jct456"))
    monkeypatch.setattr("app.core.config.settings.bilibili_buvid3", SecretStr("buv789"))
    parser = ContentParser()
    cookies = parser._get_platform_cookies(Platform.BILIBILI)
    assert cookies == {"SESSDATA": "sess123", "bili_jct": "jct456", "buvid3": "buv789"}


def test_get_platform_cookies_other():
    parser = ContentParser()
    assert parser._get_platform_cookies(Platform.WEIBO) == {}


# ===================================================================
# _maybe_process_private_archive_media
# ===================================================================

@pytest.mark.asyncio
async def test_maybe_process_no_archive(monkeypatch):
    """No archive_metadata → early return, no storage calls."""
    mocks = _patch_common(monkeypatch)
    parsed = _make_parsed()
    parsed.archive_metadata = None

    with mocks["factory"]:
        parser = ContentParser()
        await parser._maybe_process_private_archive_media(parsed)
    mocks["store_images"].assert_not_awaited()
    mocks["store_videos"].assert_not_awaited()


@pytest.mark.asyncio
async def test_maybe_process_images_and_cover(monkeypatch):
    """Stores images, updates cover_url and media_urls from stored_images."""
    archive_data = {
        "images": [{"url": "https://example.com/img1.jpg"}],
        "stored_images": [
            {"url": "https://stored.com/img1.webp", "key": "abc/img1.webp",
             "orig_url": "https://example.com/img1.jpg", "type": "cover"},
        ],
    }
    parsed = _make_parsed()
    parsed.archive_metadata = {"archive": archive_data}
    parsed.cover_url = "https://example.com/img1.jpg"
    parsed.media_urls = []

    async def _setting(key, default=None):
        if key == "archive_image_webp_quality":
            return 80
        if key == "archive_image_max_count":
            return None
        return default

    mocks = _patch_common(monkeypatch,
                          get_setting_value=AsyncMock(side_effect=_setting))

    with mocks["factory"]:
        parser = ContentParser()
        await parser._maybe_process_private_archive_media(parsed)

    mocks["store_images"].assert_awaited_once()
    # cover_url should be updated to local://
    assert parsed.cover_url == "local://abc/img1.webp"
    assert "local://abc/img1.webp" in parsed.media_urls


@pytest.mark.asyncio
async def test_maybe_process_videos(monkeypatch):
    """Stores videos, appends to media_urls."""
    archive_data = {
        "videos": [{"url": "https://example.com/vid.mp4"}],
        "stored_videos": [
            {"key": "abc/vid.mp4"},
        ],
    }
    parsed = _make_parsed()
    parsed.archive_metadata = {"archive": archive_data}
    parsed.media_urls = []

    async def _setting(key, default=None):
        if key == "archive_image_webp_quality":
            return 80
        if key == "archive_image_max_count":
            return None
        return default

    mocks = _patch_common(monkeypatch,
                          get_setting_value=AsyncMock(side_effect=_setting))

    with mocks["factory"]:
        parser = ContentParser()
        await parser._maybe_process_private_archive_media(parsed)

    mocks["store_videos"].assert_awaited_once()
    assert "local://abc/vid.mp4" in parsed.media_urls


# ===================================================================
# _handle_archived_media_fix
# ===================================================================

@pytest.mark.asyncio
async def test_handle_archived_media_fix_no_processing(db_session, monkeypatch):
    """Setting disabled → skip processing."""
    content = await _make_content(db_session,
                                  archive_metadata={"archive": {"images": [{"url": "x"}]}})
    mocks = _patch_common(monkeypatch,
                          get_setting_value=AsyncMock(return_value=False))

    with mocks["factory"]:
        parser = ContentParser()
        await parser._handle_archived_media_fix(db_session, content)
    mocks["store_images"].assert_not_awaited()


@pytest.mark.asyncio
async def test_handle_archived_media_fix_needs_media(db_session, monkeypatch):
    """Unstored images → process media."""
    content = await _make_content(
        db_session,
        archive_metadata={"archive": {"images": [{"url": "https://img.com/1.jpg"}]}},
    )

    async def _setting(key, default=None):
        if key == "enable_archive_media_processing":
            return True
        if key == "archive_image_webp_quality":
            return 80
        if key == "archive_image_max_count":
            return None
        return default

    mocks = _patch_common(monkeypatch,
                          get_setting_value=AsyncMock(side_effect=_setting))

    with mocks["factory"]:
        parser = ContentParser()
        await parser._handle_archived_media_fix(db_session, content)
    mocks["store_images"].assert_awaited_once()


# ===================================================================
# retry_parse
# ===================================================================

@pytest.mark.asyncio
async def test_retry_parse_not_found(db_session, monkeypatch):
    """Content not found → return False."""
    mocks = _patch_common(monkeypatch)
    with mocks["factory"]:
        parser = ContentParser()
        result = await parser.retry_parse(999999)
    assert result is False


@pytest.mark.asyncio
async def test_retry_parse_already_parsed(db_session, monkeypatch):
    """Already PARSE_SUCCESS, not force → return True."""
    content = await _make_content(db_session, status=ContentStatus.PARSE_SUCCESS)
    mocks = _patch_common(monkeypatch)
    with mocks["factory"]:
        parser = ContentParser()
        result = await parser.retry_parse(content.id, force=False)
    assert result is True
    mocks["adapter"].parse.assert_not_called()


@pytest.mark.asyncio
async def test_retry_parse_success(db_session, monkeypatch):
    """Retry succeeds → return True."""
    content = await _make_content(db_session, status=ContentStatus.PARSE_FAILED)
    parsed = _make_parsed()
    mock_adapter = AsyncMock()
    mock_adapter.parse.return_value = parsed
    mock_adapter.map_stats_to_content = MagicMock()
    mocks = _patch_common(monkeypatch, mock_adapter=mock_adapter, parsed=parsed)

    with mocks["factory"]:
        parser = ContentParser()
        result = await parser.retry_parse(content.id, force=True)
    assert result is True


@pytest.mark.asyncio
async def test_retry_parse_exhausted(db_session, monkeypatch):
    """All retries fail → return False."""
    content = await _make_content(db_session, status=ContentStatus.PARSE_FAILED)
    mock_adapter = AsyncMock()
    mock_adapter.parse.side_effect = Exception("always fails")
    mocks = _patch_common(monkeypatch, mock_adapter=mock_adapter)
    monkeypatch.setattr("asyncio.sleep", AsyncMock())

    with mocks["factory"]:
        parser = ContentParser()
        result = await parser.retry_parse(content.id, max_retries=2, delay_seconds=0.01, force=True)
    assert result is False
