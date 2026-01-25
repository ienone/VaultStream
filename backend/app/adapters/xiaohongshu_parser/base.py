"""
小红书解析器公共工具模块

提供所有小红书解析器共用的工具函数
"""
import re
import html as _html
from typing import Any, List


def clean_text(text: Any) -> str:
    """
    清洗文本
    
    Args:
        text: 待清洗的文本
        
    Returns:
        str: 清洗后的文本
    """
    if text is None:
        return ""
    if not isinstance(text, str):
        text = str(text)
    
    val = _html.unescape(text)
    val = val.replace("\u200b", "").replace("\ufeff", "")
    val = val.replace("\r\n", "\n").replace("\r", "\n")
    val = "\n".join([ln.strip() for ln in val.split("\n")])
    val = re.sub(r"\n{3,}", "\n\n", val)
    return val.strip()


def extract_source_tags(note: dict) -> List[str]:
    """
    提取平台原生标签
    
    来源：
    1. tag_list字段中的话题标签
    2. desc描述中的#话题[话题]#格式
    
    Args:
        note: 笔记数据
        
    Returns:
        List[str]: 标签列表
    """
    tags = set()
    
    # 从tag_list提取
    tag_list = note.get("tag_list") or note.get("tagList") or []
    for tag in tag_list:
        if isinstance(tag, dict):
            name = tag.get("name", "").strip()
            if name:
                tags.add(name)
    
    # 从描述中提取#xxx[话题]#或#xxx#格式
    desc = note.get("desc", "") or ""
    # 匹配#标签名[话题]#格式
    pattern1 = r'#([^#\[\]]+)\[话题\]#'
    for match in re.findall(pattern1, desc):
        tag_name = match.strip()
        if tag_name:
            tags.add(tag_name)
    
    # 匹配普通#标签#格式（不含[话题]的）
    pattern2 = r'#([^#\[\]]+)#'
    for match in re.findall(pattern2, desc):
        tag_name = match.strip()
        if tag_name and '[话题]' not in tag_name:
            tags.add(tag_name)
    
    return sorted(list(tags))


def strip_tags_from_text(text: str) -> str:
    """
    从文本中移除标签格式
    
    移除：
    - #标签名[话题]#格式
    - #标签名#格式（独立的）
    
    Args:
        text: 原始文本
        
    Returns:
        str: 移除标签后的文本
    """
    if not text:
        return ""
    
    # 移除#xxx[话题]#格式
    result = re.sub(r'#[^#\[\]]+\[话题\]#\s*', '', text)
    
    # 移除独立的#xxx#格式（前后是空白或行首行尾）
    result = re.sub(r'(?:^|\s)#[^#\[\]\s]+#(?:\s|$)', ' ', result)
    
    # 清理多余空白
    result = re.sub(r'\s+', ' ', result).strip()
    result = re.sub(r'\n\s*\n', '\n\n', result)
    
    return result
