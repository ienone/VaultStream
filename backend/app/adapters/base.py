"""
平台适配器基类
"""
from abc import ABC, abstractmethod
from typing import Dict, Any, Optional, List, Literal
from dataclasses import dataclass, field
from datetime import datetime

# 布局类型常量
LAYOUT_ARTICLE = "article"
LAYOUT_VIDEO = "video"
LAYOUT_GALLERY = "gallery"
LAYOUT_AUDIO = "audio"
LAYOUT_LINK = "link"

LayoutTypeStr = Literal["article", "video", "gallery", "audio", "link"]


@dataclass
class ParsedContent:
    """解析后的内容"""
    platform: str
    content_type: str
    content_id: str
    clean_url: str
    layout_type: LayoutTypeStr  # 布局类型 - 必填
    
    title: Optional[str] = None
    description: Optional[str] = None
    author_name: Optional[str] = None
    author_id: Optional[str] = None
    author_avatar_url: Optional[str] = None
    author_url: Optional[str] = None  # 作者主页链接
    cover_url: Optional[str] = None
    cover_color: Optional[str] = None
    media_urls: list = field(default_factory=list)
    published_at: Optional[datetime] = None
    
    # DEPRECATED: Use archive_metadata
    raw_metadata: Dict[str, Any] = field(default_factory=dict)
    
    stats: Dict[str, int] = field(default_factory=dict)  # 通用互动数据
    source_tags: List[str] = field(default_factory=list)  # 平台原生标签
    
    # DEPRECATED: Use context_data / rich_payload
    associated_question: Optional[Dict[str, Any]] = None  # 知乎回答关联的问题
    top_answers: Optional[List[Dict[str, Any]]] = None  # 知乎问题的精选回答
    
    # New V2 Fields
    context_data: Optional[Dict[str, Any]] = None  # [Context Slot] 关联上下文
    rich_payload: Optional[Dict[str, Any]] = None  # [Rich Payload] 富媒体/交互组件块
    archive_metadata: Optional[Dict[str, Any]] = None  # [Archive Blob] 原始元数据
    
    def __post_init__(self):
        # 强约束：必需的标识符必须存在
        if not isinstance(self.platform, str) or not self.platform.strip():
            raise ValueError("ParsedContent.platform 不能为空")
        if not isinstance(self.content_type, str) or not self.content_type.strip():
            raise ValueError("ParsedContent.content_type 不能为空")
        if not isinstance(self.content_id, str) or not self.content_id.strip():
            raise ValueError("ParsedContent.content_id 不能为空")
        if not isinstance(self.clean_url, str) or not self.clean_url.strip():
            raise ValueError("ParsedContent.clean_url 不能为空")
        
        # layout_type 必填且合法
        valid_layouts = (LAYOUT_ARTICLE, LAYOUT_VIDEO, LAYOUT_GALLERY, LAYOUT_AUDIO, LAYOUT_LINK)
        if self.layout_type not in valid_layouts:
            raise ValueError(f"ParsedContent.layout_type 必须是 {valid_layouts} 之一，实际为: {self.layout_type}")

        if not isinstance(self.media_urls, list):
            raise ValueError("ParsedContent.media_urls 必须是列表")
        if not isinstance(self.raw_metadata, dict):
            raise ValueError("ParsedContent.raw_metadata 必须是字典")
        if not isinstance(self.stats, dict):
            raise ValueError("ParsedContent.stats 必须是字典")


class PlatformAdapter(ABC):
    """平台适配器基类"""
    
    @abstractmethod
    async def detect_content_type(self, url: str) -> Optional[str]:
        """检测内容类型"""
        pass
    
    @abstractmethod
    async def clean_url(self, url: str) -> str:
        """净化URL（去除追踪参数、短链还原等）"""
        pass
    
    @abstractmethod
    async def parse(self, url: str) -> ParsedContent:
        """解析内容"""
        pass

