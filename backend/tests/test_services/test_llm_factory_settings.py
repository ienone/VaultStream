from __future__ import annotations

import pytest

from app.core.llm_factory import LLMFactory


@pytest.mark.asyncio
async def test_text_llm_base_url_takes_precedence(monkeypatch):
    async def _fake_setting(key: str, default=None):
        values = {
            "text_llm_api_key": "test-key",
            "text_llm_base_url": "https://base-url.example/v1",
            "text_llm_api_base": "https://legacy-api-base.example/v1",
            "text_llm_model": "qwen-test",
        }
        return values.get(key, default)

    monkeypatch.setattr("app.core.llm_factory.get_setting_value", _fake_setting)
    config = await LLMFactory.get_crawl4ai_config("text")
    assert config["base_url"] == "https://base-url.example/v1"
    assert config["provider"] == "openai/qwen-test"
