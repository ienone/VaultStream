import re
from typing import List, Optional, Union, Any

def normalize_tags(tags: Optional[Union[List[str], str]] = None, tags_text: Optional[str] = None, lower: bool = False) -> List[str]:
    """
    统一标签清洗逻辑。
    
    功能：
    1. 支持列表或字符串输入。
    2. 自动根据逗号(中英文)、空格拆分。
    3. 去除首尾空格。
    4. 去重（保持顺序）。
    5. 过滤空值。
    6. 可选转换为小写。
    
    Args:
        tags: 标签列表或单个标签字符串。
        tags_text: 额外的标签文本（逗号/空格分隔）。
        lower: 是否转换为小写。默认为 False。
        
    Returns:
        清洗后的标签列表。
    """
    candidates: List[str] = []
    
    # 处理 tags 参数
    if tags:
        if isinstance(tags, str):
            candidates.extend(re.split(r"[,，\s]+", tags))
        elif isinstance(tags, list):
            for tag in tags:
                if tag is None:
                    continue
                candidates.extend(re.split(r"[,，\s]+", str(tag)))
    
    # 处理 tags_text 参数
    if tags_text:
        candidates.extend(re.split(r"[,，\s]+", tags_text))

    normalized: List[str] = []
    seen: set[str] = set()
    
    for raw in candidates:
        clean = raw.strip()
        if lower:
            clean = clean.lower()
            
        if not clean:
            continue
        if clean in seen:
            continue
        seen.add(clean)
        normalized.append(clean)
        
    return normalized
