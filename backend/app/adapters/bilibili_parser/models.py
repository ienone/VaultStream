"""
B站解析器数据模型

定义B站内容解析过程中使用的数据结构
"""
from typing import Dict, List, Any, Optional
from dataclasses import dataclass, field


@dataclass
class BilibiliArchive:
    """
    B站内容存档结构
    
    用于存储解析后的内容，供私有存档和检索使用
    """
    version: int = 2  # 存档格式版本
    type: str = ""  # 存档类型: bilibili_video, bilibili_article等
    title: str = ""  # 标题
    plain_text: str = ""  # 纯文本内容
    markdown: str = ""  # Markdown格式内容
    blocks: List[Dict[str, Any]] = field(default_factory=list)  # 结构化内容块
    images: List[Dict[str, Any]] = field(default_factory=list)  # 图片列表
    videos: List[Dict[str, Any]] = field(default_factory=list)  # 视频列表
    links: List[Dict[str, Any]] = field(default_factory=list)  # 链接列表
    mentions: List[Dict[str, Any]] = field(default_factory=list)  # @提及列表
    topics: List[str] = field(default_factory=list)  # 话题列表
    stored_images: List[Dict[str, Any]] = field(default_factory=list)  # 已存储的图片
    stored_videos: List[Dict[str, Any]] = field(default_factory=list)  # 已存储的视频
    
    def to_dict(self) -> Dict[str, Any]:
        """转换为字典格式"""
        return {
            "version": self.version,
            "type": self.type,
            "title": self.title,
            "plain_text": self.plain_text,
            "markdown": self.markdown,
            "blocks": self.blocks,
            "images": self.images,
            "videos": self.videos,
            "links": self.links,
            "mentions": self.mentions,
            "topics": self.topics,
            "stored_images": self.stored_images,
            "stored_videos": self.stored_videos,
        }


@dataclass
class VideoInfo:
    """视频基本信息"""
    bvid: Optional[str] = None  # BV号
    aid: Optional[int] = None  # AV号
    title: str = ""  # 标题
    desc: str = ""  # 描述
    pic: Optional[str] = None  # 封面图
    pubdate: Optional[int] = None  # 发布时间戳
    duration: int = 0  # 时长（秒）
    owner: Dict[str, Any] = field(default_factory=dict)  # UP主信息
    stat: Dict[str, Any] = field(default_factory=dict)  # 统计数据
    pages: List[Dict[str, Any]] = field(default_factory=list)  # 分P信息


@dataclass
class ArticleInfo:
    """专栏文章基本信息"""
    cvid: str = ""  # 文章ID（如cv123456）
    title: str = ""  # 标题
    summary: str = ""  # 摘要
    banner_url: Optional[str] = None  # 横幅图
    mid: Optional[int] = None  # 作者UID
    author_name: str = ""  # 作者名
    author_face: Optional[str] = None  # 作者头像
    image_urls: List[str] = field(default_factory=list)  # 图片列表
    publish_time: Optional[int] = None  # 发布时间戳
    stats: Dict[str, Any] = field(default_factory=dict)  # 统计数据


@dataclass
class DynamicInfo:
    """动态基本信息"""
    dynamic_id: str = ""  # 动态ID
    type: str = "opus"  # 动态类型
    title: str = ""  # 标题
    content: str = ""  # 内容
    author: Dict[str, Any] = field(default_factory=dict)  # 作者信息
    images: List[Dict[str, Any]] = field(default_factory=list)  # 图片列表
    created_at: Optional[int] = None  # 创建时间戳


@dataclass
class BangumiInfo:
    """番剧/影视基本信息"""
    season_id: Optional[str] = None  # 季度ID（如ss12345）
    ep_id: Optional[str] = None  # 剧集ID（如ep12345）
    title: str = ""  # 标题
    evaluate: str = ""  # 简介/评价
    cover: Optional[str] = None  # 封面图
    stat: Dict[str, Any] = field(default_factory=dict)  # 统计数据


@dataclass
class LiveInfo:
    """直播间基本信息"""
    room_id: str = ""  # 直播间ID
    title: str = ""  # 直播间标题
    description: str = ""  # 描述
    cover: Optional[str] = None  # 封面图
    uid: Optional[int] = None  # 主播UID
    uname: str = ""  # 主播昵称
    face: Optional[str] = None  # 主播头像
    live_status: int = 0  # 直播状态: 0-未开播, 1-直播中, 2-轮播中
    online: int = 0  # 在线人数/人气值
