"""
应用常量定义
包含平台类型、内容类型等枚举常量
"""
from enum import Enum


class Platform(str, Enum):
    """分发平台类型"""
    TELEGRAM = "telegram"
    QQ = "qq"


class ContentType(str, Enum):
    """内容类型枚举"""
    # 基于现有数据库 content_id 值的映射
    # content_id=6: Bilibili视频
    # content_id=8: 推文
    # content_id=9: Zhihu内容
    BILIBILI_VIDEO = "6"
    TWEET = "8"
    ZHIHU = "9"


# 平台常量列表
SUPPORTED_PLATFORMS = [Platform.TELEGRAM.value, Platform.QQ.value]

# 测试用内容ID列表（用于目标预览）
# 注意：这些是整数值，对应数据库中的content_id
PREVIEW_CONTENT_IDS = [6, 8, 9]

# Render Config Presets (Raw data to avoid circular imports with schemas)
DEFAULT_RENDER_CONFIG_PRESETS = [
    {
        "id": "minimal",
        "name": "Minimal",
        "description": "Minimal display with title and link only",
        "is_builtin": True,
        "config": {
            "show_platform_id": False,
            "show_title": True,
            "show_tags": False,
            "author_mode": "none",
            "content_mode": "hidden",
            "media_mode": "none",
            "link_mode": "clean",
            "header_text": "",
            "footer_text": ""
        }
    },
    {
        "id": "standard",
        "name": "Standard",
        "description": "Balanced display with summary and media",
        "is_builtin": True,
        "config": {
            "show_platform_id": True,
            "show_title": True,
            "show_tags": False,
            "author_mode": "name",
            "content_mode": "summary",
            "media_mode": "auto",
            "link_mode": "clean",
            "header_text": "",
            "footer_text": ""
        }
    },
    {
        "id": "detailed",
        "name": "Detailed",
        "description": "Full display with all fields and media",
        "is_builtin": True,
        "config": {
            "show_platform_id": True,
            "show_title": True,
            "show_tags": True,
            "author_mode": "full",
            "content_mode": "full",
            "media_mode": "all",
            "link_mode": "original",
            "header_text": "📰 {{date}}",
            "footer_text": "Powered by VaultStream"
        }
    },
    {
        "id": "media_only",
        "name": "Media Only",
        "description": "Media-focused with minimal text",
        "is_builtin": True,
        "config": {
            "show_platform_id": False,
            "show_title": True,
            "show_tags": False,
            "author_mode": "none",
            "content_mode": "hidden",
            "media_mode": "all",
            "link_mode": "none",
            "header_text": "",
            "footer_text": ""
        }
    },
]
