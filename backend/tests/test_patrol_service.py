"""Tests for app.services.patrol_service"""

import json
import pytest
from unittest.mock import AsyncMock, MagicMock, patch

from app.services.patrol_service import PatrolService
from app.models.base import DiscoveryState, Platform


# ────────────────────────────────────────────
# Helpers
# ────────────────────────────────────────────

def _make_content(**overrides):
    """Build a mock Content object with sensible defaults."""
    content = MagicMock()
    content.id = overrides.get("id", 1)
    content.title = overrides.get("title", "Test Title")
    content.body = overrides.get("body", "Some interesting article body text.")
    content.url = overrides.get("url", "https://example.com/article")
    content.source = overrides.get("source", "hackernews")
    content.author_name = overrides.get("author_name", "testauthor")
    content.platform = overrides.get("platform", Platform.UNIVERSAL)
    content.ai_score = None
    content.ai_reason = None
    content.ai_tags = None
    content.summary = None
    content.discovery_state = overrides.get("discovery_state", DiscoveryState.INGESTED)
    return content


def _mock_llm_response(data: dict):
    """Create a mock LLM response with JSON content."""
    response = MagicMock()
    response.content = json.dumps(data)
    return response


GOOD_SCORING = {
    "score": 7.5,
    "reason": "High quality technical content",
    "summary": "A great article about testing",
    "tags": ["testing", "python", "ai"],
}

LOW_SCORING = {
    "score": 3.0,
    "reason": "Generic content",
    "summary": "Nothing special",
    "tags": ["misc"],
}


# ────────────────────────────────────────────
# _parse_scoring_response
# ────────────────────────────────────────────

class TestParseScoringResponse:
    def setup_method(self):
        self.svc = PatrolService()

    def test_parse_valid_json(self):
        result = self.svc._parse_scoring_response(json.dumps(GOOD_SCORING))
        assert result is not None
        assert result["score"] == 7.5
        assert result["reason"] == "High quality technical content"
        assert result["summary"] == "A great article about testing"
        assert result["tags"] == ["testing", "python", "ai"]

    def test_parse_invalid_json(self):
        result = self.svc._parse_scoring_response("not valid json {{{")
        assert result is None

    def test_parse_missing_score_field(self):
        result = self.svc._parse_scoring_response(json.dumps({"reason": "no score"}))
        assert result is None

    def test_parse_non_dict_json(self):
        result = self.svc._parse_scoring_response(json.dumps([1, 2, 3]))
        assert result is None

    def test_parse_score_coerced_to_float(self):
        result = self.svc._parse_scoring_response(json.dumps({"score": "8", "reason": "ok"}))
        assert result is not None
        assert result["score"] == 8.0


# ────────────────────────────────────────────
# _build_system_prompt
# ────────────────────────────────────────────

class TestBuildSystemPrompt:
    def setup_method(self):
        self.svc = PatrolService()

    def test_build_system_prompt_without_interest(self):
        prompt = self.svc._build_system_prompt("")
        assert "expert content curator" in prompt
        assert "User interest profile" not in prompt

    def test_build_system_prompt_with_interest(self):
        prompt = self.svc._build_system_prompt("I like AI and Rust")
        assert "User interest profile" in prompt
        assert "I like AI and Rust" in prompt


# ────────────────────────────────────────────
# _build_user_prompt
# ────────────────────────────────────────────

class TestBuildUserPrompt:
    def setup_method(self):
        self.svc = PatrolService()

    def test_build_user_prompt(self):
        content = _make_content(
            title="My Title",
            source="reddit",
            author_name="john",
            url="https://example.com",
            body="Article body here",
        )
        prompt = self.svc._build_user_prompt(content)
        assert "My Title" in prompt
        assert "reddit" in prompt
        assert "john" in prompt
        assert "https://example.com" in prompt
        assert "Article body here" in prompt


# ────────────────────────────────────────────
# score_item
# ────────────────────────────────────────────

@pytest.mark.asyncio
class TestScoreItem:
    def setup_method(self):
        self.svc = PatrolService()

    async def test_score_item_updates_content(self):
        """Mock LLM, verify content fields updated + state transition."""
        content = _make_content()
        mock_llm = AsyncMock()
        mock_llm.ainvoke.return_value = _mock_llm_response(GOOD_SCORING)

        with patch("app.services.patrol_service.LLMFactory") as mock_factory, \
             patch("app.services.settings_service.get_setting_value", new_callable=AsyncMock, return_value=6.0):
            mock_factory.get_text_llm = AsyncMock(return_value=mock_llm)

            result = await self.svc.score_item(content)

        assert result is True
        assert content.ai_score == 7.5
        assert content.ai_reason == "High quality technical content"
        assert content.summary == "A great article about testing"
        assert content.ai_tags == ["testing", "python", "ai"]

    async def test_score_above_threshold_marks_visible(self):
        """score >= threshold → discovery_state=VISIBLE"""
        content = _make_content()
        mock_llm = AsyncMock()
        mock_llm.ainvoke.return_value = _mock_llm_response(GOOD_SCORING)

        with patch("app.services.patrol_service.LLMFactory") as mock_factory, \
             patch("app.services.settings_service.get_setting_value", new_callable=AsyncMock, return_value=6.0):
            mock_factory.get_text_llm = AsyncMock(return_value=mock_llm)

            await self.svc.score_item(content)

        assert content.discovery_state == DiscoveryState.VISIBLE

    async def test_score_below_threshold_marks_ignored(self):
        """score < threshold → discovery_state=IGNORED"""
        content = _make_content()
        mock_llm = AsyncMock()
        mock_llm.ainvoke.return_value = _mock_llm_response(LOW_SCORING)

        with patch("app.services.patrol_service.LLMFactory") as mock_factory, \
             patch("app.services.settings_service.get_setting_value", new_callable=AsyncMock, return_value=6.0):
            mock_factory.get_text_llm = AsyncMock(return_value=mock_llm)

            await self.svc.score_item(content)

        assert content.discovery_state == DiscoveryState.IGNORED

    async def test_score_item_llm_unavailable(self):
        """LLM returns None → returns False, no crash."""
        content = _make_content()

        with patch("app.services.patrol_service.LLMFactory") as mock_factory:
            mock_factory.get_text_llm = AsyncMock(return_value=None)

            result = await self.svc.score_item(content)

        assert result is False
        assert content.ai_score is None

    async def test_score_item_llm_invocation_error(self):
        """LLM raises exception → returns False."""
        content = _make_content()
        mock_llm = AsyncMock()
        mock_llm.ainvoke.side_effect = Exception("API timeout")

        with patch("app.services.patrol_service.LLMFactory") as mock_factory:
            mock_factory.get_text_llm = AsyncMock(return_value=mock_llm)

            result = await self.svc.score_item(content)

        assert result is False

    async def test_score_item_bad_json_response(self):
        """LLM returns non-JSON → returns False."""
        content = _make_content()
        mock_llm = AsyncMock()
        bad_response = MagicMock()
        bad_response.content = "I cannot provide a JSON response"
        mock_llm.ainvoke.return_value = bad_response

        with patch("app.services.patrol_service.LLMFactory") as mock_factory:
            mock_factory.get_text_llm = AsyncMock(return_value=mock_llm)

            result = await self.svc.score_item(content)

        assert result is False


# ────────────────────────────────────────────
# score_batch
# ────────────────────────────────────────────

@pytest.mark.asyncio
class TestScoreBatch:
    def setup_method(self):
        self.svc = PatrolService()

    async def test_score_batch(self):
        """Mock LLM, verify batch processes all items."""
        items = [_make_content(id=i) for i in range(3)]
        mock_llm = AsyncMock()
        mock_llm.ainvoke.return_value = _mock_llm_response(GOOD_SCORING)

        with patch("app.services.patrol_service.LLMFactory") as mock_factory, \
             patch("app.services.settings_service.get_setting_value", new_callable=AsyncMock, return_value=6.0):
            mock_factory.get_text_llm = AsyncMock(return_value=mock_llm)

            scored = await self.svc.score_batch(items)

        assert scored == 3
        assert mock_llm.ainvoke.await_count == 3
        for item in items:
            assert item.ai_score == 7.5

    async def test_score_batch_partial_failure(self):
        """Some items fail, count reflects successes only."""
        items = [_make_content(id=i) for i in range(3)]
        mock_llm = AsyncMock()
        # First call succeeds, second fails, third succeeds
        mock_llm.ainvoke.side_effect = [
            _mock_llm_response(GOOD_SCORING),
            Exception("API error"),
            _mock_llm_response(GOOD_SCORING),
        ]

        with patch("app.services.patrol_service.LLMFactory") as mock_factory, \
             patch("app.services.settings_service.get_setting_value", new_callable=AsyncMock, return_value=6.0):
            mock_factory.get_text_llm = AsyncMock(return_value=mock_llm)

            scored = await self.svc.score_batch(items)

        assert scored == 2
