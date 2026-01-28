"""
Text Processing Utilities

Provides common text processing functions for all platform adapters.
"""
from typing import Optional


# 常见中英文标点符号
PUNCTUATIONS = ['。', '！', '？', '，', '；', '：', '…', '.', '!', '?', ',', ';', ':', '\n']


def generate_title_from_text(
    text: str,
    max_len: int = 60,
    fallback: Optional[str] = None,
    ellipsis: str = "…"
) -> str:
    """
    从正文生成标题：从第二个字符开始到第一个标点符号为止
    
    用于没有标题字段的内容（如知乎想法、微博等）
    
    Args:
        text: 正文内容
        max_len: 最大标题长度
        fallback: 无法生成时的回退值
        ellipsis: 截断时使用的省略符
    
    Returns:
        生成的标题字符串
    
    Examples:
        >>> generate_title_from_text("今天天气真好，出去玩吧")
        '今天天气真好…'
        >>> generate_title_from_text("Hello world! How are you?")
        'Hello world…'
        >>> generate_title_from_text("！开头是标点的情况，也能处理")
        '开头是标点的情况…'
        >>> generate_title_from_text("")
        None
    """
    if not text:
        return fallback
    
    # 去除开头的空白
    text = text.strip()
    if not text:
        return fallback
    
    # 跳过开头的标点符号（排除开头第一个文本就是标点符号的情况）
    start_pos = 0
    while start_pos < len(text) and text[start_pos] in PUNCTUATIONS:
        start_pos += 1
    
    if start_pos >= len(text):
        return fallback
    
    # 从有效起始位置开始，查找第一个标点
    search_text = text[start_pos:]
    cut_pos = -1
    
    # 从第2个字符开始查找第一个标点（保留至少一个字符）
    for i in range(1, min(len(search_text), max_len)):
        if search_text[i] in PUNCTUATIONS:
            cut_pos = i
            break
    
    if cut_pos > 0:
        return search_text[:cut_pos] + ellipsis
    elif len(search_text) > max_len:
        return search_text[:max_len] + ellipsis
    
    return search_text


def ensure_title(
    title: Optional[str],
    description: Optional[str],
    max_len: int = 60,
    fallback: str = "无标题"
) -> str:
    """
    确保返回一个有效的标题：优先使用 title，否则从 description 生成
    
    Args:
        title: 原始标题（可能为空）
        description: 正文内容
        max_len: 从正文生成标题时的最大长度
        fallback: 都无法生成时的回退值
    
    Returns:
        有效的标题字符串
    
    Examples:
        >>> ensure_title("我的标题", "正文内容")
        '我的标题'
        >>> ensure_title(None, "今天天气真好，出去玩吧")
        '今天天气真好…'
        >>> ensure_title("", "")
        '无标题'
    """
    # 优先使用已有标题
    if title and title.strip():
        return title.strip()
    
    # 从正文生成
    generated = generate_title_from_text(description, max_len=max_len)
    if generated:
        return generated
    
    return fallback
