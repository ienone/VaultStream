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
    body: Optional[str] = None
    author_name: Optional[str] = None
    author_id: Optional[str] = None
    author_avatar_url: Optional[str] = None
    author_url: Optional[str] = None  # 作者主页链接
    cover_url: Optional[str] = None
    cover_color: Optional[str] = None
    media_urls: list = field(default_factory=list)
    published_at: Optional[datetime] = None
    
    stats: Dict[str, int] = field(default_factory=dict)  # 通用互动数据
    source_tags: List[str] = field(default_factory=list)  # 平台原生标签
    
    # 结构化扩展组件
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

    @staticmethod
    def build_standard_archive(
        item: Dict[str, Any], 
        archive_type: str, 
        title: str = "", 
        body: str = "", 
        images: Optional[List[Dict[str, Any]]] = None,
        author_avatar_url: Optional[str] = None
    ) -> Dict[str, Any]:
        """工厂基类方法：构建标准化的 archive_metadata"""
        import copy
        images_list = copy.deepcopy(images) if images else []
        
        # 组装头像，过滤空数据
        if author_avatar_url:
            # 避免重复添加
            if not any(img.get("type") == "avatar" and img.get("url") == author_avatar_url for img in images_list):
                images_list.append({"url": author_avatar_url, "type": "avatar"})
        
        archive = {
            "version": 2,
            "type": archive_type,
            "title": title,
            "plain_text": body,
            "markdown": body,
            "images": images_list,
            "videos": [],
            "links": [],
            "stored_images": [],
            "stored_videos": []
        }
        
        archive_metadata = copy.deepcopy(item) if isinstance(item, dict) else {"item": copy.deepcopy(item)}
        archive_metadata["archive"] = archive
        return archive_metadata

    @staticmethod
    def create_parsed_content(**kwargs) -> ParsedContent:
        """工厂基类方法：创建 ParsedContent，自动处理空数据和一些标准化逻辑"""
        # 确保 media_urls 中剔除了可能为空的 URL
        if "media_urls" in kwargs and kwargs["media_urls"]:
            kwargs["media_urls"] = [url for url in kwargs["media_urls"] if url]
        return ParsedContent(**kwargs)

