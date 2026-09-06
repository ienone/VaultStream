"""AI provider and platform parser diagnostic orchestration."""

from __future__ import annotations

import asyncio
import time
from typing import Any
from urllib.parse import urlparse

import httpx
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.config import settings
from app.models import Platform
from app.services.background_task_state import (
    get_recent_task_runs,
    record_task_run_error,
    record_task_run_started,
    record_task_run_success,
)
from app.services.config_service import ConfigService, coerce_bool
from app.services.embedding_service import EmbeddingService
from app.services.settings_service import get_setting_value
from app.utils.sensitive_display import extract_secret_value


def _is_configured_value(value: Any) -> bool:
    text = extract_secret_value(value)
    return isinstance(text, str) and bool(text.strip())


async def _llm_key_configured(prefix: str) -> bool:
    return _is_configured_value(
        await get_setting_value(f"{prefix}_api_key")
    )


def _capability_item(
    key: str,
    label: str,
    status: str,
    summary: str,
    *,
    issues: list[str] | None = None,
    actions: list[str] | None = None,
    details: dict[str, Any] | None = None,
) -> dict[str, Any]:
    return {
        "key": key,
        "label": label,
        "status": status,
        "available": status == "available",
        "summary": summary,
        "issues": issues or [],
        "actions": actions or [],
        "details": details or {},
    }


async def _run_ai_connectivity_target(target: str) -> dict[str, Any]:
    if target in {"agent_chat", "text_llm", "vision_llm"}:
        from langchain_core.messages import HumanMessage

        from app.core.llm_factory import LLMFactory

        if target == "agent_chat":
            llm = await LLMFactory.get_agent_chat_llm()
        elif target == "text_llm":
            llm = await LLMFactory.get_text_llm()
        else:
            llm = await LLMFactory.get_vision_llm()
        if llm is None:
            raise RuntimeError(
                f"{target} is not configured or model initialization failed"
            )
        response = await llm.ainvoke(
            [HumanMessage(content="VaultStream connectivity test. Reply with OK.")]
        )
        text = str(getattr(response, "content", "") or "").strip()
        return {
            "target": target,
            "response_present": bool(text),
            "preview": text[:120],
        }

    if target == "semantic_search":
        vector = await EmbeddingService().embed_query(
            "VaultStream connectivity test"
        )
        return {
            "target": target,
            "dimension": len(vector),
            "response_present": bool(vector),
        }

    from app.services.content_summary_service import _get_summary_llm_config

    key, model, api_version = await _get_summary_llm_config()
    if not key:
        raise RuntimeError("summary_api_key is not configured")

    from google import genai
    from google.genai import types

    client = genai.Client(
        api_key=key,
        http_options={"api_version": api_version},
    )

    def _call():
        return client.models.generate_content(
            model=model,
            contents="VaultStream connectivity test. Reply with OK.",
            config=types.GenerateContentConfig(max_output_tokens=16),
        )

    response = await asyncio.to_thread(_call)
    text = str(getattr(response, "text", "") or "").strip()
    return {
        "target": target,
        "model": model,
        "api_version": api_version,
        "response_present": bool(text or response),
        "preview": text[:120],
    }


async def _discover_openai_compatible_models(target: str) -> list[str]:
    if target not in {"text_llm", "vision_llm"}:
        raise ValueError("target must be text_llm or vision_llm")
    config_service = ConfigService()
    config = (
        await config_service.get_text_llm_config()
        if target == "text_llm"
        else await config_service.get_vision_llm_config()
    )
    if not config.api_key or not config.base_url:
        raise ValueError(f"{target} requires an API Base URL and API Key")
    base_url = config.base_url.rstrip("/")
    parsed = urlparse(base_url)
    if parsed.scheme not in {"http", "https"} or not parsed.netloc:
        raise ValueError("API Base URL must be a valid http(s) URL")
    async with httpx.AsyncClient(timeout=12.0, follow_redirects=False) as client:
        response = await client.get(
            f"{base_url}/models",
            headers={"Authorization": f"Bearer {config.api_key}"},
        )
        response.raise_for_status()
        payload = response.json()
    models = (
        sorted(
            {
                item.get("id", "").strip()
                for item in payload.get("data", [])
                if isinstance(item, dict) and isinstance(item.get("id"), str)
            }
        )
        if isinstance(payload, dict)
        else []
    )
    if not models:
        raise RuntimeError("provider returned no usable models")
    return models


async def _run_platform_parse_test(platform: str, url: str) -> dict[str, Any]:
    from app.adapters import AdapterFactory
    from app.services.platform_parsing import open_configured_adapter

    text = (url or "").strip()
    if not text:
        raise ValueError("url is required")
    if not text.startswith(("http://", "https://")):
        raise ValueError("url must start with http:// or https://")

    platform_enum = Platform(platform)
    detected = AdapterFactory.detect_platform(text)
    if (
        platform_enum != Platform.UNIVERSAL
        and detected != Platform.UNIVERSAL
        and detected != platform_enum
    ):
        raise ValueError(f"url is detected as {detected.value}, not {platform}")

    async with open_configured_adapter(platform_enum) as adapter:
        parsed = await adapter.parse(text)

    archive_metadata = parsed.archive_metadata or {}
    raw_api_response = archive_metadata.get("raw_api_response")
    return {
        "platform": platform,
        "url": text,
        "detected_platform": detected.value,
        "title": parsed.title,
        "content_id": parsed.content_id,
        "clean_url": parsed.clean_url,
        "content_type": parsed.content_type,
        "layout_type": (
            parsed.layout_type.value
            if hasattr(parsed.layout_type, "value")
            else str(parsed.layout_type)
        ),
        "author_name": parsed.author_name,
        "author_id": parsed.author_id,
        "author_avatar_url": parsed.author_avatar_url,
        "author_url": parsed.author_url,
        "cover_url": parsed.cover_url,
        "media_urls": parsed.media_urls or [],
        "media_count": len(parsed.media_urls or []),
        "body_length": len(parsed.body or ""),
        "published_at": (
            parsed.published_at.isoformat() if parsed.published_at else None
        ),
        "stats": parsed.stats or {},
        "source_tags": parsed.source_tags or [],
        "context_data_keys": sorted((parsed.context_data or {}).keys()),
        "rich_payload_keys": sorted((parsed.rich_payload or {}).keys()),
        "archive_metadata_keys": sorted(archive_metadata.keys()),
        "archive_raw_keys": (
            sorted(raw_api_response.keys())
            if isinstance(raw_api_response, dict)
            else []
        ),
    }


class AIDiagnosticsService:
    """Own real provider calls and their persistent diagnostic runs."""

    async def build_capabilities(
        self,
        db: AsyncSession,
    ) -> list[dict[str, Any]]:
        """Build user-facing AI availability from settings and persisted state."""
        text_ready = await _llm_key_configured("text_llm")
        vision_ready = await _llm_key_configured("vision_llm")
        summary_key_ready = _is_configured_value(
            await get_setting_value("summary_api_key")
        )
        summary_enabled = coerce_bool(
            await get_setting_value(
                "enable_auto_summary",
                settings.enable_auto_summary,
            ),
            settings.enable_auto_summary,
        )
        discovery_patrol_enabled = coerce_bool(
            await get_setting_value(
                "enable_discovery_patrol",
                settings.enable_discovery_patrol,
            ),
            settings.enable_discovery_patrol,
        )
        ai_scoring_enabled = coerce_bool(
            await get_setting_value(
                "enable_ai_scoring",
                settings.enable_ai_scoring,
            ),
            settings.enable_ai_scoring,
        )
        embedding_ready = _is_configured_value(
            await get_setting_value("embedding_api_key")
        )
        agent_config = await ConfigService().get_agent_chat_config()
        agent_chat_ready = bool(agent_config.api_key)
        agent_chat_direct = _is_configured_value(
            await get_setting_value("agent_chat_api_key")
        )
        agent_chat_target_ready = agent_chat_ready or text_ready or vision_ready
        semantic_status = await EmbeddingService().get_index_status(session=db)
        indexed_total = int(semantic_status.get("indexed_total") or 0)
        connectivity = await self.latest_connectivity_by_target()

        capabilities: list[dict[str, Any]] = []
        capabilities.append(
            _capability_item(
                "text_llm",
                "文本模型",
                "available" if text_ready else "unavailable",
                "文本 LLM 可用于内容理解、摘要辅助与发现评分。"
                if text_ready
                else "未配置文本 LLM 密钥。",
                issues=[] if text_ready else ["text_llm_api_key 未配置"],
                actions=[] if text_ready else ["配置 text_llm_api_key"],
                details={
                    "configured": text_ready,
                    "connectivity": connectivity.get("text_llm"),
                },
            )
        )
        capabilities.append(
            _capability_item(
                "vision_llm",
                "视觉模型",
                "available" if vision_ready else "unavailable",
                "视觉 LLM 可用于图片理解和多模态内容增强。"
                if vision_ready
                else "未配置视觉 LLM 密钥。",
                issues=[] if vision_ready else ["vision_llm_api_key 未配置"],
                actions=[] if vision_ready else ["配置 vision_llm_api_key"],
                details={
                    "configured": vision_ready,
                    "connectivity": connectivity.get("vision_llm"),
                },
            )
        )
        if not discovery_patrol_enabled:
            patrol_status = "disabled"
            patrol_summary = "发现巡逻已关闭。"
            patrol_issues: list[str] = []
        elif not ai_scoring_enabled:
            patrol_status = "partial"
            patrol_summary = "发现巡逻开启，但 AI 评分写入已关闭。"
            patrol_issues = ["enable_ai_scoring 已关闭"]
        elif text_ready or vision_ready:
            patrol_status = "available"
            patrol_summary = "发现巡逻可写入分数、理由、标签、摘要与可见性。"
            patrol_issues = []
        else:
            patrol_status = "unavailable"
            patrol_summary = "发现巡逻开启，但缺少可用于评分的文本或视觉 LLM。"
            patrol_issues = ["text_llm_api_key 与 vision_llm_api_key 均未配置"]
        capabilities.append(
            _capability_item(
                "discovery_patrol",
                "发现巡逻评分",
                patrol_status,
                patrol_summary,
                issues=patrol_issues,
                actions=(
                    []
                    if patrol_status in {"available", "disabled"}
                    else ["配置 LLM 或开启 AI 评分"]
                ),
                details={
                    "enabled": discovery_patrol_enabled,
                    "ai_scoring_enabled": ai_scoring_enabled,
                    "text_llm": text_ready,
                    "vision_llm": vision_ready,
                },
            )
        )

        if text_ready and vision_ready:
            understanding_status = "available"
            understanding_summary = "文本与视觉模型均已配置，可用于解析增强和复杂内容理解。"
            understanding_issues = []
            understanding_actions = []
        elif text_ready or vision_ready:
            understanding_status = "partial"
            understanding_summary = "已有部分模型配置，部分解析增强能力可用。"
            understanding_issues = ["视觉模型未配置" if text_ready else "文本模型未配置"]
            understanding_actions = ["补齐文本与视觉模型密钥"]
        else:
            understanding_status = "unavailable"
            understanding_summary = "未配置文本或视觉模型，AI 内容理解能力不可用。"
            understanding_issues = ["text_llm_api_key 与 vision_llm_api_key 均未配置"]
            understanding_actions = ["配置文本或视觉 LLM 密钥"]
        capabilities.append(
            _capability_item(
                "content_understanding",
                "内容理解",
                understanding_status,
                understanding_summary,
                issues=understanding_issues,
                actions=understanding_actions,
                details={
                    "text_llm": text_ready,
                    "vision_llm": vision_ready,
                    "connectivity": (
                        (connectivity.get("text_llm") if text_ready else None)
                        or (connectivity.get("vision_llm") if vision_ready else None)
                    ),
                },
            )
        )

        if not summary_enabled:
            summary_status = "disabled"
            summary_message = "自动摘要开关已关闭。"
            summary_actions = ["开启自动摘要"]
        elif summary_key_ready:
            summary_status = "available"
            summary_message = "自动摘要已开启，摘要模型密钥已配置。"
            summary_actions = []
        else:
            summary_status = "unavailable"
            summary_message = "自动摘要已开启，但摘要模型密钥缺失。"
            summary_actions = ["配置摘要模型密钥或关闭自动摘要"]
        capabilities.append(
            _capability_item(
                "summary_generation",
                "摘要生成",
                summary_status,
                summary_message,
                issues=["summary_api_key 未配置"] if summary_status == "unavailable" else [],
                actions=summary_actions,
                details={
                    "enabled": summary_enabled,
                    "summary_key": summary_key_ready,
                    "connectivity": connectivity.get("summary_generation"),
                },
            )
        )

        if not embedding_ready:
            search_status = "unavailable"
            search_summary = "Embedding 密钥未配置，无法生成或更新语义索引。"
            search_actions = ["配置 Embedding 密钥"]
        elif indexed_total <= 0:
            search_status = "pending"
            search_summary = "Embedding 已配置，但当前还没有已索引内容。"
            search_actions = ["运行语义重建或等待新内容入库"]
        else:
            search_status = "available"
            search_summary = f"已有 {indexed_total} 条内容进入语义索引。"
            search_actions = []
        capabilities.append(
            _capability_item(
                "semantic_search",
                "语义搜索",
                search_status,
                search_summary,
                issues=[] if embedding_ready else ["embedding_api_key 未配置"],
                actions=search_actions,
                details={
                    "indexed_total": indexed_total,
                    "connectivity": connectivity.get("semantic_search"),
                    **semantic_status,
                },
            )
        )

        if agent_chat_target_ready:
            capabilities.append(
                _capability_item(
                    "agent",
                    "Agent",
                    "available",
                    "Agent 可使用已配置的 Agent chat 模型；未单独配置时会回退到文本模型，再保留视觉模型 fallback。",
                    details={
                        "agent_chat": agent_chat_target_ready,
                        "agent_chat_direct": agent_chat_direct,
                        "model": agent_config.model,
                        "base_url": agent_config.base_url,
                        "text_llm": text_ready,
                        "vision_llm": vision_ready,
                        "connectivity": connectivity.get("agent_chat"),
                    },
                )
            )
        else:
            capabilities.append(
                _capability_item(
                    "agent",
                    "Agent",
                    "unavailable",
                    "Agent 需要至少一个可用的 Agent chat、文本或视觉 LLM。",
                    issues=["未配置可供 Agent 使用的 LLM 密钥"],
                    actions=["配置 agent_chat_api_key 或 text_llm_api_key"],
                    details={
                        "agent_chat": False,
                        "agent_chat_direct": False,
                        "text_llm": False,
                        "vision_llm": False,
                        "connectivity": None,
                    },
                )
            )

        return capabilities

    async def latest_connectivity_by_target(self) -> dict[str, dict[str, Any]]:
        runs = await get_recent_task_runs("ai_connectivity_test", limit=20)
        latest: dict[str, dict[str, Any]] = {}
        for run in runs:
            target = str(run.get("target") or "")
            if not target or target in latest:
                continue
            latest[target] = {
                "run_id": run.get("run_id"),
                "status": run.get("status"),
                "started_at": run.get("started_at"),
                "finished_at": run.get("finished_at"),
                "error": run.get("error"),
                "result": (
                    run.get("result")
                    if isinstance(run.get("result"), dict)
                    else {}
                ),
            }
        return latest

    @staticmethod
    def normalize_connectivity_target(target: str) -> str:
        normalized = (target or "").strip().lower()
        aliases = {
            "embedding": "semantic_search",
            "semantic": "semantic_search",
            "summary": "summary_generation",
            "text": "text_llm",
            "vision": "vision_llm",
            "agent": "agent_chat",
        }
        normalized = aliases.get(normalized, normalized)
        if normalized not in {
            "agent_chat",
            "text_llm",
            "vision_llm",
            "summary_generation",
            "semantic_search",
        }:
            raise ValueError(
                "target must be agent_chat, text_llm, vision_llm, "
                "summary_generation or semantic_search"
            )
        return normalized

    async def test_connectivity(self, target: str) -> dict[str, Any]:
        normalized = self.normalize_connectivity_target(target)
        run = await record_task_run_started(
            "ai_connectivity_test",
            trigger="manual",
            target=normalized,
        )
        started = time.perf_counter()
        try:
            result = await _run_ai_connectivity_target(normalized)
            elapsed_ms = round((time.perf_counter() - started) * 1000, 2)
            result = {**result, "elapsed_ms": elapsed_ms}
            await record_task_run_success(
                "ai_connectivity_test",
                run["run_id"],
                **result,
            )
            return {
                "run_id": run["run_id"],
                "target": normalized,
                "status": "success",
                "ok": True,
                **result,
            }
        except Exception as exc:
            elapsed_ms = round((time.perf_counter() - started) * 1000, 2)
            await record_task_run_error(
                "ai_connectivity_test",
                run["run_id"],
                exc,
                trigger="manual",
                target=normalized,
                elapsed_ms=elapsed_ms,
            )
            return {
                "run_id": run["run_id"],
                "target": normalized,
                "status": "error",
                "ok": False,
                "error": str(exc)[:1000],
                "elapsed_ms": elapsed_ms,
            }

    async def discover_models(self, target: str) -> dict[str, Any]:
        normalized = (target or "").strip().lower()
        return {
            "target": normalized,
            "models": await _discover_openai_compatible_models(normalized),
        }

    @staticmethod
    def normalize_parse_test_platform(platform: str) -> str:
        normalized = (platform or "").strip().lower()
        aliases = {
            "x": "twitter",
            "twitter_x": "twitter",
            "telegram_channel": "telegram",
        }
        normalized = aliases.get(normalized, normalized)
        valid = {item.value for item in Platform}
        if normalized not in valid:
            raise ValueError("platform is not supported")
        return normalized

    async def test_platform_parse(
        self,
        platform: str,
        url: str,
    ) -> dict[str, Any]:
        normalized = self.normalize_parse_test_platform(platform)
        run = await record_task_run_started(
            "platform_parse_test",
            trigger="manual",
            platform=normalized,
            url=url,
        )
        started = time.perf_counter()
        try:
            result = await _run_platform_parse_test(normalized, url)
            elapsed_ms = round((time.perf_counter() - started) * 1000, 2)
            result = {**result, "elapsed_ms": elapsed_ms}
            await record_task_run_success(
                "platform_parse_test",
                run["run_id"],
                **result,
            )
            return {
                "run_id": run["run_id"],
                "platform": normalized,
                "status": "success",
                "ok": True,
                **result,
            }
        except ValueError as exc:
            elapsed_ms = round((time.perf_counter() - started) * 1000, 2)
            await record_task_run_error(
                "platform_parse_test",
                run["run_id"],
                exc,
                trigger="manual",
                platform=normalized,
                url=url,
                elapsed_ms=elapsed_ms,
            )
            raise
        except Exception as exc:
            elapsed_ms = round((time.perf_counter() - started) * 1000, 2)
            await record_task_run_error(
                "platform_parse_test",
                run["run_id"],
                exc,
                trigger="manual",
                platform=normalized,
                url=url,
                elapsed_ms=elapsed_ms,
            )
            return {
                "run_id": run["run_id"],
                "platform": normalized,
                "status": "error",
                "ok": False,
                "error": str(exc)[:1000],
                "elapsed_ms": elapsed_ms,
            }


def get_ai_diagnostics_service() -> AIDiagnosticsService:
    return AIDiagnosticsService()
