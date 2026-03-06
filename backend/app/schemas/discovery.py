"""
Discovery 相关 schemas
"""
from datetime import datetime
from typing import Optional, List, Literal
from pydantic import BaseModel, ConfigDict, Field

from app.models import DiscoverySourceKind, DiscoveryState


# --- Discovery Item ---

class DiscoveryItemResponse(BaseModel):
    id: int
    title: Optional[str] = None
    url: str
    summary: Optional[str] = None
    ai_score: Optional[float] = None
    ai_reason: Optional[str] = None
    ai_tags: Optional[list] = None
    source_type: Optional[str] = None
    discovery_state: Optional[DiscoveryState] = None
    discovered_at: Optional[datetime] = None
    created_at: datetime

    model_config = ConfigDict(from_attributes=True)


class DiscoveryItemUpdate(BaseModel):
    state: Literal["promoted", "ignored"]


class DiscoveryBulkAction(BaseModel):
    ids: List[int]
    action: Literal["promote", "ignore"]


# --- Discovery Source ---

class DiscoverySourceCreate(BaseModel):
    kind: DiscoverySourceKind
    name: str
    enabled: bool = True
    config: dict = Field(default_factory=dict)
    sync_interval_minutes: int = 60


class DiscoverySourceUpdate(BaseModel):
    name: Optional[str] = None
    enabled: Optional[bool] = None
    config: Optional[dict] = None
    sync_interval_minutes: Optional[int] = None


class DiscoverySourceResponse(BaseModel):
    id: int
    kind: DiscoverySourceKind
    name: str
    enabled: bool
    config: dict = Field(default_factory=dict)
    last_sync_at: Optional[datetime] = None
    last_error: Optional[str] = None
    sync_interval_minutes: int
    created_at: datetime

    model_config = ConfigDict(from_attributes=True)


# --- Discovery Settings ---

class DiscoverySettingsResponse(BaseModel):
    interest_profile: str = ""
    score_threshold: float = 6.0
    retention_days: int = 7


class DiscoverySettingsUpdate(BaseModel):
    interest_profile: Optional[str] = None
    score_threshold: Optional[float] = None
    retention_days: Optional[int] = None


# --- Stats ---

class DiscoveryStatsResponse(BaseModel):
    total: int = 0
    by_state: dict[str, int] = Field(default_factory=dict)
    by_source: dict[str, int] = Field(default_factory=dict)
