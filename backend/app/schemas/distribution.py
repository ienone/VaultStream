from __future__ import annotations
"""
分发规则与目标 schemas
"""
from datetime import datetime
from enum import Enum
from typing import Optional, List, Dict, Any
from pydantic import BaseModel, Field, field_validator, model_validator


class DistributionTargetCreate(BaseModel):
    bot_chat_id: int
    enabled: bool = True
    merge_forward: bool = False
    use_author_name: bool = True
    summary: Optional[str] = None
    render_config_override: Optional[Dict[str, Any]] = None


class DistributionTargetUpdate(BaseModel):
    enabled: Optional[bool] = None
    merge_forward: Optional[bool] = None
    use_author_name: Optional[bool] = None
    summary: Optional[str] = None
    render_config_override: Optional[Dict[str, Any]] = None


class DistributionTargetResponse(BaseModel):
    id: int
    rule_id: int
    bot_chat_id: int
    enabled: bool
    merge_forward: bool
    use_author_name: bool
    summary: Optional[str]
    render_config_override: Optional[Dict[str, Any]]
    created_at: datetime
    updated_at: datetime
    
    bot_chat: Optional[BotChatResponse] = None
    
    class Config:
        orm_mode = True


class DistributionRuleCreate(BaseModel):
    name: str
    description: Optional[str] = None
    match_conditions: Dict[str, Any]
    enabled: bool = True
    priority: int = 0
    nsfw_policy: str = "block"
    approval_required: bool = False
    auto_approve_conditions: Optional[Dict[str, Any]] = None
    rate_limit: Optional[int] = None
    time_window: Optional[int] = None
    template_id: Optional[str] = None
    render_config: Optional[Dict[str, Any]] = None


class DistributionRuleUpdate(BaseModel):
    name: Optional[str] = None
    description: Optional[str] = None
    match_conditions: Optional[Dict[str, Any]] = None
    enabled: Optional[bool] = None
    priority: Optional[int] = None
    nsfw_policy: Optional[str] = None
    approval_required: Optional[bool] = None
    auto_approve_conditions: Optional[Dict[str, Any]] = None
    rate_limit: Optional[int] = None
    time_window: Optional[int] = None
    template_id: Optional[str] = None
    render_config: Optional[Dict[str, Any]] = None


class DistributionRuleResponse(BaseModel):
    id: int
    name: str
    description: Optional[str]
    match_conditions: Dict[str, Any]
    enabled: bool
    priority: int
    nsfw_policy: str
    approval_required: bool
    auto_approve_conditions: Optional[Dict[str, Any]]
    rate_limit: Optional[int]
    time_window: Optional[int]
    template_id: Optional[str]
    render_config: Optional[Dict[str, Any]]
    created_at: datetime
    updated_at: datetime
    
    distribution_targets: List[DistributionTargetResponse] = Field(default_factory=list)
    
    class Config:
        orm_mode = True


class RulePreviewStats(BaseModel):
    """规则级别的分发预览统计（基于24h未来展望+现有内容）"""
    rule_id: int
    rule_name: str
    will_push: int
    filtered: int
    pending_review: int
    total_matched: int


class AllRulesPreviewResponse(BaseModel):
    """所有规则的分发预览统计"""
    rules: List[RulePreviewStats]
    summary_will_push: int  # 各规则去重后的将推总数（简化版可直接求和）
    summary_filtered: int
    summary_pending: int
    total_system_contents: int


class DistributionPreviewItem(BaseModel):
    """规则分发预览的内容项"""
    content_id: int
    title: Optional[str]
    url: str
    decision: str  # will_push, filtered, pending_review
    reason: Optional[str] = None  # 如 "rejected by tag" / "nsfw block"
    bot_chats: List[Dict[str, Any]] = Field(default_factory=list)  # [{'id': 1, 'title': 'xxx'}]


class DistributionPreviewResponse(BaseModel):
    """规则级别的实际预览内容（包含将推、已滤等）"""
    rule_id: int
    rule_name: str
    items: List[DistributionPreviewItem]
    total_matched: int
    
    
class BatchTargetUpdateRequest(BaseModel):
    target_ids: List[int]
    enabled: Optional[bool] = None
    merge_forward: Optional[bool] = None
    use_author_name: Optional[bool] = None
    summary: Optional[str] = None
    render_config_override: Optional[Dict[str, Any]] = None
    

    class Config:
        orm_mode = True


class TargetUsageInfo(BaseModel):
    """分发目标使用情况（聚合展示）"""
    target_platform: str
    target_id: str
    enabled: bool
    rule_count: int
    rule_ids: List[int]
    rule_names: List[str]
    merge_forward: bool = False
    use_author_name: bool = True
    summary: Optional[str] = None
    render_config: Optional[Dict[str, Any]] = None
    total_pushed: int = 0
    last_pushed_at: Optional[datetime] = None


class TargetListResponse(BaseModel):
    """分发目标列表响应"""
    total: int
    targets: List[TargetUsageInfo]


class BatchTargetUpdateResponse(BaseModel):
    """批量更新分发目标响应"""
    updated_count: int
    updated_rules: List[int]
    message: str


class RenderConfig(BaseModel):
    """渲染配置结构（可嵌套或扁平使用）"""
    show_platform_id: bool = True
    show_title: bool = True
    show_tags: bool = False
    author_mode: str = Field(default="full", description="Author display mode: none/name/full")
    content_mode: str = Field(default="summary", description="Content mode: hidden/summary/full")
    media_mode: str = Field(default="auto", description="Media mode: none/auto/all")
    link_mode: str = Field(default="clean", description="Link mode: none/clean/original")
    header_text: str = Field(default="", description="Header text with variable support")
    footer_text: str = Field(default="", description="Footer text with variable support")


class RenderConfigPreset(BaseModel):
    """渲染配置预设"""
    id: str
    name: str
    config: RenderConfig
    is_default: bool = False
    description: Optional[str] = None


class RulePreviewRequest(BaseModel):
    """规则预览请求"""
    hours_ahead: int = Field(default=24, ge=1, le=168, description="预览未来多少小时")
    limit: int = Field(default=50, ge=1, le=200, description="最大返回条数")


class PreviewItemStatus(str, Enum):
    """预览项状态"""
    WILL_PUSH = "will_push"
    FILTERED = "filtered"
    PENDING_REVIEW = "pending_review"
    PUSHED = "pushed"
class RulePreviewItem(BaseModel):
    """规则预览项"""
    content_id: int
    title: Optional[str] = None
    platform: str
    tags: List[str] = Field(default_factory=list)
    is_nsfw: bool = False
    status: str
    reason_code: Optional[str] = None
    reason: Optional[str] = None
    scheduled_time: Optional[datetime] = None
    thumbnail_url: Optional[str] = None
    
    class Config:
        orm_mode = True


class RulePreviewResponse(BaseModel):
    """规则预览响应"""
    rule_id: int
    rule_name: str
    total_matched: int
    will_push_count: int
    filtered_count: int
    pending_review_count: int
    items: List[RulePreviewItem]
