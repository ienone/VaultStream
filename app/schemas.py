"""
Pydantic 模式定义（用于API请求/响应）
"""
from datetime import datetime
from typing import Optional, List, Dict, Any
from pydantic import BaseModel, HttpUrl, Field
from app.models import ContentStatus, Platform, BilibiliContentType


class ShareRequest(BaseModel):
    """分享请求"""
    url: str = Field(..., description="要分享的URL")
    tags: List[str] = Field(default_factory=list, description="标签列表")
    source: Optional[str] = Field(None, description="来源标识")
    is_nsfw: bool = Field(default=False, description="是否为NSFW内容")


class ShareResponse(BaseModel):
    """分享响应"""
    id: int
    platform: Platform
    url: str
    status: ContentStatus
    created_at: datetime
    
    class Config:
        from_attributes = True


class ContentDetail(BaseModel):
    """内容详情"""
    id: int
    platform: Platform
    url: str
    clean_url: Optional[str]
    status: ContentStatus
    tags: List[str]
    is_nsfw: bool
    source: Optional[str]
    content_type: Optional[str] # 内容具体类型

    # 通用字段
    title: Optional[str] # 内容标题
    description: Optional[str] # 内容描述
    author_name: Optional[str] # 作者名称
    author_id: Optional[str] # 作者平台ID
    cover_url: Optional[str] # 封面URL
    media_urls: List[str] # 媒体资源URL列表
    view_count: int = 0 # 查看次数
    like_count: int = 0 # 点赞次数
    collect_count: int = 0 # 收藏次数
    share_count: int = 0 # 分享次数 
    comment_count: int = 0 # 评论次数
    extra_stats: Dict[str, Any] = Field(default_factory=dict) # 平台特有扩展数据

    # B站特有
    bilibili_type: Optional[BilibiliContentType]
    bilibili_id: Optional[str]
        
    # 元数据
    raw_metadata: Optional[Dict[str, Any]]
    
    # 时间
    created_at: datetime
    updated_at: datetime
    published_at: Optional[datetime]
    
    class Config:
        from_attributes = True


class GetContentRequest(BaseModel):
    """获取待分发内容请求"""
    tag: Optional[str] = Field(None, description="按标签筛选")
    target_platform: str = Field(..., description="目标平台标识")
    limit: int = Field(1, ge=1, le=10, description="获取数量")


class MarkPushedRequest(BaseModel):
    """标记已推送请求"""
    content_id: int
    target_platform: str
    message_id: Optional[str] = None
