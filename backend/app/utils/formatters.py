"""
格式化工具模块

提供数字、标签等格式化功能
"""
import re
from typing import List


def format_number(num) -> str:
    """
    格式化数字，超过1万显示为'万'
    
    Args:
        num: 待格式化的数字
        
    Returns:
        格式化后的字符串
        
    Examples:
        >>> format_number(5000)
        '5000'
        >>> format_number(15000)
        '1.50万'
        >>> format_number(123456)
        '12.35万'
    """
    if not num:
        return "0"
    try:
        n = int(num)
        if n >= 10000:
            return f"{n/10000:.2f}万"
        return str(n)
    except:
        return str(num)


def parse_tags(tags_str: str) -> List[str]:
    """
    解析标签字符串，支持中英文逗号、顿号分隔
    
    Args:
        tags_str: 标签字符串，如 "科技,编程、AI"
        
    Returns:
        标签列表
        
    Examples:
        >>> parse_tags("科技,编程、AI")
        ['科技', '编程', 'AI']
        >>> parse_tags("tag1，tag2、tag3")
        ['tag1', 'tag2', 'tag3']
    """
    if not tags_str:
        return []
    # 兼容 , ， 、 分隔符
    tags = re.split(r'[,，、]', tags_str)
    return [t.strip() for t in tags if t.strip()]
