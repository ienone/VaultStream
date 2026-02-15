"""
格式化工具模块

提供数字、标签等格式化功能
"""
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

