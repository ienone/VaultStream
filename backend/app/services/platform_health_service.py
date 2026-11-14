"""Local account inventory. Explicit checks and scheduled jobs verify the remote login."""
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.adapters.favorites import FAVORITES_CAPABILITIES
from app.models import NotificationMessage
from app.services.browser_auth_service import browser_auth_service
from app.services.config_service import ConfigService
from app.utils.platform_names import platform_name


async def list_platform_accounts(db: AsyncSession) -> dict:
    config = await ConfigService.snapshot(db)
    invalid = set(await db.scalars(select(NotificationMessage.source_id).where(
        NotificationMessage.source_type == "platform_auth",
        NotificationMessage.payload["status"].as_string() == "invalid",
    )))
    platforms = []
    for platform in ("zhihu", "xiaohongshu", "twitter", "weibo", "bilibili"):
        configured = bool(await config.get_platform_cookie_string(platform))
        platforms.append({
            "platform": platform,
            "label": platform_name(platform),
            "login": "not_configured" if not configured else "invalid" if platform in invalid else "configured",
            "qr_login": platform in browser_auth_service.qr_platforms,
            "favorites_supported": platform in FAVORITES_CAPABILITIES,
        })
    return {"platforms": platforms}
