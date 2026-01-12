import re
import json
import logging
import requests
from typing import Optional, List, Dict, Any
from app.adapters.base import PlatformAdapter, ParsedContent
from app.adapters.errors import NonRetryableAdapterError, RetryableAdapterError
from app.config import settings

logger = logging.getLogger(__name__)

class XiaohongshuAdapter(PlatformAdapter):
    """
    小红书内容解析适配器
    
    依赖:
    - settings.xiaohongshu_cookie: 必须配置有效的 Cookie 才能获取数据
    """
    
    # 匹配小红书笔记链接 (Explore 或 Discovery)
    # e.g., https://www.xiaohongshu.com/explore/64c878540000000010032e5c
    # e.g., https://www.xiaohongshu.com/discovery/item/64c878540000000010032e5c
 