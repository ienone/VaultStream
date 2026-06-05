from __future__ import annotations

import os
from dataclasses import dataclass
from typing import Any, Callable, Optional

from pydantic import SecretStr

from app.core.db_adapter import AsyncSessionLocal
from app.models import SystemSetting
from app.utils.sensitive_display import (
    as_configured_placeholder,
    extract_secret_value,
    is_sensitive_setting_key,
)


def coerce_setting_value(value: Any) -> Any:
    if isinstance(value, str):
        if value.lower() == "true":
            return True
        if value.lower() == "false":
            return False
    return value


def coerce_bool(value: Any) -> bool:
    return bool(coerce_setting_value(value))


def coerce_int(value: Any, default: int) -> int:
    try:
        return int(value)
    except (TypeError, ValueError):
        return default


@dataclass(frozen=True)
class SummaryAIConfig:
    enabled: bool
    api_key: str | None
    model: str
    api_version: str


@dataclass(frozen=True)
class EmbeddingAIConfig:
    api_key: str | None
    model: str
    output_dimensionality: int
    search_max_rows: int


@dataclass(frozen=True)
class AgentChatConfig:
    api_key: str | None
    model: str
    base_url: str | None


@dataclass(frozen=True)
class AIConfig:
    summary: SummaryAIConfig
    embedding: EmbeddingAIConfig
    agent_chat: AgentChatConfig


class ConfigService:
    def __init__(
        self,
        *,
        session_factory: Callable[..., Any] = AsyncSessionLocal,
        cache: dict[str, Any] | None = None,
    ) -> None:
        self._session_factory = session_factory
        self._cache = cache if cache is not None else {}

    async def get_value(self, key: str, default: Any = None) -> Any:
        if key in self._cache:
            return coerce_setting_value(self._cache[key])

        async with self._session_factory() as db:
            from app.repositories import SystemRepository

            repo = SystemRepository(db)
            setting = await repo.get_setting(key)

            if setting:
                self._cache[key] = setting.value
                return coerce_setting_value(setting.value)

        return default

    async def get_value_fresh(self, key: str, default: Any = None) -> Any:
        async with self._session_factory() as db:
            from app.repositories import SystemRepository

            repo = SystemRepository(db)
            setting = await repo.get_setting(key)

            if setting:
                self._cache[key] = setting.value
                return coerce_setting_value(setting.value)

        return default

    async def set_value(
        self,
        key: str,
        value: Any,
        *,
        category: str = "general",
        description: Optional[str] = None,
    ) -> SystemSetting:
        async with self._session_factory() as db:
            from app.repositories import SystemRepository

            repo = SystemRepository(db)
            setting = await repo.upsert_setting(
                key=key,
                value=value,
                category=category,
                description=description,
            )

            await db.commit()
            await db.refresh(setting)

            self._cache[key] = value
            self._sync_runtime_setting(key, value)
            return setting

    async def load_all_to_memory(self) -> None:
        async with self._session_factory() as db:
            from app.repositories import SystemRepository

            repo = SystemRepository(db)
            settings_list = await repo.list_settings()

            for setting in settings_list:
                self._cache[setting.key] = setting.value
                self._sync_runtime_setting(setting.key, setting.value)

    async def delete_value(self, key: str) -> bool:
        async with self._session_factory() as db:
            from app.repositories import SystemRepository

            repo = SystemRepository(db)
            setting = await repo.get_setting(key)

            if setting is None:
                return False

            await repo.delete_setting(setting)
            await db.commit()
            self._cache.pop(key, None)
            self._clear_runtime_setting(key)
            return True

    async def list_values(self, category: Optional[str] = None) -> list[dict[str, Any]]:
        async with self._session_factory() as db:
            from app.repositories import SystemRepository

            repo = SystemRepository(db)
            settings_list = await repo.list_settings(category=category)

            response_items: list[dict[str, Any]] = []
            for setting in settings_list:
                value = setting.value
                if is_sensitive_setting_key(setting.key):
                    value = as_configured_placeholder(setting.value, source="db") or ""

                response_items.append(
                    {
                        "key": setting.key,
                        "value": value,
                        "category": setting.category,
                        "description": setting.description,
                        "updated_at": setting.updated_at,
                    }
                )

            return response_items

    def invalidate(self, key: str) -> None:
        self._cache.pop(key, None)

    async def get_summary_ai_config(self) -> SummaryAIConfig:
        from app.core.config import settings

        api_key = await self.get_value("summary_api_key")
        key_text = extract_secret_value(api_key)
        if key_text is None:
            key_text = extract_secret_value(settings.summary_api_key)
        if key_text is None:
            key_text = os.environ.get("GEMINI_API_KEY")

        model = await self.get_value("summary_model", settings.summary_model)
        api_version = await self.get_value(
            "summary_api_version",
            settings.summary_api_version,
        )
        enabled = await self.get_value(
            "enable_auto_summary",
            settings.enable_auto_summary,
        )

        return SummaryAIConfig(
            enabled=coerce_bool(enabled),
            api_key=key_text,
            model=str(model or settings.summary_model),
            api_version=str(api_version or settings.summary_api_version),
        )

    async def get_embedding_ai_config(self) -> EmbeddingAIConfig:
        from app.core.config import settings

        api_key = await self.get_value("embedding_api_key")
        key_text = extract_secret_value(api_key)
        if key_text is None:
            key_text = extract_secret_value(settings.embedding_api_key)

        model = await self.get_value("embedding_model", settings.embedding_model)
        output_dimensionality = await self.get_value(
            "embedding_output_dimensionality",
            settings.embedding_output_dimensionality,
        )
        search_max_rows = await self.get_value(
            "embedding_search_max_rows",
            settings.embedding_search_max_rows,
        )

        return EmbeddingAIConfig(
            api_key=key_text,
            model=str(model or settings.embedding_model),
            output_dimensionality=coerce_int(
                output_dimensionality,
                settings.embedding_output_dimensionality,
            ),
            search_max_rows=coerce_int(
                search_max_rows,
                settings.embedding_search_max_rows,
            ),
        )

    async def get_agent_chat_config(self) -> AgentChatConfig:
        from app.core.config import settings

        api_key = await self.get_value("agent_chat_api_key")
        key_text = extract_secret_value(api_key)
        if key_text is None:
            key_text = extract_secret_value(await self.get_value("text_llm_api_key"))
        if key_text is None:
            key_text = extract_secret_value(settings.text_llm_api_key)

        base_url = await self.get_value("agent_chat_base_url")
        if not base_url:
            base_url = await self.get_value("text_llm_base_url")
        if not base_url:
            base_url = await self.get_value("text_llm_api_base")
        if not base_url:
            base_url = settings.text_llm_base_url

        model = await self.get_value("agent_chat_model")
        if not model:
            model = await self.get_value("text_llm_model", settings.text_llm_model)

        return AgentChatConfig(
            api_key=key_text,
            model=str(model or settings.text_llm_model),
            base_url=str(base_url) if base_url else None,
        )

    async def get_ai_config(self) -> AIConfig:
        return AIConfig(
            summary=await self.get_summary_ai_config(),
            embedding=await self.get_embedding_ai_config(),
            agent_chat=await self.get_agent_chat_config(),
        )

    def _sync_runtime_setting(self, key: str, value: Any) -> None:
        from app.core.config import settings

        if not hasattr(settings, key):
            return

        field_type = settings.__annotations__.get(key)
        if field_type == SecretStr or "SecretStr" in str(field_type):
            setattr(settings, key, SecretStr(str(value)) if value else None)
        else:
            setattr(settings, key, value)

    def _clear_runtime_setting(self, key: str) -> None:
        from app.core.config import settings

        if not hasattr(settings, key):
            return

        field_type = settings.__annotations__.get(key)
        if field_type == SecretStr or "SecretStr" in str(field_type):
            setattr(settings, key, None)
        else:
            setattr(settings, key, "")
