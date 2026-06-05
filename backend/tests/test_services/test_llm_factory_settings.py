from __future__ import annotations

import pytest

from app.core.llm_factory import LLMFactory
from app.services.config_service import AgentChatConfig


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


@pytest.mark.asyncio
async def test_agent_chat_llm_uses_agent_specific_config(monkeypatch):
    captured: dict[str, object] = {}

    class FakeChat:
        def __init__(self, **kwargs):
            captured.update(kwargs)

    async def _fake_agent_config(self):
        return AgentChatConfig(
            api_key="agent-key",
            model="agent-model",
            base_url="https://agent.example/v1",
        )

    monkeypatch.setattr("app.core.llm_factory.ChatOpenAICompatible", FakeChat)
    monkeypatch.setattr(
        "app.services.config_service.ConfigService.get_agent_chat_config",
        _fake_agent_config,
    )

    llm = await LLMFactory.get_agent_chat_llm()

    assert llm is not None
    assert captured["api_key"] == "agent-key"
    assert captured["model"] == "agent-model"
    assert captured["base_url"] == "https://agent.example/v1"
    assert captured["temperature"] == 0.2
