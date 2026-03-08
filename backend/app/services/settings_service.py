from typing import Any

from pydantic import SecretStr

from app.models import SystemSetting
from app.core.db_adapter import AsyncSessionLocal
from app.utils.sensitive_display import as_configured_placeholder, is_sensitive_setting_key

# Simple in-memory cache
_SETTINGS_CACHE = {}


async def get_setting_value(key: str, default: Any = None) -> Any:
    """
    从数据库中读取配置项（含内存缓存）。
    所有配置均存储于 DB，不再从 .env 回退。
    """
    if key in _SETTINGS_CACHE:
        val = _SETTINGS_CACHE[key]
    else:
        async with AsyncSessionLocal() as db:
            from app.repositories import SystemRepository
            repo = SystemRepository(db)
            setting = await repo.get_setting(key)
            
            if setting:
                _SETTINGS_CACHE[key] = setting.value
                val = setting.value
            else:
                val = default

    # Handle string boolean values like "true" or "false"
    if isinstance(val, str):
        if val.lower() == "true":
            return True
        elif val.lower() == "false":
            return False
    return val


async def set_setting_value(key: str, value: Any, category: str = "general", description: str = None) -> SystemSetting:
    """
    Set a system setting value and update cache.
    """
    async with AsyncSessionLocal() as db:
        from app.repositories import SystemRepository
        repo = SystemRepository(db)
        setting = await repo.upsert_setting(
            key=key, 
            value=value, 
            category=category, 
            description=description
        )
        
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
        from app.repositories import SystemRepository
        repo = SystemRepository(db)
        settings_list = await repo.list_settings()
        
        for setting in settings_list:
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
        from app.repositories import SystemRepository
        repo = SystemRepository(db)
        setting = await repo.get_setting(key)
        
        if setting:
            await repo.delete_setting(setting)
            await db.commit()
            
            # Remove from cache
            if key in _SETTINGS_CACHE:
                del _SETTINGS_CACHE[key]
            return True
            
        return False


async def list_settings_values(category: str = None) -> list[dict[str, Any]]:
    """
    返回数据库中存储的所有配置项（可按 category 过滤）。
    不再从 .env 注入虚拟配置——所有设置均通过 UI 保存到 DB 管理。
    """
    async with AsyncSessionLocal() as db:
        from app.repositories import SystemRepository
        repo = SystemRepository(db)
        settings_list = await repo.list_settings(category=category)

        # 对敏感字段做统一脱敏回显，避免在设置列表里暴露明文。
        response_items: list[dict[str, Any]] = []
        for setting in settings_list:
            value = setting.value
            if is_sensitive_setting_key(setting.key):
                value = as_configured_placeholder(setting.value, source="db") or ""

            response_items.append({
                "key": setting.key,
                "value": value,
                "category": setting.category,
                "description": setting.description,
                "updated_at": setting.updated_at,
            })

        return response_items


def invalidate_setting_cache(key: str):
    if key in _SETTINGS_CACHE:
        del _SETTINGS_CACHE[key]
