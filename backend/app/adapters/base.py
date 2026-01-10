"""
平台适配器基类
"""
from abc import ABC, abstractmethod
from typing import Dict, Any, Optional, List
from dataclasses import dataclass
from datetime import datetime


@dataclass
class ParsedContent:
    """解析后的内容"""
    platform: str
    content_type: str
    content_id: str
    clean_url: str
    
    title: Optional[str] = None
    description: Optional[str] = None
    author_name: Optional[str] = None
    author_id: Optional[str] = None
    cover_url: Optional[str] = None
    cover_color: Optional[str] = None
    media_urls: list = None
    published_at: Optional[datetime] = None  # 将 str 改为 datetime
    
    raw_metadata: Dict[str, Any] = None
    stats: Dict[str, int] = None  # 新增：通用互动数据
    
    def __post_init__(self):
        if self.media_urls is None:
            self.media_urls = []
        if self.raw_metadata is None:
            self.raw_metadata = {}
        if self.stats is None:
            self.stats = {}

        # 强约束：必需的标识符必须存在
        if not isinstance(self.platform, str) or not self.platform.strip():
            raise ValueError("ParsedContent.platform 不能为空")
        if not isinstance(self.content_type, str) or not self.content_type.strip():
            raise ValueError("ParsedContent.content_type 不能为空")
        if not isinstance(self.content_id, str) or not self.content_id.strip():
            raise ValueError("ParsedContent.content_id 不能为空")
        if not isinstance(self.clean_url, str) or not self.clean_url.strip():
            raise ValueError("ParsedContent.clean_url 不能为空")

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

