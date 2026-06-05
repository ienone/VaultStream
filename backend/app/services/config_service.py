from __future__ import annotations

import os
from collections.abc import Iterable
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


def coerce_float(value: Any, default: float) -> float:
    try:
        return float(value)
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
class LLMConfig:
    api_key: str | None
    model: str
    base_url: str | None


@dataclass(frozen=True)
class AIConfig:
    summary: SummaryAIConfig
    embedding: EmbeddingAIConfig
    agent_chat: AgentChatConfig
    text_llm: LLMConfig
    vision_llm: LLMConfig


@dataclass(frozen=True)
class FavoritesSyncConfig:
    enabled_platforms: list[str]
    interval_minutes: int
    max_items: int
    duplicate_strategy: str
    last_sync_at: Any


@dataclass(frozen=True)
class FavoritesSyncPlatformState:
    platform: str
    rate_per_minute: float
    cursor: str | None
    last_result: Any


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

    async def get_text_llm_config(self) -> LLMConfig:
        from app.core.config import settings

        api_key = await self.get_value("text_llm_api_key")
        key_text = extract_secret_value(api_key)
        if key_text is None:
            key_text = extract_secret_value(settings.text_llm_api_key)

        base_url = await self.get_value("text_llm_base_url")
        if not base_url:
            base_url = await self.get_value("text_llm_api_base")
        if not base_url:
            base_url = settings.text_llm_base_url

        model = await self.get_value("text_llm_model", settings.text_llm_model)

        return LLMConfig(
            api_key=key_text,
            model=str(model or settings.text_llm_model),
            base_url=str(base_url) if base_url else None,
        )

    async def get_vision_llm_config(self) -> LLMConfig:
        from app.core.config import settings

        api_key = await self.get_value("vision_llm_api_key")
        key_text = extract_secret_value(api_key)
        if key_text is None:
            key_text = extract_secret_value(settings.vision_llm_api_key)

        base_url = await self.get_value("vision_llm_base_url")
        if not base_url:
            base_url = await self.get_value("vision_llm_api_base")
        if not base_url:
            base_url = settings.vision_llm_base_url

        model = await self.get_value("vision_llm_model", settings.vision_llm_model)

        return LLMConfig(
            api_key=key_text,
            model=str(model or settings.vision_llm_model),
            base_url=str(base_url) if base_url else None,
        )

    async def get_ai_config(self) -> AIConfig:
        return AIConfig(
            summary=await self.get_summary_ai_config(),
            embedding=await self.get_embedding_ai_config(),
            agent_chat=await self.get_agent_chat_config(),
            text_llm=await self.get_text_llm_config(),
            vision_llm=await self.get_vision_llm_config(),
        )

    @staticmethod
    def parse_favorites_sync_platforms(raw_value: object) -> list[str]:
        import json
        from collections.abc import Iterable

        if raw_value is None:
            return []
        if isinstance(raw_value, str):
            text = raw_value.strip()
            if not text:
                return []
            try:
                parsed = json.loads(text)
                if isinstance(parsed, list):
                    return [str(x).strip().lower() for x in parsed if str(x).strip()]
            except json.JSONDecodeError:
                pass
            return [x.strip().lower() for x in text.split(",") if x.strip()]
        if isinstance(raw_value, Iterable):
            values: list[str] = []
            for item in raw_value:
                text = str(item).strip().lower()
                if text:
                    values.append(text)
            return values
        return []

    async def get_favorites_sync_config(
        self,
        *,
        default_interval_minutes: int,
        default_max_items: int,
        default_duplicate_strategy: str,
        supported_platforms: Iterable[str] | None = None,
        allowed_duplicate_strategies: set[str] | None = None,
        fresh: bool = False,
    ) -> FavoritesSyncConfig:
        read = self.get_value_fresh if fresh else self.get_value

        interval = coerce_int(
            await read("favorites_sync_interval_minutes", default_interval_minutes),
            default_interval_minutes,
        )
        if interval <= 0:
            interval = default_interval_minutes

        max_items = coerce_int(
            await read("favorites_sync_max_items", default_max_items),
            default_max_items,
        )
        if max_items <= 0:
            max_items = default_max_items

        strategy = str(
            await read(
                "favorites_sync_duplicate_strategy",
                default_duplicate_strategy,
            )
            or default_duplicate_strategy
        ).strip().lower()
        if allowed_duplicate_strategies and strategy not in allowed_duplicate_strategies:
            strategy = default_duplicate_strategy

        raw_platforms = await read("favorites_sync_platforms", [])
        enabled_platforms = self.parse_favorites_sync_platforms(raw_platforms)
        if supported_platforms is not None:
            supported = set(supported_platforms)
            enabled_platforms = [
                platform for platform in enabled_platforms if platform in supported
            ]

        return FavoritesSyncConfig(
            enabled_platforms=enabled_platforms,
            interval_minutes=interval,
            max_items=max_items,
            duplicate_strategy=strategy,
            last_sync_at=await read("favorites_sync_last_sync_at"),
        )

    async def get_favorites_sync_platform_state(
        self,
        platform: str,
        *,
        default_rate_per_minute: float,
        fresh: bool = False,
    ) -> FavoritesSyncPlatformState:
        read = self.get_value_fresh if fresh else self.get_value
        cursor = await read(f"favorites_sync_cursor_{platform}")
        if not isinstance(cursor, str):
            cursor = None

        return FavoritesSyncPlatformState(
            platform=platform,
            rate_per_minute=coerce_float(
                await read(
                    f"favorites_sync_rate_{platform}",
                    default_rate_per_minute,
                ),
                default_rate_per_minute,
            ),
            cursor=cursor,
            last_result=await read(f"favorites_sync_last_result_{platform}"),
        )

    async def set_favorites_sync_last_sync_at(self, value: Any) -> SystemSetting:
        return await self.set_value(
            "favorites_sync_last_sync_at",
            value,
            category="favorites_sync",
        )

    async def set_favorites_sync_last_result(self, value: Any) -> SystemSetting:
        return await self.set_value(
            "favorites_sync_last_result",
            value,
            category="favorites_sync",
        )

    async def set_favorites_sync_platform_last_result(
        self,
        platform: str,
        value: Any,
    ) -> SystemSetting:
        return await self.set_value(
            f"favorites_sync_last_result_{platform}",
            value,
            category="favorites_sync",
        )

    async def set_favorites_sync_cursor(
        self,
        platform: str,
        value: str,
    ) -> SystemSetting:
        return await self.set_value(
            f"favorites_sync_cursor_{platform}",
            value,
            category="favorites_sync",
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
