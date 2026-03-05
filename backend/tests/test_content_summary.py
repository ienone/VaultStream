"""Tests for app.services.content_summary_service"""

import pytest
from unittest.mock import AsyncMock, MagicMock, patch

from app.services.content_summary_service import (
    strip_markdown,
    generate_summary_llm,
    generate_summary_for_content,
)


# ────────────────────────────────────────────
# strip_markdown
# ────────────────────────────────────────────

class TestStripMarkdown:
    def test_empty_string(self):
        assert strip_markdown("") == ""

    def test_none_returns_empty(self):
        assert strip_markdown(None) == ""

    def test_removes_images(self):
        text = "before ![alt](http://img.png) after"
        assert strip_markdown(text) == "before  after"

    def test_removes_links_keeps_text(self):
        text = "click [here](http://example.com) now"
        assert strip_markdown(text) == "click here now"

    def test_removes_headers(self):
        text = "# Title\n## Subtitle\nBody"
        result = strip_markdown(text)
        assert "Title" in result
        assert "#" not in result

    def test_removes_bold_italic(self):
        text = "this is **bold** and *italic* and ~~strike~~"
        result = strip_markdown(text)
        assert "**" not in result
        assert "*" not in result
        assert "~~" not in result
        assert "bold" in result

    def test_removes_blockquotes(self):
        text = "> quoted line\nnormal line"
        result = strip_markdown(text)
        assert result.startswith("quoted")

    def test_removes_horizontal_rules(self):
        text = "above\n---\nbelow"
        result = strip_markdown(text)
        assert "---" not in result
        assert "above" in result
        assert "below" in result

    def test_collapses_multiple_newlines(self):
        text = "a\n\n\n\nb"
        result = strip_markdown(text)
        assert "\n\n" not in result

    def test_plain_text_unchanged(self):
        text = "hello world"
        assert strip_markdown(text) == "hello world"

    def test_combined_markdown(self):
        text = "# Header\n\n![img](url)\n\n> quote\n\n**bold** [link](http://x)\n\n---\n\nend"
        result = strip_markdown(text)
        assert "#" not in result
        assert "![" not in result
        assert "**" not in result
        assert "---" not in result
        assert "end" in result


# ────────────────────────────────────────────
# generate_summary_llm
# ────────────────────────────────────────────

@pytest.mark.asyncio
class TestGenerateSummaryLlm:
    async def test_text_only_no_images(self):
        """Text LLM called, no vision call when images=None"""
        mock_response = MagicMock()
        mock_response.content = "这是摘要"

        mock_text_llm = AsyncMock()
        mock_text_llm.ainvoke.return_value = mock_response

        with patch("app.services.content_summary_service.LLMFactory") as mock_factory:
            mock_factory.get_text_llm = AsyncMock(return_value=mock_text_llm)
            mock_factory.get_vision_llm = AsyncMock(return_value=None)

            result = await generate_summary_llm("一些正文内容", title="标题")

        assert result == "这是摘要"
        mock_text_llm.ainvoke.assert_awaited_once()
        # Verify prompt contains title
        prompt = mock_text_llm.ainvoke.call_args[0][0][0].content
        assert "标题" in prompt

    async def test_with_images_calls_vision_then_text(self):
        """Vision LLM used for image description, then Text LLM for summary"""
        vision_response = MagicMock()
        vision_response.content = "图片中有一只猫"
        text_response = MagicMock()
        text_response.content = "最终摘要"

        mock_vision_llm = AsyncMock()
        mock_vision_llm.ainvoke.return_value = vision_response
        mock_text_llm = AsyncMock()
        mock_text_llm.ainvoke.return_value = text_response

        with patch("app.services.content_summary_service.LLMFactory") as mock_factory:
            mock_factory.get_vision_llm = AsyncMock(return_value=mock_vision_llm)
            mock_factory.get_text_llm = AsyncMock(return_value=mock_text_llm)

            result = await generate_summary_llm(
                "正文", images=["http://img1.png", "http://img2.png"]
            )

        assert result == "最终摘要"
        mock_vision_llm.ainvoke.assert_awaited_once()
        mock_text_llm.ainvoke.assert_awaited_once()
        # Text prompt should include visual description
        text_prompt = mock_text_llm.ainvoke.call_args[0][0][0].content
        assert "视觉信息描述" in text_prompt

    async def test_fallback_to_vision_llm_when_text_unavailable(self):
        """When text LLM is None, falls back to vision LLM for summary"""
        mock_response = MagicMock()
        mock_response.content = "视觉模型摘要"

        mock_vision_llm = AsyncMock()
        mock_vision_llm.ainvoke.return_value = mock_response

        with patch("app.services.content_summary_service.LLMFactory") as mock_factory:
            mock_factory.get_text_llm = AsyncMock(return_value=None)
            mock_factory.get_vision_llm = AsyncMock(return_value=mock_vision_llm)

            result = await generate_summary_llm("正文内容")

        assert result == "视觉模型摘要"

    async def test_raises_when_no_llm_available(self):
        """Raises RuntimeError when neither text nor vision LLM configured"""
        with patch("app.services.content_summary_service.LLMFactory") as mock_factory:
            mock_factory.get_text_llm = AsyncMock(return_value=None)
            mock_factory.get_vision_llm = AsyncMock(return_value=None)

            with pytest.raises(RuntimeError, match="LLM 未配置"):
                await generate_summary_llm("正文内容")

    async def test_truncates_long_summary(self):
        """Summary exceeding max_summary_len is truncated with ellipsis"""
        long_text = "摘" * 200
        mock_response = MagicMock()
        mock_response.content = long_text

        mock_llm = AsyncMock()
        mock_llm.ainvoke.return_value = mock_response

        with patch("app.services.content_summary_service.LLMFactory") as mock_factory:
            mock_factory.get_text_llm = AsyncMock(return_value=mock_llm)

            result = await generate_summary_llm("正文", max_summary_len=50)

        assert len(result) == 51  # 50 chars + "…"
        assert result.endswith("…")

    async def test_llm_invocation_error_propagates(self):
        """LLM invocation errors are re-raised"""
        mock_llm = AsyncMock()
        mock_llm.ainvoke.side_effect = Exception("API Error")

        with patch("app.services.content_summary_service.LLMFactory") as mock_factory:
            mock_factory.get_text_llm = AsyncMock(return_value=mock_llm)

            with pytest.raises(Exception, match="API Error"):
                await generate_summary_llm("正文")


# ────────────────────────────────────────────
# generate_summary_for_content
# ────────────────────────────────────────────

def _make_content(**overrides):
    """Helper to build a mock Content object with sensible defaults."""
    content = MagicMock()
    content.id = overrides.get("id", 1)
    content.title = overrides.get("title", "测试标题")
    content.body = overrides.get("body", "这是一段足够长的正文" * 30)
    content.summary = overrides.get("summary", None)
    content.media_urls = overrides.get("media_urls", None)
    content.archive_metadata = overrides.get("archive_metadata", None)
    content.status = MagicMock(value="published")
    content.platform = overrides.get("platform", MagicMock(value="twitter"))
    content.review_status = overrides.get("review_status", "approved")
    return content


@pytest.mark.asyncio
class TestGenerateSummaryForContent:
    async def test_content_not_found_raises(self):
        session = AsyncMock()
        session.get.return_value = None

        with pytest.raises(ValueError, match="内容不存在"):
            await generate_summary_for_content(session, 999)

    async def test_skips_when_summary_exists_and_not_force(self):
        content = _make_content(summary="已有摘要")
        session = AsyncMock()
        session.get.return_value = content

        result = await generate_summary_for_content(session, 1)

        assert result.summary == "已有摘要"
        session.commit.assert_not_awaited()

    async def test_force_regenerates_existing_summary(self):
        content = _make_content(summary="旧摘要")
        session = AsyncMock()
        session.get.return_value = content

        with patch(
            "app.services.content_summary_service.generate_summary_llm",
            new_callable=AsyncMock,
            return_value="新摘要",
        ), patch("app.core.events.event_bus") as mock_bus:
            mock_bus.publish = AsyncMock()
            result = await generate_summary_for_content(session, 1, force=True)

        assert result.summary == "新摘要"
        session.commit.assert_awaited()

    async def test_no_body_no_media_uses_title(self):
        content = _make_content(body=None, media_urls=None)
        session = AsyncMock()
        session.get.return_value = content

        result = await generate_summary_for_content(session, 1)

        assert result.summary == content.title
        session.commit.assert_awaited()

    async def test_empty_body_no_media_uses_title(self):
        content = _make_content(body="", media_urls=[])
        session = AsyncMock()
        session.get.return_value = content

        result = await generate_summary_for_content(session, 1)

        assert result.summary == content.title
        session.commit.assert_awaited()

    async def test_short_text_no_images_skips_generation(self):
        content = _make_content(body="短文本", media_urls=None)
        session = AsyncMock()
        session.get.return_value = content

        result = await generate_summary_for_content(session, 1)

        assert result.summary is None
        session.commit.assert_awaited()

    async def test_successful_generation(self):
        content = _make_content()
        session = AsyncMock()
        session.get.return_value = content

        with patch(
            "app.services.content_summary_service.generate_summary_llm",
            new_callable=AsyncMock,
            return_value="LLM生成的摘要",
        ), patch("app.core.events.event_bus") as mock_bus:
            mock_bus.publish = AsyncMock()
            result = await generate_summary_for_content(session, 1)

        assert result.summary == "LLM生成的摘要"
        session.commit.assert_awaited()
        mock_bus.publish.assert_awaited_once()
        event_data = mock_bus.publish.call_args[0]
        assert event_data[0] == "content_updated"
        assert event_data[1]["summary"] == "LLM生成的摘要"

    async def test_llm_failure_sets_summary_none(self):
        content = _make_content()
        session = AsyncMock()
        session.get.return_value = content

        with patch(
            "app.services.content_summary_service.generate_summary_llm",
            new_callable=AsyncMock,
            side_effect=Exception("LLM down"),
        ), patch("app.core.events.event_bus") as mock_bus:
            mock_bus.publish = AsyncMock()
            result = await generate_summary_for_content(session, 1)

        assert result.summary is None
        session.commit.assert_awaited()

    async def test_images_from_archive_metadata(self):
        content = _make_content(
            archive_metadata={
                "archive": {
                    "images": [
                        {"url": "http://img1.png", "type": "photo"},
                        {"url": "http://avatar.png", "type": "avatar"},
                        {"url": "http://img2.png", "is_avatar": True},
                        {"url": "http://img3.png", "type": "photo"},
                    ]
                }
            },
        )
        session = AsyncMock()
        session.get.return_value = content

        with patch(
            "app.services.content_summary_service.generate_summary_llm",
            new_callable=AsyncMock,
            return_value="摘要",
        ) as mock_llm, patch("app.core.events.event_bus") as mock_bus:
            mock_bus.publish = AsyncMock()
            await generate_summary_for_content(session, 1)

        # Should exclude avatars: img1 and img3 included, avatar and is_avatar excluded
        call_kwargs = mock_llm.call_args
        images_arg = call_kwargs[1]["images"]
        assert "http://img1.png" in images_arg
        assert "http://img3.png" in images_arg
        assert "http://avatar.png" not in images_arg
        assert "http://img2.png" not in images_arg

    async def test_images_fallback_to_media_urls(self):
        content = _make_content(
            archive_metadata=None,
            media_urls=["http://media1.png", "local://skip.png", "http://media2.png"],
        )
        session = AsyncMock()
        session.get.return_value = content

        with patch(
            "app.services.content_summary_service.generate_summary_llm",
            new_callable=AsyncMock,
            return_value="摘要",
        ) as mock_llm, patch("app.core.events.event_bus") as mock_bus:
            mock_bus.publish = AsyncMock()
            await generate_summary_for_content(session, 1)

        images_arg = mock_llm.call_args[1]["images"]
        assert "http://media1.png" in images_arg
        assert "http://media2.png" in images_arg
        assert "local://skip.png" not in images_arg

    async def test_event_publish_failure_does_not_raise(self):
        content = _make_content()
        session = AsyncMock()
        session.get.return_value = content

        with patch(
            "app.services.content_summary_service.generate_summary_llm",
            new_callable=AsyncMock,
            return_value="摘要",
        ), patch("app.core.events.event_bus") as mock_bus:
            mock_bus.publish = AsyncMock(side_effect=Exception("event bus down"))
            result = await generate_summary_for_content(session, 1)

        # Should not raise, summary still set
        assert result.summary == "摘要"
