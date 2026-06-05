from __future__ import annotations

import pytest

from app.core.llm_factory import LLMFactory
from app.services.config_service import AgentChatConfig, LLMConfig


@pytest.mark.asyncio
async def test_text_llm_base_url_takes_precedence(monkeypatch):
    async def _fake_text_config(self):
        return LLMConfig(
            api_key="test-key",
            model="qwen-test",
            base_url="https://base-url.example/v1",
        )

    monkeypatch.setattr(
        "app.services.config_service.ConfigService.get_text_llm_config",
        _fake_text_config,
    )
    config = await LLMFactory.get_crawl4ai_config("text")
    assert config["base_url"] == "https://base-url.example/v1"
    assert config["provider"] == "openai/qwen-test"


@pytest.mark.asyncio
async def test_text_llm_uses_typed_config(monkeypatch):
    captured: dict[str, object] = {}

    class FakeChat:
        def __init__(self, **kwargs):
            captured.update(kwargs)

    async def _fake_text_config(self):
        return LLMConfig(
            api_key="text-key",
            model="text-model",
            base_url="https://text.example/v1",
        )

    monkeypatch.setattr("app.core.llm_factory.ChatOpenAICompatible", FakeChat)
    monkeypatch.setattr(
        "app.services.config_service.ConfigService.get_text_llm_config",
        _fake_text_config,
    )

    llm = await LLMFactory.get_text_llm()

    assert llm is not None
    assert captured["api_key"] == "text-key"
    assert captured["model"] == "text-model"
    assert captured["base_url"] == "https://text.example/v1"
    assert captured["temperature"] == 0.3


@pytest.mark.asyncio
async def test_vision_llm_uses_typed_config(monkeypatch):
    captured: dict[str, object] = {}

    class FakeChat:
        def __init__(self, **kwargs):
            captured.update(kwargs)

    async def _fake_vision_config(self):
        return LLMConfig(
            api_key="vision-key",
            model="vision-model",
            base_url="https://vision.example/v1",
        )

    monkeypatch.setattr("app.core.llm_factory.ChatOpenAICompatible", FakeChat)
    monkeypatch.setattr(
        "app.services.config_service.ConfigService.get_vision_llm_config",
        _fake_vision_config,
    )

    llm = await LLMFactory.get_vision_llm()

    assert llm is not None
    assert captured["api_key"] == "vision-key"
    assert captured["model"] == "vision-model"
    assert captured["base_url"] == "https://vision.example/v1"
    assert captured["temperature"] == 0.0


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
