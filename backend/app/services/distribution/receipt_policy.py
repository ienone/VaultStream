"""Keep QQ Agent receipts separate from automatic distribution to their sender."""
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models import AgentRun, BotChat, ContentSource


EXPLICIT_PUSH = "explicit_push"


async def has_qq_agent_receipt(
    db: AsyncSession, content_id: int, bot_chat: BotChat, target_id: str,
) -> bool:
    if bot_chat.platform_type != "qq" or not target_id.startswith("private:"):
        return False
    user_id = target_id.removeprefix("private:")
    namespace = f"qq-{bot_chat.bot_config_id}-{user_id}"
    rows = (await db.execute(
        select(ContentSource.client_context, AgentRun.session_id)
        .join(AgentRun, AgentRun.id == ContentSource.client_context["run_id"].as_string())
        .where(ContentSource.content_id == content_id, ContentSource.source == "qq_bot")
    )).all()
    for origin, session_id in rows:
        if (isinstance(origin, dict)
                and origin.get("channel") == "qq_bot"
                and origin.get("capture_via") == "agent"
                and origin.get("bot_config_id") == bot_chat.bot_config_id
                and origin.get("user_id") == user_id
                and origin.get("session_id") == session_id
                and isinstance(origin.get("source_ref"), str) and origin["source_ref"]
                and (session_id == namespace or session_id.startswith(namespace + "-"))):
            return True
    return False
