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


@pytest.mark.asyncio
async def test_processing_status_includes_failure_payloads(client, db_session):
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

    db_session.add(
        ContentQueueItem(
            content_id=content.id,
            rule_id=rule.id,
            bot_chat_id=chat.id,
            target_platform="telegram",
            target_id=chat.chat_id,
            status=QueueItemStatus.FAILED,
            attempt_count=3,
            max_attempts=3,
            last_error="telegram rate limited",
            last_error_type="rate_limit",
            last_error_at=datetime(2026, 6, 5, 10, 5, 0),
        )
    )
    await db_session.commit()

    response = await client.get(f"/api/v1/contents/{content.id}/processing-status")

    assert response.status_code == 200
    stages = {stage["key"]: stage for stage in response.json()["stages"]}
    embedding_failures = stages["semantic_index"]["details"]["failures"]
    distribution_failures = stages["distribution"]["details"]["failures"]

    assert stages["patrol"]["status"] == "disabled"
    assert stages["patrol"]["details"]["discovery_state"] is None

    assert stages["semantic_index"]["status"] == "failed"
    assert embedding_failures[0]["failure_reason"] == "embedding api unavailable"
    assert embedding_failures[0]["retry_count"] == 2

    assert stages["distribution"]["status"] == "failed"
    assert distribution_failures[0]["last_error"] == "telegram rate limited"
    assert distribution_failures[0]["last_error_type"] == "rate_limit"
    assert distribution_failures[0]["target_platform"] == "telegram"
