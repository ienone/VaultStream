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

# 渲染配置预设（原始数据，以避免与 schemas 产生循环导入）
DEFAULT_RENDER_CONFIG_PRESETS = [
    {"id": "summary", "name": "图文摘要", "description": "短正文或摘要，配一张代表图", "is_default": True,
     "config": {"format": "summary"}},
    {"id": "full", "name": "完整内容", "description": "全文与全部媒体", "config": {"format": "full"}},
    {"id": "text", "name": "仅文字", "description": "全文与原文链接，不发送媒体", "config": {"format": "text"}},
]
