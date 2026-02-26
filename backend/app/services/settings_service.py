import os
from datetime import datetime
from typing import Any

from pydantic import SecretStr
from sqlalchemy import select

from app.models import SystemSetting
from app.core.db_adapter import AsyncSessionLocal

# Simple in-memory cache
_SETTINGS_CACHE = {}


def _secret_value(val) -> str | None:
    """从 SecretStr 或普通字符串中安全提取值"""
    if val is None:
        return None
    if isinstance(val, SecretStr):
        return val.get_secret_value() or None
    return val or None


async def get_setting_value(key: str, default: Any = None) -> Any:
    """
    Get a system setting value, with caching.
    Falls back to .env configuration if not present in the DB.
    """
    if key in _SETTINGS_CACHE:
        return _SETTINGS_CACHE[key]
    
    async with AsyncSessionLocal() as db:
        result = await db.execute(select(SystemSetting).where(SystemSetting.key == key))
        setting = result.scalar_one_or_none()
        
        if setting:
            _SETTINGS_CACHE[key] = setting.value
            return setting.value
            
    # Check fallback map from .env
    from app.core.config import settings
    fallback_map = {
        "text_llm_api_base": settings.text_llm_base_url,
        "text_llm_api_key": _secret_value(settings.text_llm_api_key),
        "text_llm_model": settings.text_llm_model,
        "vision_llm_api_base": settings.vision_llm_base_url,
        "vision_llm_api_key": _secret_value(settings.vision_llm_api_key),
        "vision_llm_model": settings.vision_llm_model,
        "enable_auto_summary": settings.enable_auto_summary,
        "enable_archive_media_processing": settings.enable_archive_media_processing,
        "archive_image_webp_quality": settings.archive_image_webp_quality,
        "archive_image_max_count": settings.archive_image_max_count,
        "telegram_admin_ids": settings.telegram_admin_ids,
        "telegram_whitelist_ids": settings.telegram_whitelist_ids,
        "telegram_blacklist_ids": settings.telegram_blacklist_ids,
        "http_proxy": settings.http_proxy,
        "https_proxy": settings.https_proxy,
        "bilibili_bili_jct": _secret_value(settings.bilibili_bili_jct),
        "bilibili_buvid3": _secret_value(settings.bilibili_buvid3),
    }
    
    if key in fallback_map:
        val = fallback_map[key]
        if val is not None:
            return val
        
    # Return default if provided, otherwise check for known defaults
    if default is not None:
        return default
        
    return None


async def set_setting_value(key: str, value: Any, category: str = "general", description: str = None) -> SystemSetting:
    """
    Set a system setting value and update cache.
    """
    async with AsyncSessionLocal() as db:
        result = await db.execute(select(SystemSetting).where(SystemSetting.key == key))
        setting = result.scalar_one_or_none()
        
        if setting:
            setting.value = value
            if description:
                setting.description = description
            if category:
                setting.category = category
        else:
            setting = SystemSetting(
                key=key,
                value=value,
                category=category,
                description=description
            )
            db.add(setting)
        
        await db.commit()
        await db.refresh(setting)
        
        # Update cache
        _SETTINGS_CACHE[key] = value

        # 同步更新全局 settings 对象（如果存在对应字段）
        from app.core.config import settings
        if hasattr(settings, key):
            from pydantic import SecretStr
            # 处理 SecretStr 包装
            field_type = settings.__annotations__.get(key)
            if field_type == SecretStr or "SecretStr" in str(field_type):
                setattr(settings, key, SecretStr(str(value)))
            else:
                setattr(settings, key, value)
        
        return setting


async def load_all_settings_to_memory():
    """
    Load all settings from database into memory cache and settings singleton object on backend startup.
    This ensures API keys, cookies, and other configurations stored in the DB persist across restarts.
    """
    from app.core.config import settings
    from pydantic import SecretStr

    async with AsyncSessionLocal() as db:
        result = await db.execute(select(SystemSetting))
        for setting in result.scalars().all():
            key = setting.key
            value = setting.value
            
            # 1. Update basic cache
            _SETTINGS_CACHE[key] = value

            # 2. Synchronize to global settings object
            if hasattr(settings, key):
                field_type = settings.__annotations__.get(key)
                if field_type == SecretStr or "SecretStr" in str(field_type):
                    setattr(settings, key, SecretStr(str(value)) if value else None)
                else:
                    setattr(settings, key, value)

async def delete_setting_value(key: str) -> bool:
    """
    Delete a system setting.
    """
    async with AsyncSessionLocal() as db:
        result = await db.execute(select(SystemSetting).where(SystemSetting.key == key))
        setting = result.scalar_one_or_none()
        
        if setting:
            await db.delete(setting)
            await db.commit()
            
            # Remove from cache
            if key in _SETTINGS_CACHE:
                del _SETTINGS_CACHE[key]
            return True
            
        return False


def _resolve_env_display(env_val, is_secret: bool = False):
    """将环境变量值转换为前端可展示的虚拟设置值。

    - SecretStr 或标记为 is_secret 的值 → 掩码字符串
    - 空值 → None (表示跳过)
    - 其余 → 原值
    """
    if env_val is None:
        return None

    if isinstance(env_val, SecretStr):
        raw = env_val.get_secret_value()
        return "*** [Configured via .env] ***" if raw else None

    if is_secret:
        return "*** [Configured via .env] ***" if env_val else None

    # 非机密：空字符串也返回（前端需要显示编辑框）
    return env_val


async def list_settings_values(category: str = None) -> list[SystemSetting]:
    """
    List all settings, optionally filtered by category.
    Merges in environmental variable configs for platforms so they show as configured.
    """
    from app.core.config import settings as env_settings
    
    async with AsyncSessionLocal() as db:
        query = select(SystemSetting)
        if category:
            query = query.where(SystemSetting.category == category)
        result = await db.execute(query)
        db_settings = list(result.scalars().all())
        
    db_keys = {s.key for s in db_settings}
    
    # 环境变量映射：(env_value, category)
    env_mappings: dict[str, tuple[Any, str]] = {
        # --- 平台凭证 ---
        "bilibili_cookie": (env_settings.bilibili_sessdata, "platform"),
        "weibo_cookie": (env_settings.weibo_cookie, "platform"),
        "xiaohongshu_cookie": (env_settings.xiaohongshu_cookie, "platform"),
        "zhihu_cookie": (env_settings.zhihu_cookie, "platform"),
        "bilibili_bili_jct": (env_settings.bilibili_bili_jct, "platform"),
        "bilibili_buvid3": (env_settings.bilibili_buvid3, "platform"),
        # --- LLM ---
        "text_llm_api_base": (env_settings.text_llm_base_url, "llm"),
        "text_llm_api_key": (env_settings.text_llm_api_key, "llm"),
        "text_llm_model": (env_settings.text_llm_model, "llm"),
        "vision_llm_api_base": (env_settings.vision_llm_base_url, "llm"),
        "vision_llm_api_key": (env_settings.vision_llm_api_key, "llm"),
        "vision_llm_model": (env_settings.vision_llm_model, "llm"),
        # --- 网络 ---
        "http_proxy": (env_settings.http_proxy, "network"),
        "https_proxy": (env_settings.https_proxy, "network"),
        # --- Bot 权限 ---
        "telegram_admin_ids": (env_settings.telegram_admin_ids, "bot"),
        "telegram_whitelist_ids": (env_settings.telegram_whitelist_ids, "bot"),
        "telegram_blacklist_ids": (env_settings.telegram_blacklist_ids, "bot"),
        # --- 存储与媒体 ---
        "enable_archive_media_processing": (env_settings.enable_archive_media_processing, "storage"),
        "archive_image_webp_quality": (env_settings.archive_image_webp_quality, "storage"),
        "archive_image_max_count": (env_settings.archive_image_max_count, "storage"),
        # --- 摘要生成 ---
        "enable_auto_summary": (env_settings.enable_auto_summary, "llm"),
    }

    virtual_settings: list[SystemSetting] = []
    now = datetime.now()

    for key, (env_val, cat) in env_mappings.items():
        if category and category != cat:
            continue
        if key in db_keys:
            continue

        display_val = _resolve_env_display(env_val)
        if display_val is None:
            continue

        virtual_settings.append(
            SystemSetting(
                key=key,
                value=display_val,
                category=cat,
                description="环境变量配置",
                updated_at=now,
            )
        )

    return db_settings + virtual_settings


def invalidate_setting_cache(key: str):
    if key in _SETTINGS_CACHE:
        del _SETTINGS_CACHE[key]
