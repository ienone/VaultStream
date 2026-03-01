"""
通用的 schema 定义与基类模型
"""
from datetime import datetime
from typing import Optional, List, Dict, Any, TypeVar, Generic
from pydantic import BaseModel, Field
from app.models import Platform, ContentStatus, ReviewStatus, LayoutType

class APIResponse(BaseModel):
    """标准的 API 响应包裹体（如需扩展）"""
    code: int = 200
    message: str = "success"
    data: Optional[Any] = None

class TagStats(BaseModel):
    """标签统计"""
    name: str
    count: int

class QueueStats(BaseModel):
    """队列统计"""
    unprocessed: int
    processing: int
    parse_success: int
    parse_failed: int
    total: int

class DistributionStatusStats(BaseModel):
    """解析成功后进入分发阶段的状态统计"""
    will_push: int
    filtered: int
    pending_review: int
    pushed: int
    total: int

class DashboardStats(BaseModel):
    """仪表盘数据"""
    platform_counts: Dict[str, int]
    daily_growth: List[Dict[str, Any]]
    storage_usage_bytes: int


class QueueOverviewStats(BaseModel):
    """看板队列总览统计（解析+分发）"""
    parse: QueueStats
    distribution: DistributionStatusStats


class SystemSettingBase(BaseModel):
    """系统设置基础"""
    value: Any
    category: Optional[str] = "general"
    description: Optional[str] = None


class SystemSettingUpdate(BaseModel):
    """更新系统设置"""
    value: Any
    description: Optional[str] = None


class SystemSettingResponse(SystemSettingBase):
    """系统设置响应"""
    key: str
    updated_at: datetime

    class Config:
        orm_mode = True


class StorageStatsResponse(BaseModel):
    """存储统计响应"""
    total_bytes: int
    media_count: int
    by_platform: Dict[str, int]
    by_type: Dict[str, int]

class PushedRecordResponse(BaseModel):
    """推送记录响应"""
    id: int
    content_id: int
    target_platform: str
    target_id: str
    message_id: Optional[str] = None
    push_status: str
    error_message: Optional[str] = None
    pushed_at: datetime
    
    class Config:
        orm_mode = True
