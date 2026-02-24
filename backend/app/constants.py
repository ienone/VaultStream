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
    BILIBILI_VIDEO = "bilibili_video"
    TWEET = "tweet"
    ZHIHU = "zhihu"


# 平台常量列表
SUPPORTED_PLATFORMS = [Platform.TELEGRAM.value, Platform.QQ.value]

# Render Config Presets (Raw data to avoid circular imports with schemas)
DEFAULT_RENDER_CONFIG_PRESETS = [
    {
        "id": "minimal",
        "name": "极简",
        "description": "仅显示标题与链接，适合精简推送",
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
        "name": "标准",
        "description": "平衡展示摘要与媒体，适合日常使用",
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
        "name": "详细",
        "description": "完整展示字段与媒体，信息最丰富",
        "is_builtin": True,
        "config": {
            "show_platform_id": True,
            "show_title": True,
            "show_tags": True,
            "author_mode": "full",
            "content_mode": "full",
            "media_mode": "all",
            "link_mode": "original",
            "header_text": "日期 {{date}}",
            "footer_text": ""
        }
    },
    {
        "id": "media_only",
        "name": "媒体优先",
        "description": "以媒体为主，文本最少",
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
