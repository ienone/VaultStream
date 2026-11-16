"""Local account inventory. Explicit checks and scheduled jobs verify the remote login."""
from sqlalchemy.ext.asyncio import AsyncSession

from app.adapters.favorites import FAVORITES_CAPABILITIES
from app.services.browser_auth_service import browser_auth_service
from app.services.config_service import ConfigService
from app.services.account_auth_state import account_login
from app.utils.platform_names import platform_name


async def list_platform_accounts(db: AsyncSession) -> dict:
    config = await ConfigService.snapshot(db)
    platforms = []
    for platform in ("zhihu", "xiaohongshu", "twitter", "weibo", "bilibili"):
        cookie = await config.get_platform_cookie_string(platform)
        observation = await config.get_value(f"account_auth:{platform}")
        platforms.append({
            "platform": platform,
            "label": platform_name(platform),
            "login": account_login(platform, cookie, observation),
            "qr_login": platform in browser_auth_service.qr_platforms,
            "favorites_supported": platform in FAVORITES_CAPABILITIES,
        })
    return {"platforms": platforms}
