"""Tests for app.services.content_summary_service."""

import sys
import types as module_types
from unittest.mock import AsyncMock, MagicMock, patch

import pytest

from app.services.content_summary_service import (
    generate_summary_for_content,
    strip_markdown,
)
from app.services.config_service import SummaryAIConfig


def _summary_config(
    *,
    api_key: str | None = "test-key",
    model: str = "gemini-test-model",
    api_version: str = "v1beta",
) -> SummaryAIConfig:
    return SummaryAIConfig(
        enabled=True,
        api_key=api_key,
        model=model,
        api_version=api_version,
    )


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


def _make_content(**overrides):
    content = MagicMock()
    content.id = overrides.get("id", 1)
    content.title = overrides.get("title", "测试标题")
    content.body = overrides.get("body", "这是一段足够长的正文" * 30)
    content.summary = overrides.get("summary", None)
    content.tags = overrides.get("tags", [])
    content.rich_payload = overrides.get("rich_payload", {})
    return content


class _FakeGenerateContentConfig:
    def __init__(self, **kwargs):
        self.kwargs = kwargs


class _FakeModels:
    def __init__(self, response):
        self.response = response
        self.calls = []

    def generate_content(self, **kwargs):
        self.calls.append(kwargs)
        return self.response


class _FakeClient:
    def __init__(self, response):
        self.models = _FakeModels(response)


def _install_fake_genai(monkeypatch, response):
    fake_client = _FakeClient(response)

    google_module = module_types.ModuleType("google")
    genai_module = module_types.ModuleType("google.genai")
    genai_types_module = module_types.ModuleType("google.genai.types")

    def client_factory(**kwargs):
        fake_client.kwargs = kwargs
        return fake_client

    genai_module.Client = client_factory
    genai_types_module.GenerateContentConfig = _FakeGenerateContentConfig
    genai_module.types = genai_types_module
    google_module.genai = genai_module

    monkeypatch.setitem(sys.modules, "google", google_module)
    monkeypatch.setitem(sys.modules, "google.genai", genai_module)
    monkeypatch.setitem(sys.modules, "google.genai.types", genai_types_module)
    return fake_client


@pytest.mark.asyncio
class TestGenerateSummaryForContent:
    async def test_content_not_found_raises(self):
        session = AsyncMock()
        session.get.return_value = None

        with pytest.raises(ValueError, match="内容不存在"):
            await generate_summary_for_content(session, 999)

    async def test_skips_when_summary_and_chunks_exist(self):
        content = _make_content(
            summary="已有摘要",
            rich_payload={"chunks": [{"title": "已有切片"}]},
        )
        session = AsyncMock()
        session.get.return_value = content

        result = await generate_summary_for_content(session, 1)

        assert result is content
        session.commit.assert_not_awaited()

    async def test_no_api_key_returns_without_committing(self):
        content = _make_content()
        session = AsyncMock()
        session.get.return_value = content

        with patch(
            "app.services.content_summary_service.ConfigService.get_summary_ai_config",
            new_callable=AsyncMock,
            return_value=_summary_config(api_key=None),
        ):
            result = await generate_summary_for_content(session, 1)

        assert result is content
        assert content.summary is None
        session.commit.assert_not_awaited()

    async def test_successful_generation_persists_summary_tags_and_chunks(self, monkeypatch):
        content = _make_content(tags=["existing"])
        session = AsyncMock()
        session.get.return_value = content

        response = MagicMock()
        response.parsed = {
            "summary": "新摘要",
            "tags": ["ai", "existing"],
            "rag_chunks": [
                {
                    "title": "切片",
                    "content": "切片正文",
                    "media_refs": ["local://sha256:abc"],
                }
            ],
        }
        fake_client = _install_fake_genai(monkeypatch, response)

        with patch(
            "app.services.content_summary_service.ConfigService.get_summary_ai_config",
            new_callable=AsyncMock,
            return_value=_summary_config(model="gemini-summary", api_version="v1"),
        ), patch(
            "app.services.content_summary_service.flag_modified",
        ) as mock_flag:
            result = await generate_summary_for_content(session, 1)

        assert result.summary == "新摘要"
        assert sorted(result.tags) == ["ai", "existing"]
        assert result.rich_payload["chunks"][0]["title"] == "切片"
        assert fake_client.kwargs["api_key"] == "test-key"
        assert fake_client.kwargs["http_options"] == {"api_version": "v1"}
        assert fake_client.models.calls[0]["model"] == "gemini-summary"
        session.commit.assert_awaited_once()
        assert mock_flag.call_count == 2

    async def test_generation_can_parse_json_text_response(self, monkeypatch):
        content = _make_content()
        session = AsyncMock()
        session.get.return_value = content

        response = MagicMock()
        response.parsed = None
        response.text = (
            '{"summary": "文本响应摘要", "tags": ["json"], '
            '"rag_chunks": [{"title": "json切片", "content": "正文", "media_refs": []}]}'
        )
        _install_fake_genai(monkeypatch, response)

        with patch(
            "app.services.content_summary_service.ConfigService.get_summary_ai_config",
            new_callable=AsyncMock,
            return_value=_summary_config(),
        ), patch(
            "app.services.content_summary_service.flag_modified",
        ):
            result = await generate_summary_for_content(session, 1)

        assert result.summary == "文本响应摘要"
        assert result.tags == ["json"]
        assert result.rich_payload["chunks"][0]["title"] == "json切片"
        session.commit.assert_awaited_once()

    async def test_generation_failure_does_not_commit_or_raise(self, monkeypatch):
        content = _make_content()
        session = AsyncMock()
        session.get.return_value = content

        class FailingModels:
            def generate_content(self, **kwargs):
                raise RuntimeError("Gemini down")

        class FailingClient:
            models = FailingModels()

        google_module = module_types.ModuleType("google")
        genai_module = module_types.ModuleType("google.genai")
        genai_types_module = module_types.ModuleType("google.genai.types")
        genai_module.Client = lambda **kwargs: FailingClient()
        genai_types_module.GenerateContentConfig = _FakeGenerateContentConfig
        genai_module.types = genai_types_module
        google_module.genai = genai_module
        monkeypatch.setitem(sys.modules, "google", google_module)
        monkeypatch.setitem(sys.modules, "google.genai", genai_module)
        monkeypatch.setitem(sys.modules, "google.genai.types", genai_types_module)

        with patch(
            "app.services.content_summary_service.ConfigService.get_summary_ai_config",
            new_callable=AsyncMock,
            return_value=_summary_config(),
        ):
            result = await generate_summary_for_content(session, 1)

        assert result is content
        session.commit.assert_not_awaited()
