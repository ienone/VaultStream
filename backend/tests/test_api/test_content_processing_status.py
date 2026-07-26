from datetime import datetime
from uuid import uuid4

import pytest

from app.models import (
    BotChat,
    BotChatType,
    BotConfig,
    BotConfigPlatform,
    Content,
    ContentEmbedding,
    ContentQueueItem,
    ContentStatus,
    DistributionRule,
    Platform,
    QueueItemStatus,
)
from app.services.config_service import (
    AIConfig,
    AgentChatConfig,
    ArchiveMediaConfig,
    EmbeddingAIConfig,
    LLMConfig,
    SummaryAIConfig,
)


def _ai_config_without_runtime_keys() -> AIConfig:
    return AIConfig(
        summary=SummaryAIConfig(
            enabled=True,
            api_key=None,
            model="summary-model",
            api_version="v1beta",
        ),
        embedding=EmbeddingAIConfig(
            api_key=None,
            model="gemini-embedding-2",
            output_dimensionality=1536,
            search_max_rows=5000,
        ),
        agent_chat=AgentChatConfig(
            api_key=None,
            model="agent-model",
            base_url=None,
        ),
        text_llm=LLMConfig(api_key=None, model="text-model", base_url=None),
        vision_llm=LLMConfig(api_key=None, model="vision-model", base_url=None),
    )


def _ai_config_with_runtime_keys() -> AIConfig:
    return AIConfig(
        summary=SummaryAIConfig(
            enabled=True,
            api_key="summary-key",
            model="summary-model",
            api_version="v1beta",
        ),
        embedding=EmbeddingAIConfig(
            api_key="embedding-key",
            model="gemini-embedding-2",
            output_dimensionality=1536,
            search_max_rows=5000,
        ),
        agent_chat=AgentChatConfig(api_key=None, model="agent-model", base_url=None),
        text_llm=LLMConfig(api_key="text-key", model="text-model", base_url=None),
        vision_llm=LLMConfig(api_key=None, model="vision-model", base_url=None),
    )


@pytest.mark.asyncio
async def test_processing_status_reports_partial_semantic_index(client, db_session, monkeypatch):
    """部分成功必须表达为 partial，不能被压成 success 或 failed。"""

    async def _fake_ai_config(self):
        return _ai_config_with_runtime_keys()

    async def _fake_archive_config(self):
        return ArchiveMediaConfig(
            enabled=True,
            images_enabled=True,
            videos_enabled=True,
            image_webp_quality=80,
            image_max_count=None,
            video_max_count=2,
            video_max_bytes=1024,
        )

    monkeypatch.setattr("app.routers.contents.ConfigService.get_ai_config", _fake_ai_config)
    monkeypatch.setattr(
        "app.routers.contents.ConfigService.get_archive_media_config",
        _fake_archive_config,
    )

    suffix = uuid4().hex
    content = Content(
        platform=Platform.ZHIHU,
        url=f"https://www.zhihu.com/answer/{suffix}",
        canonical_url=f"https://www.zhihu.com/answer/{suffix}",
        status=ContentStatus.PARSE_SUCCESS,
        title="Partial semantic index",
        summary="已有摘要",
    )
    db_session.add(content)
    await db_session.flush()

    db_session.add_all(
        [
            ContentEmbedding(content_id=content.id, chunk_index=0, index_status="indexed"),
            ContentEmbedding(
                content_id=content.id,
                chunk_index=1,
                index_status="failed",
                failure_reason="embedding timeout",
                retry_count=1,
            ),
        ]
    )
    await db_session.commit()

    response = await client.get(f"/api/v1/contents/{content.id}/processing-status")
    assert response.status_code == 200
    payload = response.json()
    stages = {stage["key"]: stage for stage in payload["stages"]}

    semantic = stages["semantic_index"]
    assert semantic["state"] == "partial"
    assert semantic["detail_state"] == "partial"
    assert semantic["completed_units"] == 1
    assert semantic["total_units"] == 2
    assert len(semantic["failures"]) == 1
    assert semantic["failures_total"] == 1
    assert semantic["failures_truncated"] is False
    assert semantic["failures"][0]["retryable"] is True

    # 密钥齐备时才提供重试动作，且必须标记为有外部副作用
    kinds = {action["kind"] for action in semantic["actions"]}
    assert kinds == {"rebuild_semantic_index", "retry_semantic_chunk"}
    assert all(action["external_effect"] is True for action in semantic["actions"])
    retry_chunk = next(a for a in semantic["actions"] if a["kind"] == "retry_semantic_chunk")
    assert retry_chunk["target_ids"] == [semantic["failures"][0]["id"]]

    # partial 优先于 success，整体状态必须暴露未完成
    assert payload["state"] == "partial"

    # 已有摘要时动作是"重新生成"，仍然只在摘要阶段出现一次
    summary_actions = stages["summary"]["actions"]
    assert [action["kind"] for action in summary_actions] == ["generate_summary"]
    assert summary_actions[0]["label"] == "重新生成摘要"


@pytest.mark.asyncio
async def test_processing_status_includes_failure_payloads(client, db_session, monkeypatch):
    async def _fake_ai_config(self):
        return _ai_config_without_runtime_keys()

    async def _fake_archive_config(self):
        return ArchiveMediaConfig(
            enabled=True,
            images_enabled=True,
            videos_enabled=True,
            image_webp_quality=80,
            image_max_count=None,
            video_max_count=2,
            video_max_bytes=1024,
        )

    monkeypatch.setattr(
        "app.routers.contents.ConfigService.get_ai_config",
        _fake_ai_config,
    )
    monkeypatch.setattr(
        "app.routers.contents.ConfigService.get_archive_media_config",
        _fake_archive_config,
    )

    suffix = uuid4().hex
    content = Content(
        platform=Platform.ZHIHU,
        url=f"https://www.zhihu.com/question/{suffix}",
        canonical_url=f"https://www.zhihu.com/question/{suffix}",
        clean_url=f"https://www.zhihu.com/question/{suffix}",
        status=ContentStatus.PARSE_SUCCESS,
        title="Processing status payload test",
    )
    db_session.add(content)
    await db_session.flush()

    db_session.add(
        ContentEmbedding(
            content_id=content.id,
            chunk_index=0,
            index_status="failed",
            failure_reason="embedding api unavailable",
            retry_count=2,
            last_attempted_at=datetime(2026, 6, 5, 10, 0, 0),
        )
    )

    rule = DistributionRule(
        name=f"processing-status-rule-{suffix}",
        match_conditions={"tags": []},
    )
    bot = BotConfig(platform=BotConfigPlatform.TELEGRAM, name=f"bot-{suffix}")
    db_session.add_all([rule, bot])
    await db_session.flush()

    chat = BotChat(
        bot_config_id=bot.id,
        chat_id=f"chat-{suffix}",
        chat_type=BotChatType.CHANNEL,
        title="Test Channel",
        is_push_target=True,
    )
    db_session.add(chat)
    await db_session.flush()

    permanent_rule = DistributionRule(
        name=f"processing-status-permanent-rule-{suffix}",
        match_conditions={"tags": []},
    )
    db_session.add(permanent_rule)
    await db_session.flush()

    retryable_item = ContentQueueItem(
        content_id=content.id,
        rule_id=rule.id,
        bot_chat_id=chat.id,
        target_platform="telegram",
        target_id=chat.chat_id,
        status=QueueItemStatus.FAILED,
        attempt_count=2,
        max_attempts=3,
        last_error="telegram rate limited",
        last_error_type="rate_limit",
        last_error_at=datetime(2026, 6, 5, 10, 5, 0),
    )
    permanent_item = ContentQueueItem(
        content_id=content.id,
        rule_id=permanent_rule.id,
        bot_chat_id=chat.id,
        target_platform="telegram",
        target_id=f"{chat.chat_id}-already-pushed",
        status=QueueItemStatus.FAILED,
        attempt_count=0,
        max_attempts=3,
        last_error="Already pushed (dedupe)",
        last_error_type="already_pushed_dedupe",
        last_error_at=datetime(2026, 6, 5, 10, 6, 0),
    )
    db_session.add_all([retryable_item, permanent_item])
    await db_session.commit()

    response = await client.get(f"/api/v1/contents/{content.id}/processing-status")

    assert response.status_code == 200
    payload = response.json()
    stages = {stage["key"]: stage for stage in payload["stages"]}
    embedding_failures = stages["semantic_index"]["failures"]
    distribution_failures = stages["distribution"]["failures"]

    # 存在失败阶段时整体状态必须是 failed
    assert payload["state"] == "failed"

    # 没有远端归档媒体：不适用，而不是成功
    assert stages["archive_media"]["state"] == "not_applicable"
    assert stages["archive_media"]["detail_state"] == "no_media"
    assert stages["archive_media"]["details"]["enabled"] is True
    assert stages["archive_media"]["details"]["video_max_count"] == 2
    assert stages["archive_media"]["details"]["video_max_bytes"] == 1024

    # 非发现流内容不适用巡逻评分，且不提供任何可执行动作
    assert stages["patrol"]["state"] == "not_applicable"
    assert stages["patrol"]["detail_state"] == "not_discovery"
    assert stages["patrol"]["details"]["discovery_state"] is None
    assert stages["patrol"]["issues"] == []
    assert stages["patrol"]["actions"] == []

    # 密钥缺失属于 blocked 的前置条件，但已有失败分块时状态仍是 failed；
    # 此时只能给出配置建议，不能提供会立即再次失败的重试动作。
    assert stages["semantic_index"]["state"] == "failed"
    assert stages["semantic_index"]["detail_state"] == "failed"
    assert stages["semantic_index"]["issues"] == ["embedding_api_key 未配置"]
    assert stages["semantic_index"]["hints"] == ["配置 Embedding 密钥"]
    assert stages["semantic_index"]["actions"] == []
    assert embedding_failures[0]["reason"] == "embedding api unavailable"
    assert embedding_failures[0]["retry_count"] == 2
    assert embedding_failures[0]["reference"] == "分块 0"

    # 分发失败：提供 typed 重试动作，并标记外部副作用
    assert stages["distribution"]["state"] == "failed"
    assert stages["distribution"]["detail_state"] == "failed"
    assert stages["distribution"]["issues"] == ["存在失败或被过滤的分发队列项"]
    failures_by_type = {failure["error_type"]: failure for failure in distribution_failures}
    retryable_failure = failures_by_type["rate_limit"]
    permanent_failure = failures_by_type["already_pushed_dedupe"]
    retry_action = stages["distribution"]["actions"][0]
    assert retry_action["kind"] == "retry_distribution_item"
    assert retry_action["external_effect"] is True
    assert retry_action["target_ids"] == [retryable_failure["id"]]
    assert retryable_failure["reason"] == "telegram rate limited"
    assert retryable_failure["reference"] == f"telegram:{chat.chat_id}"
    assert retryable_failure["retry_count"] == 2
    assert retryable_failure["max_retries"] == 3
    assert retryable_failure["retryable"] is True
    assert permanent_failure["retryable"] is False
    assert permanent_failure["id"] not in retry_action["target_ids"]
    assert stages["distribution"]["failures_total"] == 2
    assert stages["distribution"]["failures_truncated"] is False


@pytest.mark.asyncio
async def test_summary_stage_does_not_treat_rag_chunks_as_summary(
    client,
    db_session,
    monkeypatch,
):
    async def _fake_ai_config(self):
        return _ai_config_with_runtime_keys()

    async def _fake_archive_config(self):
        return ArchiveMediaConfig(
            enabled=False,
            images_enabled=False,
            videos_enabled=False,
            image_webp_quality=80,
            image_max_count=None,
            video_max_count=2,
            video_max_bytes=1024,
        )

    monkeypatch.setattr("app.routers.contents.ConfigService.get_ai_config", _fake_ai_config)
    monkeypatch.setattr(
        "app.routers.contents.ConfigService.get_archive_media_config",
        _fake_archive_config,
    )

    suffix = uuid4().hex
    content = Content(
        platform=Platform.ZHIHU,
        url=f"https://www.zhihu.com/answer/{suffix}",
        canonical_url=f"https://www.zhihu.com/answer/{suffix}",
        status=ContentStatus.PARSE_SUCCESS,
        title="Chunks are not a summary",
        summary=None,
        rich_payload={"chunks": [{"text": "RAG chunk"}]},
    )
    db_session.add(content)
    await db_session.commit()

    response = await client.get(f"/api/v1/contents/{content.id}/processing-status")
    assert response.status_code == 200
    summary = next(stage for stage in response.json()["stages"] if stage["key"] == "summary")
    assert summary["state"] == "pending"
    assert summary["detail_state"] == "pending"
    assert summary["details"]["summary_present"] is False
    assert summary["details"]["chunks_present"] is True
    assert [action["kind"] for action in summary["actions"]] == ["generate_summary"]
