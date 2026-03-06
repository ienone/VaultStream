"""
发现流适配器基类

所有来源 Scraper（RSS/HN/Reddit/GitHub/Telegram）继承此基类。
"""
from abc import ABC, abstractmethod
from dataclasses import dataclass, field
from datetime import datetime
from typing import Optional


@dataclass
class DiscoveryItem:
    """适配器产出的标准化发现条目，用于入库前的统一结构。"""

    url: str
    title: str
    content: str = ""
    author: Optional[str] = None
    published_at: Optional[datetime] = None
    source_tags: list[str] = field(default_factory=list)
    raw_metadata: dict = field(default_factory=dict)


class BaseDiscoveryScraper(ABC):
    """发现流适配器抽象基类。"""

    def __init__(self, source_config: dict):
        """
        Args:
            source_config: discovery_sources.config JSON 字段的内容
        """
        self.config = source_config

    @abstractmethod
    async def fetch(self, last_cursor: Optional[str] = None) -> tuple[list[DiscoveryItem], Optional[str]]:
        """
        抓取新内容。

        Args:
            last_cursor: 上次同步的游标（entry ID / 时间戳），用于增量抓取。
                         首次同步时为 None。

        Returns:
            (items, new_cursor): 抓取到的条目列表 + 新游标值
        """
        ...
