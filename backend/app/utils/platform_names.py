PLATFORM_NAMES = {
    "zhihu": "知乎",
    "xiaohongshu": "小红书",
    "twitter": "X",
    "weibo": "微博",
    "bilibili": "哔哩哔哩",
    "telegram": "Telegram",
    "qq": "QQ",
}


def platform_name(platform: str) -> str:
    return PLATFORM_NAMES.get(platform, platform)
