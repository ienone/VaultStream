from __future__ import annotations

from abc import ABC, abstractmethod
from dataclasses import dataclass, field
from datetime import datetime
from typing import Optional


@dataclass
class FavoriteItem:
    """Unified favorite item shape across platforms."""

    url: str
    title: Optional[str] = None
    platform: Optional[str] = None
    item_id: Optional[str] = None
    author: Optional[str] = None
    cover_url: Optional[str] = None
    media_urls: list[str] = field(default_factory=list)
    favorited_at: Optional[datetime] = None
    content_type: Optional[str] = None


class BaseFavoritesFetcher(ABC):
    """Platform favorites fetcher base class."""

    @abstractmethod
    async def fetch_favorites(
        self,
        *,
        max_items: int = 50,
        cursor: Optional[str] = None,
    ) -> tuple[list[FavoriteItem], Optional[str]]:
        """Fetch favorites and return (items, next_cursor)."""

    @abstractmethod
    async def check_auth(self) -> bool:
        """Check whether current platform auth is available."""

    @abstractmethod
    def platform_name(self) -> str:
        """Return stable platform id."""
