"""Tests for app.services.patrol_service"""

import json
import pytest
from uuid import uuid4
from unittest.mock import AsyncMock, MagicMock, patch

from app.services.patrol_service import PatrolService
from app.services.background_task_state import get_recent_task_runs
from app.models import Content
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


class _FakeConfigService:
    def __init__(self, values: dict[str, object]) -> None:
        self.values = values

    async def get_value(self, key: str, default=None):
        return self.values.get(key, default)


def _patrol_service(**config_values) -> PatrolService:
    values = {"discovery_score_threshold": 6.0}
    values.update(config_values)
    return PatrolService(config_service=_FakeConfigService(values))


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
        self.svc = _patrol_service()

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
        self.svc = _patrol_service()

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
        self.svc = _patrol_service()

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
        self.svc = _patrol_service()

    async def test_score_item_updates_content(self):
        """Mock LLM, verify content fields updated + state transition."""
        content = _make_content()
        mock_llm = AsyncMock()
        mock_llm.ainvoke.return_value = _mock_llm_response(GOOD_SCORING)

        with patch("app.services.patrol_service.LLMFactory") as mock_factory:
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

        with patch("app.services.patrol_service.LLMFactory") as mock_factory:
            mock_factory.get_text_llm = AsyncMock(return_value=mock_llm)

            await self.svc.score_item(content)

        assert content.discovery_state == DiscoveryState.VISIBLE

    async def test_score_below_threshold_marks_ignored(self):
        """score < threshold → discovery_state=IGNORED"""
        content = _make_content()
        mock_llm = AsyncMock()
        mock_llm.ainvoke.return_value = _mock_llm_response(LOW_SCORING)

        with patch("app.services.patrol_service.LLMFactory") as mock_factory:
            mock_factory.get_text_llm = AsyncMock(return_value=mock_llm)

            await self.svc.score_item(content)

        assert content.discovery_state == DiscoveryState.IGNORED

    async def test_score_item_uses_injected_threshold_config(self):
        """Injected threshold controls visible/ignored state."""
        content = _make_content()
        mock_llm = AsyncMock()
        mock_llm.ainvoke.return_value = _mock_llm_response(GOOD_SCORING)
        svc = _patrol_service(discovery_score_threshold=8.0)

        with patch("app.services.patrol_service.LLMFactory") as mock_factory:
            mock_factory.get_text_llm = AsyncMock(return_value=mock_llm)

            await svc.score_item(content)

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
        self.svc = _patrol_service()

    async def test_score_batch(self):
        """Mock LLM, verify batch processes all items."""
        items = [_make_content(id=i) for i in range(3)]
        mock_llm = AsyncMock()
        mock_llm.ainvoke.return_value = _mock_llm_response(GOOD_SCORING)

        with patch("app.services.patrol_service.LLMFactory") as mock_factory:
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

        with patch("app.services.patrol_service.LLMFactory") as mock_factory:
            mock_factory.get_text_llm = AsyncMock(return_value=mock_llm)

            scored = await self.svc.score_batch(items)

        assert scored == 2


@pytest.mark.asyncio
async def test_score_pending_records_discovery_patrol_run(monkeypatch, db_session, client):
    token = uuid4().hex
    contents = [
        Content(
            platform=Platform.RSS,
            url=f"https://example.com/patrol/{token}/1",
            canonical_url=f"https://example.com/patrol/{token}/1",
            title=f"Patrol run test {token} 1",
            body="Interesting content",
            discovery_state=DiscoveryState.INGESTED,
        ),
        Content(
            platform=Platform.RSS,
            url=f"https://example.com/patrol/{token}/2",
            canonical_url=f"https://example.com/patrol/{token}/2",
            title=f"Patrol run test {token} 2",
            body="More interesting content",
            discovery_state=DiscoveryState.INGESTED,
        ),
    ]
    db_session.add_all(contents)
    await db_session.commit()

    async def fake_score_batch(self, items, interest_profile="", batch_size=10):
        assert interest_profile == "AI and systems"
        for item in items:
            if item.title and token in item.title:
                item.discovery_state = DiscoveryState.VISIBLE
        return len(items)

    monkeypatch.setattr(PatrolService, "score_batch", fake_score_batch)

    scored = await PatrolService(
        config_service=_FakeConfigService(
            {"discovery_interest_profile": "AI and systems"}
        )
    ).score_pending(db_session)

    runs = await get_recent_task_runs("discovery_patrol")
    latest = runs[0]
    assert latest["task"] == "discovery_patrol"
    assert latest["status"] == "success"
    assert latest["trigger"] == "auto"
    assert latest["result"]["candidate_count"] == scored
    assert latest["result"]["scored_count"] == scored
    assert latest["result"]["failed_count"] == 0
    assert latest["result"]["interest_profile_present"] is True

    diagnostics = await client.get("/api/v1/background-tasks/diagnostics")
    assert diagnostics.status_code == 200
    diagnostic_run = next(
        run
        for run in diagnostics.json()["recent_task_runs"]
        if run["run_id"] == latest["run_id"]
    )
    assert diagnostic_run["task"] == "discovery_patrol"
    assert diagnostic_run["status"] == "success"
