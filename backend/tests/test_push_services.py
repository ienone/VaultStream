"""
Tests for push services: TelegramPushService, NapcatPushService, and factory.
"""
import pytest
from unittest.mock import patch, MagicMock

from app.push.telegram import TelegramPushService, MAX_CAPTION_LENGTH, MAX_MESSAGE_LENGTH
from app.push.napcat import (
    NapcatPushService,
    _build_text_segment,
    _build_image_segment,
    _build_video_segment,
    _build_record_segment,
)
from app.push import factory
from app.push.factory import get_push_service, _push_service_cache


# ─── Telegram: _get_media_mode ───────────────────────────────────────────────

class TestTelegramGetMediaMode:
    def test_none_config(self):
        assert TelegramPushService._get_media_mode(None) == "auto"

    def test_empty_config(self):
        assert TelegramPushService._get_media_mode({}) == "auto"

    def test_flat_media_mode(self):
        assert TelegramPushService._get_media_mode({"media_mode": "none"}) == "none"

    def test_nested_structure(self):
        config = {"structure": {"media_mode": "cover"}}
        assert TelegramPushService._get_media_mode(config) == "cover"

    def test_nested_structure_missing_media_mode(self):
        config = {"structure": {"other_key": True}}
        assert TelegramPushService._get_media_mode(config) == "auto"


# ─── Telegram: _build_payload ────────────────────────────────────────────────

class TestTelegramBuildPayload:
    def setup_method(self):
        self.service = TelegramPushService()

    @patch("app.push.telegram.extract_media_urls", return_value=[])
    @patch("app.push.telegram.format_content_for_tg", return_value="plain text")
    def test_no_render_config_uses_format_for_tg(self, mock_fmt, mock_extract):
        content = {"title": "t"}
        text, media = self.service._build_payload(content)
        mock_fmt.assert_called_once_with(content)
        assert text == "plain text"
        assert media == []

    @patch("app.push.telegram.extract_media_urls", return_value=[])
    @patch("app.push.telegram.format_content_with_render_config", return_value="rich text")
    def test_with_render_config_uses_render_config_formatter(self, mock_fmt, mock_extract):
        content = {"title": "t", "render_config": {"structure": {}}}
        text, media = self.service._build_payload(content)
        mock_fmt.assert_called_once()
        assert text == "rich text"

    @patch("app.push.telegram.extract_media_urls", return_value=[{"type": "photo", "url": "u"}])
    @patch("app.push.telegram.format_content_for_tg", return_value="x" * 2000)
    def test_truncate_to_caption_length_when_media(self, mock_fmt, mock_extract):
        content = {"title": "t"}
        text, media = self.service._build_payload(content)
        assert len(text) == MAX_CAPTION_LENGTH
        assert text.endswith("...")

    @patch("app.push.telegram.extract_media_urls", return_value=[])
    @patch("app.push.telegram.format_content_for_tg", return_value="x" * 5000)
    def test_truncate_to_message_length_when_no_media(self, mock_fmt, mock_extract):
        content = {"title": "t"}
        text, media = self.service._build_payload(content)
        assert len(text) == MAX_MESSAGE_LENGTH
        assert text.endswith("...")

    @patch("app.push.telegram.extract_media_urls", return_value=[{"type": "photo", "url": "u"}])
    @patch("app.push.telegram.format_content_for_tg", return_value="short")
    def test_no_truncation_when_short(self, mock_fmt, mock_extract):
        content = {"title": "t"}
        text, media = self.service._build_payload(content)
        assert text == "short"

    @patch("app.push.telegram.extract_media_urls", return_value=[
        {"type": "photo", "url": "a"},
        {"type": "video", "url": "b"},
    ])
    @patch("app.push.telegram.format_content_for_tg", return_value="txt")
    def test_media_mode_none_clears_media(self, mock_fmt, mock_extract):
        content = {"title": "t", "render_config": {"media_mode": "none"}}
        text, media = self.service._build_payload(content)
        assert media == []

    @patch("app.push.telegram.extract_media_urls", return_value=[
        {"type": "photo", "url": "a"},
        {"type": "photo", "url": "b"},
        {"type": "video", "url": "c"},
    ])
    @patch("app.push.telegram.format_content_with_render_config", return_value="txt")
    def test_media_mode_cover_keeps_first_photo(self, mock_fmt, mock_extract):
        content = {"title": "t", "render_config": {"media_mode": "cover"}}
        text, media = self.service._build_payload(content)
        assert len(media) == 1
        assert media[0]["url"] == "a"
        assert media[0]["type"] == "photo"

    @patch("app.push.telegram.extract_media_urls", return_value=[
        {"type": "video", "url": "v"},
    ])
    @patch("app.push.telegram.format_content_with_render_config", return_value="txt")
    def test_media_mode_cover_falls_back_to_first_item_if_no_photo(self, mock_fmt, mock_extract):
        content = {"title": "t", "render_config": {"media_mode": "cover"}}
        text, media = self.service._build_payload(content)
        assert len(media) == 1
        assert media[0]["url"] == "v"

    @patch("app.push.telegram.extract_media_urls", return_value=[])
    @patch("app.push.telegram.format_content_for_tg", return_value="txt")
    def test_uses_content_media_items_when_present(self, mock_fmt, mock_extract):
        content = {
            "title": "t",
            "media_items": [{"type": "photo", "url": "inline"}],
        }
        text, media = self.service._build_payload(content)
        assert media == [{"type": "photo", "url": "inline"}]
        mock_extract.assert_not_called()


# ─── Napcat: segment builders ────────────────────────────────────────────────

class TestNapcatSegmentBuilders:
    def test_build_text_segment(self):
        result = _build_text_segment("hello")
        assert result == {"type": "text", "data": {"text": "hello"}}

    def test_build_image_segment(self):
        result = _build_image_segment("http://img.png")
        assert result == {"type": "image", "data": {"file": "http://img.png"}}

    def test_build_video_segment(self):
        result = _build_video_segment("http://vid.mp4")
        assert result == {"type": "video", "data": {"file": "http://vid.mp4"}}

    def test_build_record_segment(self):
        result = _build_record_segment("http://audio.mp3")
        assert result == {"type": "record", "data": {"file": "http://audio.mp3"}}


# ─── Napcat: _parse_target ───────────────────────────────────────────────────

class TestNapcatParseTarget:
    def setup_method(self):
        self.service = NapcatPushService()

    def test_group_prefix(self):
        tid, is_private = self.service._parse_target("group:123")
        assert tid == "123"
        assert is_private is False

    def test_private_prefix(self):
        tid, is_private = self.service._parse_target("private:456")
        assert tid == "456"
        assert is_private is True

    def test_bare_number_defaults_to_group(self):
        tid, is_private = self.service._parse_target("789")
        assert tid == "789"
        assert is_private is False

    def test_integer_input(self):
        tid, is_private = self.service._parse_target(100)
        assert tid == "100"
        assert is_private is False


# ─── Napcat: _get_media_mode ────────────────────────────────────────────────

class TestNapcatGetMediaMode:
    def setup_method(self):
        self.service = NapcatPushService()

    def test_no_render_config(self):
        assert self.service._get_media_mode({}) == "auto"

    def test_flat_media_mode(self):
        content = {"render_config": {"media_mode": "none"}}
        assert self.service._get_media_mode(content) == "none"

    def test_nested_structure(self):
        content = {"render_config": {"structure": {"media_mode": "cover"}}}
        assert self.service._get_media_mode(content) == "cover"

    def test_none_render_config(self):
        content = {"render_config": None}
        assert self.service._get_media_mode(content) == "auto"


# ─── Napcat: _extract_media ─────────────────────────────────────────────────

class TestNapcatExtractMedia:
    def setup_method(self):
        self.service = NapcatPushService()

    @patch("app.push.napcat.extract_media_urls", return_value=[
        {"type": "photo", "url": "a"},
        {"type": "video", "url": "b"},
    ])
    def test_auto_returns_all(self, mock_extract):
        content = {"archive_metadata": {"k": "v"}}
        result = self.service._extract_media(content)
        assert len(result) == 2

    @patch("app.push.napcat.extract_media_urls")
    def test_none_returns_empty(self, mock_extract):
        content = {"render_config": {"media_mode": "none"}}
        result = self.service._extract_media(content)
        assert result == []
        mock_extract.assert_not_called()

    @patch("app.push.napcat.extract_media_urls", return_value=[
        {"type": "photo", "url": "a"},
        {"type": "photo", "url": "b"},
        {"type": "video", "url": "c"},
    ])
    def test_cover_keeps_first_photo(self, mock_extract):
        content = {"render_config": {"media_mode": "cover"}, "archive_metadata": {}}
        result = self.service._extract_media(content)
        assert len(result) == 1
        assert result[0]["url"] == "a"

    @patch("app.push.napcat.extract_media_urls", return_value=[
        {"type": "video", "url": "v"},
    ])
    def test_cover_falls_back_to_first_if_no_photo(self, mock_extract):
        content = {"render_config": {"media_mode": "cover"}, "archive_metadata": {}}
        result = self.service._extract_media(content)
        assert len(result) == 1
        assert result[0]["url"] == "v"

    def test_uses_content_media_items_when_present(self):
        content = {
            "media_items": [{"type": "photo", "url": "inline"}],
        }
        result = self.service._extract_media(content)
        assert result == [{"type": "photo", "url": "inline"}]


# ─── Napcat: _build_message_segments ─────────────────────────────────────────

class TestNapcatBuildMessageSegments:
    def setup_method(self):
        self.service = NapcatPushService()

    @patch("app.push.napcat._resolve_media_url", return_value="http://resolved.png")
    @patch("app.push.napcat.extract_media_urls", return_value=[
        {"type": "photo", "url": "u1"},
    ])
    @patch("app.push.napcat.strip_markdown", return_value="clean text")
    @patch("app.push.napcat.format_content_with_render_config", return_value="raw text")
    def test_segments_with_photo(self, mock_fmt, mock_strip, mock_extract, mock_resolve):
        content = {"title": "t", "archive_metadata": {}}
        segments = self.service._build_message_segments(content)
        assert segments[0] == {"type": "text", "data": {"text": "clean text"}}
        assert segments[1] == {"type": "image", "data": {"file": "http://resolved.png"}}

    @patch("app.push.napcat._resolve_media_url", return_value="http://resolved.mp4")
    @patch("app.push.napcat.extract_media_urls", return_value=[
        {"type": "video", "url": "v1"},
    ])
    @patch("app.push.napcat.strip_markdown", return_value="clean text")
    @patch("app.push.napcat.format_content_with_render_config", return_value="raw text")
    def test_segments_with_video(self, mock_fmt, mock_strip, mock_extract, mock_resolve):
        content = {"title": "t", "archive_metadata": {}}
        segments = self.service._build_message_segments(content)
        assert segments[1] == {"type": "video", "data": {"file": "http://resolved.mp4"}}

    @patch("app.push.napcat._resolve_media_url", return_value=None)
    @patch("app.push.napcat.extract_media_urls", return_value=[
        {"type": "photo", "url": "u1"},
    ])
    @patch("app.push.napcat.strip_markdown", return_value="text")
    @patch("app.push.napcat.format_content_with_render_config", return_value="text")
    def test_skips_media_with_no_resolved_url(self, mock_fmt, mock_strip, mock_extract, mock_resolve):
        content = {"title": "t", "archive_metadata": {}}
        segments = self.service._build_message_segments(content)
        assert len(segments) == 1  # text only

    @patch("app.push.napcat.extract_media_urls", return_value=[])
    @patch("app.push.napcat.strip_markdown", return_value="")
    @patch("app.push.napcat.format_content_with_render_config", return_value="")
    def test_empty_text_becomes_placeholder(self, mock_fmt, mock_strip, mock_extract):
        content = {"title": "t"}
        segments = self.service._build_message_segments(content)
        assert segments[0]["data"]["text"] == "(no content)"


# ─── Factory ─────────────────────────────────────────────────────────────────

class TestPushFactory:
    def setup_method(self):
        _push_service_cache.clear()

    def test_get_telegram_service(self):
        service = get_push_service("telegram")
        assert isinstance(service, TelegramPushService)

    def test_get_qq_service(self):
        service = get_push_service("qq")
        assert isinstance(service, NapcatPushService)

    def test_unknown_platform_raises(self):
        with pytest.raises(ValueError, match="Unsupported push platform"):
            get_push_service("unknown")

    def test_cache_returns_same_instance(self):
        s1 = get_push_service("telegram")
        s2 = get_push_service("telegram")
        assert s1 is s2

    def test_case_insensitive(self):
        service = get_push_service("Telegram")
        assert isinstance(service, TelegramPushService)
