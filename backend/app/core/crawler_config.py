"""
爬虫配置管理

根据域名/地区配置不同的等待时间和爬取策略。
使用内置规则组进行匹配，不依赖运行时数据库配置。
"""
from typing import Optional, TypedDict, List
from urllib.parse import urlparse


# 默认等待时间（秒）
DEFAULT_DELAY = 5.0


class RuleGroup(TypedDict, total=False):
    """规则组结构"""
    name: str           # 规则组名称
    delay: float        # 延迟时间（秒）
    domains: List[str]  # 域名列表
    enabled: bool       # 是否启用
    priority: int       # 优先级（越大越优先）


# 内置规则组（只读，不可修改）
BUILTIN_RULE_GROUPS: dict[str, RuleGroup] = {
    "overseas_social": {
        "name": "海外社交媒体",
        "delay": 20.0,
        "domains": [
            "twitter.com", "x.com", "t.co",
            "instagram.com",
            "facebook.com", "fb.com",
            "reddit.com",
            "tiktok.com",
            "tumblr.com",
            "pinterest.com",
        ],
        "enabled": True,
        "priority": 10,
    },
    "overseas_video": {
        "name": "海外视频平台",
        "delay": 20.0,
        "domains": [
            "youtube.com", "youtu.be",
            "twitch.tv",
            "vimeo.com",
        ],
        "enabled": True,
        "priority": 10,
    },
    "overseas_tech": {
        "name": "海外技术站点",
        "delay": 15.0,
        "domains": [
            "github.com", "githubusercontent.com",
            "medium.com",
            "dev.to",
            "stackoverflow.com",
        ],
        "enabled": True,
        "priority": 5,
    },
    "overseas_other": {
        "name": "其他海外站点",
        "delay": 15.0,
        "domains": [
            "google.com", "blogger.com", "blogspot.com",
            "telegram.org", "t.me",
            "discord.com", "discord.gg",
            "flickr.com",
        ],
        "enabled": True,
        "priority": 5,
    },
}


def extract_domain(url: str) -> str:
    """从 URL 中提取主域名（不含 www）"""
    try:
        parsed = urlparse(url)
        domain = parsed.netloc.lower()
        # 移除 www. 前缀
        if domain.startswith("www."):
            domain = domain[4:]
        return domain
    except Exception:
        return ""


def match_domain(domain: str, pattern: str) -> bool:
    """检查域名是否匹配规则"""
    # 精确匹配
    if domain == pattern:
        return True
    # 子域名匹配（如 mobile.twitter.com 匹配 twitter.com）
    if domain.endswith("." + pattern):
        return True
    return False


def find_matching_rule_sync(domain: str) -> tuple[Optional[str], Optional[RuleGroup]]:
    """
    同步版本：查找匹配域名的规则组（仅内置规则）
    
    Returns:
        (规则组ID, 规则组) 或 (None, None)
    """
    matched: list[tuple[str, RuleGroup, int]] = []
    
    for group_id, group in BUILTIN_RULE_GROUPS.items():
        if not group.get("enabled", True):
            continue
        for pattern in group.get("domains", []):
            if match_domain(domain, pattern):
                matched.append((group_id, group, group.get("priority", 0)))
                break
    
    if not matched:
        return None, None
    
    # 按优先级排序，取最高优先级
    matched.sort(key=lambda x: x[2], reverse=True)
    return matched[0][0], matched[0][1]


async def find_matching_rule(domain: str) -> tuple[Optional[str], Optional[RuleGroup], float]:
    """异步兼容包装：复用同步规则匹配实现。"""
    group_id, group = find_matching_rule_sync(domain)
    if not group:
        return None, None, DEFAULT_DELAY
    return group_id, group, group.get("delay", DEFAULT_DELAY)


async def get_delay_for_url(url: str) -> float:
    """
    根据 URL 获取适当的等待时间
    
    Args:
        url: 目标 URL
    
    Returns:
        等待时间（秒）
    """
    domain = extract_domain(url)
    if not domain:
        return DEFAULT_DELAY
    
    # 查找匹配的规则组
    _, _, delay = await find_matching_rule(domain)
    
    if delay != DEFAULT_DELAY:
        return delay
    
    return DEFAULT_DELAY


def get_delay_for_url_sync(url: str) -> float:
    """
    同步版本：根据 URL 获取适当的等待时间
    仅使用内置配置，不查询数据库
    
    Args:
        url: 目标 URL
    
    Returns:
        等待时间（秒）
    """
    domain = extract_domain(url)
    if not domain:
        return DEFAULT_DELAY
    
    # 查找匹配的内置规则组
    _, group = find_matching_rule_sync(domain)
    if group:
        return group.get("delay", DEFAULT_DELAY)
    
    return DEFAULT_DELAY

