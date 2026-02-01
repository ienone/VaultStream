from typing import Any
from sqlalchemy import select
from app.models import SystemSetting
from app.core.db_adapter import AsyncSessionLocal

# Default values
DEFAULT_UNIVERSAL_PROMPT = """
Analyze the web page content. 
1. Extract the main article/post content, ignoring navigation, sidebars, ads, and footers.
2. Extract metadata like author, publish date, and tags.
3. CRITICAL: Look for interaction metrics (views, likes, comments, shares) usually found at the top or bottom of the post.
4. Keep the 'content' field in clean Markdown format.
5. Detect content type: 'article' for long-form text, 'video' if main content is video, 'gallery' if image-focused, 'audio' for podcasts.
6. Extract video_url if there's a main video element, audio_url if there's a podcast/audio player.
"""

# Simple in-memory cache
_SETTINGS_CACHE = {}

async def get_setting_value(key: str, default: Any = None) -> Any:
    """
    Get a system setting value, with caching.
    """
    if key in _SETTINGS_CACHE:
        return _SETTINGS_CACHE[key]
    
    async with AsyncSessionLocal() as db:
        result = await db.execute(select(SystemSetting).where(SystemSetting.key == key))
        setting = result.scalar_one_or_none()
        
        if setting:
            _SETTINGS_CACHE[key] = setting.value
            return setting.value
        
        # Return default if provided, otherwise check for known defaults
        if default is not None:
            return default
            
        if key == "universal_adapter_prompt":
            return DEFAULT_UNIVERSAL_PROMPT
            
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
        return setting

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

async def list_settings_values(category: str = None) -> list[SystemSetting]:
    """
    List all settings, optionally filtered by category.
    """
    async with AsyncSessionLocal() as db:
        query = select(SystemSetting)
        if category:
            query = query.where(SystemSetting.category == category)
        result = await db.execute(query)
        return result.scalars().all()

def invalidate_setting_cache(key: str):
    if key in _SETTINGS_CACHE:
        del _SETTINGS_CACHE[key]
