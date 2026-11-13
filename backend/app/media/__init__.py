"""
媒体处理模块 - 提供媒体下载、转换、存储等功能

该模块包含:
- processor: 媒体下载、转换和存储
- extractor: 媒体URL提取
- color: 封面颜色提取
"""
from .extractor import extract_media_urls
from .processor import archive_media_file
from .color import extract_cover_color

__all__ = [
    'extract_media_urls',
    'archive_media_file',
    'extract_cover_color',
]
