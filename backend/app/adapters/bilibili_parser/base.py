"""
B站解析器公共工具模块

提供所有B站解析器共用的工具函数，包括：
- 文本清洗和格式化
- URL处理
- HTML处理
- Markdown渲染
"""
import re
import html as _html
from typing import Any, Optional, Dict, List
from app.logging import logger


def clean_text(text: Any) -> str:
    """
    清洗文本内容
    
    功能：
    - HTML 反转义
    - 去除零宽字符和不可见字符
    - 统一换行符
    - 去除行尾空白
    - 压缩多余空行
    
    Args:
        text: 待清洗的文本
        
    Returns:
        str: 清洗后的文本
    """
    if text is None:
        return ""
    if not isinstance(text, str):
        text = str(text)

    # HTML反转义
    val = _html.unescape(text)
    
    # 去除常见零宽/不可见字符
    val = val.replace("\u200b", "").replace("\ufeff", "")
    
    # 统一换行符
    val = val.replace("\r\n", "\n").replace("\r", "\n")
    
    # 去掉每行的首尾空白
    val = "\n".join([ln.strip() for ln in val.split("\n")])
    
    # 压缩连续空行（最多保留1个空行）
    val = re.sub(r"\n{3,}", "\n\n", val)
    
    return val.strip()


def safe_url(url: Any) -> Optional[str]:
    """
    安全获取URL
    
    处理协议相对URL（如//i0.hdslb.com/...）
    过滤无效URL
    
    Args:
        url: URL字符串或其他类型
        
    Returns:
        Optional[str]: 有效的URL字符串，无效则返回None
    """
    if not url or not isinstance(url, str):
        return None
    
    u = url.strip()
    if not u:
        return None
    
    # 将协议相对URL转换为绝对URL
    if u.startswith("//"):
        return "https:" + u
    
    return u


def prune_metadata(item: Dict[str, Any]) -> Dict[str, Any]:
    """
    裁剪冗余的大型元数据字段
    
    防止数据库膨胀和接口响应过慢，裁剪：
    - UGC合辑的episodes列表
    - PGC番剧的episodes列表
    - 视频的pages列表（超过10个分P时）
    - PGC章节的episodes列表
    
    Args:
        item: 原始元数据字典
        
    Returns:
        Dict[str, Any]: 裁剪后的元数据字典（原对象被修改）
    """
    if not item or not isinstance(item, dict):
        return item
        
    # 1) UGC 合辑处理 (ugc_season)
    # B站某些长视频属于合辑，ugc_season 包含了合辑中所有（可能几百个）视频的详细元数据
    if 'ugc_season' in item and isinstance(item['ugc_season'], dict):
        season = item.get('ugc_season')
        if 'sections' in season and isinstance(season['sections'], list):
            for section in season['sections']:
                if isinstance(section, dict) and 'episodes' in section and isinstance(section['episodes'], list):
                    # 记录数量并清空详细列表，防止数据过载
                    section['ep_count'] = len(section['episodes'])
                    section['episodes'] = []  # 清空集数详情
    
    # 2) PGC 番剧处理 (episodes) - 针对番剧、电影等
    if 'episodes' in item and isinstance(item['episodes'], list):
        # 番剧详情接口会返回所有剧集列表
        item['ep_count'] = len(item['episodes'])
        item['episodes'] = []  # 清空剧集列表

    # 3) 分P处理 (pages) - 针对多P视频
    if 'pages' in item and isinstance(item['pages'], list):
        # 分P通常包含每个分P的标题、时长等，如果太多也进行裁剪
        if len(item['pages']) > 10:
            item['page_count'] = len(item['pages'])
            item['pages'] = item['pages'][:10]  # 仅保留前10个预览
          
    # 4) PGC 章节处理 (sections)
    if 'sections' in item and isinstance(item['sections'], list):
        # 针对一些 PGC 内容的章节信息
        for section in item['sections']:
            if isinstance(section, dict) and 'episodes' in section and isinstance(section['episodes'], list):
                section['ep_count'] = len(section['episodes'])
                section['episodes'] = []
                
    return item


def render_markdown(blocks: List[Dict[str, Any]]) -> str:
    """
    将结构化blocks渲染为Markdown格式
    
    支持的block类型：
    - title: 一级标题
    - heading: 多级标题
    - text: 普通段落
    - quote: 引用块
    - separator: 分隔线
    - image: 图片
    - link: 链接
    
    Args:
        blocks: 结构化的内容块列表
        
    Returns:
        str: Markdown格式的文本
    """
    parts: List[str] = []
    
    for b in blocks:
        b_type = b.get("type")
        
        if b_type == "title":
            # 一级标题
            t = clean_text(b.get("text"))
            if t:
                parts.append(f"# {t}")
                
        elif b_type == "heading":
            # 多级标题
            t = clean_text(b.get("text"))
            level = b.get("level")
            try:
                level_i = int(level) if level is not None else 2
            except Exception:
                level_i = 2
            # 限制标题级别在2-6之间
            level_i = min(max(level_i, 2), 6)
            if t:
                parts.append(f"{'#' * level_i} {t}")
                
        elif b_type == "text":
            # 普通文本段落
            t = clean_text(b.get("text"))
            if t:
                parts.append(t)
                
        elif b_type == "quote":
            # 引用块
            t = clean_text(b.get("text"))
            if t:
                # 为每一行添加引用符号
                parts.append("\n".join([f"> {ln}" for ln in t.split("\n") if ln.strip()]))
                
        elif b_type == "separator":
            # 分隔线
            parts.append("---")
            
        elif b_type == "image":
            # 图片
            u = safe_url(b.get("url"))
            if u:
                alt = clean_text(b.get("alt") or "image")
                parts.append(f"![{alt}]({u})")
                
        elif b_type == "link":
            # 链接
            u = safe_url(b.get("url"))
            t = clean_text(b.get("text"))
            if u:
                parts.append(f"[{t or u}]({u})")
    
    return "\n\n".join([p for p in parts if p]).strip()


def parse_opus_text_nodes(
    nodes: Any,
    links: List[Dict[str, Any]],
    mentions: List[Dict[str, Any]],
    topics: List[str],
) -> tuple[str, str]:
    """
    解析B站动态（Opus）的文本节点结构
    
    B站动态使用特殊的节点结构，包含：
    - TEXT_NODE_TYPE_WORD: 普通文字（可能带样式）
    - TEXT_NODE_TYPE_RICH: 富文本（链接、@提及、话题等）
    
    Args:
        nodes: 节点列表
        links: 链接列表（会被修改，添加新链接）
        mentions: 提及列表（会被修改，添加新提及）
        topics: 话题列表（会被修改，添加新话题）
        
    Returns:
        tuple[str, str]: (纯文本, Markdown格式文本)
    """
    if not isinstance(nodes, list):
        return "", ""

    plain_parts: List[str] = []
    md_parts: List[str] = []

    def apply_style(md: str, style: Any) -> str:
        """应用文本样式到Markdown"""
        if not md:
            return md
        if not isinstance(style, dict):
            return md
        # 注意顺序：删除线 -> 斜体 -> 粗体
        if style.get("strikethrough"):
            md = f"~~{md}~~"
        if style.get("italic"):
            md = f"*{md}*"
        if style.get("bold"):
            md = f"**{md}**"
        return md

    for n in nodes:
        if not isinstance(n, dict):
            continue
        n_type = n.get("type")

        # 普通文字节点
        if n_type == "TEXT_NODE_TYPE_WORD":
            word = n.get("word") or {}
            text = clean_text(word.get("words") or "")
            if not text:
                continue
            plain_parts.append(text)
            md_parts.append(apply_style(text, word.get("style")))
            continue

        # 富文本节点（链接、提及、话题等）
        if n_type == "TEXT_NODE_TYPE_RICH":
            rich = n.get("rich") or {}
            rich_type = rich.get("type") or ""
            text = clean_text(rich.get("text") or rich.get("orig_text") or "")
            jump_url = safe_url(rich.get("jump_url") or rich.get("url"))
            
            # 处理协议相对URL
            if jump_url and jump_url.startswith("//"):
                jump_url = "https:" + jump_url

            # Web 链接
            if jump_url or rich_type == "RICH_TEXT_NODE_TYPE_WEB":
                if jump_url:
                    links.append({"url": jump_url, "text": text})
                    plain_parts.append(text or jump_url)
                    md_parts.append(f"[{text or jump_url}]({jump_url})")
                elif text:
                    plain_parts.append(text)
                    md_parts.append(text)
                continue

            # @ 提及
            if rich_type in ("RICH_TEXT_NODE_TYPE_AT", "RICH_TEXT_NODE_TYPE_MENTION"):
                rid = rich.get("rid") or rich.get("mid") or rich.get("id")
                name = text
                mentions.append({"mid": str(rid) if rid is not None else None, "name": name})
                if name:
                    plain_parts.append(name)
                    md_parts.append(name)
                continue

            # 话题
            if rich_type in ("RICH_TEXT_NODE_TYPE_TOPIC", "RICH_TEXT_NODE_TYPE_TAG"):
                if text:
                    topics.append(text)
                    plain_parts.append(text)
                    md_parts.append(text)
                continue

            # 兜底：当作普通文本
            if text:
                plain_parts.append(text)
                md_parts.append(text)

    return "".join(plain_parts), "".join(md_parts)


def format_request_error(e: Exception) -> str:
    """
    格式化HTTP请求异常信息
    
    httpx 的异常在某些情况下 str(e) 为空；
    这里补齐类型与 repr，便于排查问题
    
    Args:
        e: 异常对象
        
    Returns:
        str: 格式化的错误信息
    """
    msg = str(e).strip()
    if msg:
        return msg
    return f"{type(e).__name__}: {e!r}"
