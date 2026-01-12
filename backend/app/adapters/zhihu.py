import re
import json
import logging
import requests
from typing import Optional, List, Dict, Any
from app.adapters.base import PlatformAdapter, ParsedContent
from app.adapters.errors import NonRetryableAdapterError, RetryableAdapterError
from app.config import settings
from datetime import datetime

logger = logging.getLogger(__name__)

class ZhihuAdapter(PlatformAdapter)
    """
    知乎内容解析适配器
    
    支持:
    - 回答: hhttps://www.zhihu.com/answer/1993098398442726640
    - 文章: https://zhuanlan.zhihu.com/p/1993458822560363213
    - 问题: https://www.zhihu.com/question/20917550(提取问题本身及信息以及前几个回答的链接&作者信息)
    - 想法: https://www.zhihu.com/pin/1882078427231803012
    - 用户信息: https://www.zhihu.com/people/tian-yuan-dong
    依赖:
    - settings.zhihu_cookie 
  