"""
文本格式化工具模块

提供Telegram等平台的内容文本格式化功能
"""
import html
import re
from datetime import datetime
from typing import Dict, Any, Optional


def format_number(num) -> str:
    """格式化数字，超过1万显示为“万”单位。"""
    if not num:
        return "0"
    try:
        n = int(num)
        if n >= 10000:
            return f"{n / 10000:.2f}万"
        return str(n)
    except Exception:
        return str(num)


def strip_markdown(text: str) -> str:
    """Remove common Markdown formatting for plain-text platforms (e.g. QQ).

    Handles: headings, bold/italic, images, links, inline code,
    block quotes, horizontal rules, and stray markup characters.
    """
    if not text:
        return text
    # Images: ![alt](url) → alt, or remove entirely if alt is empty
    text = re.sub(r'!\[([^\]]*)\]\([^)]+\)', r'\1', text)
    # Links: [text](url) → text
    text = re.sub(r'\[([^\]]+)\]\([^)]+\)', r'\1', text)
    # Headings: ### heading → heading
    text = re.sub(r'^#{1,6}\s+', '', text, flags=re.MULTILINE)
    # Bold/italic: **text** or __text__ → text
    text = re.sub(r'\*\*(.+?)\*\*', r'\1', text)
    text = re.sub(r'__(.+?)__', r'\1', text)
    # Italic: *text* or _text_ → text (careful not to match underscores in words)
    text = re.sub(r'(?<!\w)\*(.+?)\*(?!\w)', r'\1', text)
    text = re.sub(r'(?<!\w)_(.+?)_(?!\w)', r'\1', text)
    # Strikethrough: ~~text~~ → text
    text = re.sub(r'~~(.+?)~~', r'\1', text)
    # Inline code: `code` → code
    text = re.sub(r'`([^`]+)`', r'\1', text)
    # Block quotes: > text → text
    text = re.sub(r'^>\s?', '', text, flags=re.MULTILINE)
    # Horizontal rules: --- or *** or ___ → (remove)
    text = re.sub(r'^[-*_]{3,}\s*$', '', text, flags=re.MULTILINE)
    # Clean up multiple blank lines
    text = re.sub(r'\n{3,}', '\n\n', text)
    return text.strip()


_DEFAULT_RENDER_CONFIG = {
    "show_platform_id": True,
    "show_title": True,
    "show_tags": False,
    "author_mode": "full",
    "content_mode": "summary",
    "media_mode": "auto",
    "link_mode": "clean",
    "header_text": "",
    "footer_text": "",
}

_PLATFORM_LABELS = {
    "bilibili": "Bilibili",
    "twitter": "Twitter/X",
    "xiaohongshu": "Xiaohongshu",
    "douyin": "Douyin",
    "weibo": "Weibo",
    "zhihu": "Zhihu",
    "ku_an": "KuAn",
    "universal": "Universal",
}


def _normalize_render_config(render_config: Optional[Dict[str, Any]]) -> Dict[str, Any]:
    if not render_config:
        return {}
    if isinstance(render_config, dict) and isinstance(render_config.get("structure"), dict):
        return {**render_config.get("structure", {})}
    return {**render_config}


def _apply_template(text: str, content: Dict[str, Any]) -> str:
    if not text:
        return ""
    date_value = datetime.utcnow().strftime("%Y-%m-%d")
    title_value = str(content.get("title") or content.get("body") or "")
    return text.replace("{{date}}", date_value).replace("{{title}}", title_value)


def format_content_with_render_config(
    content_dict: Dict[str, Any],
    render_config: Dict[str, Any],
    *,
    rich_text: bool,
    platform: str,
) -> str:
    """
    根据 render_config 渲染内容文本

    Args:
        content_dict: 内容数据字典
        render_config: 渲染配置
        rich_text: 是否使用富文本（Telegram HTML）
        platform: 目标平台名称
    """
    config = {**_DEFAULT_RENDER_CONFIG, **_normalize_render_config(render_config)}

    def escape(value: str) -> str:
        return html.escape(value) if rich_text else value

    lines = []

    header_text = _apply_template(str(config.get("header_text") or ""), content_dict)
    if header_text:
        lines.append(escape(header_text))

    if config.get("show_platform_id"):
        label = _PLATFORM_LABELS.get(platform, platform)
        lines.append(f"平台：{escape(str(label))}")

    if config.get("show_title"):
        title = str(content_dict.get("title") or content_dict.get("body") or "")
        if title:
            title_text = escape(title)
            if rich_text:
                title_text = f"<b>{title_text}</b>"
            lines.append(title_text)

    author_mode = config.get("author_mode", "full")
    if author_mode and author_mode != "none":
        author_name = content_dict.get("author_name")
        author_id = content_dict.get("author_id")
        if author_name:
            author_text = escape(str(author_name))
            if author_mode == "full" and author_id:
                author_text = f"{author_text} ({escape(str(author_id))})"
            lines.append(f"作者：{author_text}")

    content_mode = config.get("content_mode", "summary")
    if content_mode and content_mode != "hidden":
        desc = content_dict.get("summary") or content_dict.get("body") or ""
        if desc:
            if content_mode == "summary" and len(desc) > 200:
                desc = desc[:200] + "..."
            lines.append(escape(str(desc)))

    link_mode = config.get("link_mode", "clean")
    link = ""
    if link_mode == "original":
        link = content_dict.get("url") or content_dict.get("canonical_url") or ""
    elif link_mode == "clean":
        link = content_dict.get("clean_url") or content_dict.get("canonical_url") or content_dict.get("url") or ""
    if link_mode != "none" and link:
        lines.append(f"链接：{escape(str(link))}")

    if config.get("show_tags") and content_dict.get("tags"):
        tags = " ".join([f"#{tag}" for tag in content_dict.get("tags") or []])
        lines.append(escape(tags))

    footer_text = _apply_template(str(config.get("footer_text") or ""), content_dict)
    if footer_text:
        lines.append(escape(footer_text))

    return "\n".join([line for line in lines if line])


def format_content_for_tg(content_dict: dict) -> str:
    """
    为 Telegram 格式化内容文本
    
    根据不同平台选择合适的格式化方法
    
    Args:
        content_dict: 内容字典，包含platform、title、description等字段
        
    Returns:
        格式化后的Telegram消息文本（支持HTML格式）
    """
    platform = content_dict.get('platform')
    if platform == 'bilibili':
        return _format_bilibili_message(content_dict)
    elif platform == 'twitter':
        return _format_twitter_message(content_dict)
    return _format_default_message(content_dict)


def _format_twitter_message(content: dict) -> str:
    """
    格式化 Twitter/X 特有的消息内容
    
    Args:
        content: Twitter内容字典
        
    Returns:
        格式化后的消息文本
    """
    url = content.get('clean_url') or content.get('url') or ""
    
    # 转义标题和作者
    author_name = html.escape(str(content.get('author_name') or '未知'))
    author_handle = content.get('extra_stats', {}).get('screen_name', '')
    if author_handle:
        author_display = f"{author_name} (@{author_handle})"
    else:
        author_display = author_name
    
    # 发布时间
    pub_at = content.get('published_at')
    if pub_at and isinstance(pub_at, str):
        pub_at = pub_at.replace('T', ' ')
    
    # 互动数据
    views = content.get('view_count', 0)
    likes = content.get('like_count', 0)
    retweets = content.get('share_count', 0)  # Twitter 的转发
    replies = content.get('comment_count', 0)
    
    # 从 extra_stats 获取更多 Twitter 特有数据
    extra = content.get('extra_stats', {}) or {}
    bookmarks = extra.get('bookmarks', 0)
    is_reply = extra.get('replying_to')
    
    lines = []
    
    # 作者信息
    lines.append(f"{author_display}")
    
    # 如果是回复推文
    if is_reply:
        lines.append(f"回复：@{is_reply}")
    
    # 发布时间
    if pub_at:
        lines.append(f"时间：{pub_at}")
    
    # 互动统计
    stats_parts = []
    if views:
        stats_parts.append(f"浏览 {format_number(views)}")
    if likes:
        stats_parts.append(f"点赞 {format_number(likes)}")
    if retweets:
        stats_parts.append(f"转发 {format_number(retweets)}")
    if replies:
        stats_parts.append(f"回复 {format_number(replies)}")
    if bookmarks:
        stats_parts.append(f"收藏 {format_number(bookmarks)}")
    
    if stats_parts:
        lines.append(" | ".join(stats_parts))
    
    # 正文内容
    desc = content.get('summary') or content.get('body', '')
    if desc:
        clean_desc = html.escape(desc[:500] + "..." if len(desc) > 500 else desc)
        lines.append(f"\n{clean_desc}")
    
    # 链接
    lines.append(f"\n链接：{url}")
    
    # 标签
    if content.get('tags'):
        tags_str = " ".join([f"#{tag}" for tag in content['tags']])
        lines.append(f"\n{tags_str}")
    
    return "\n".join(lines)


def _format_bilibili_message(content: dict) -> str:
    """
    格式化B站特有的消息内容
    
    Args:
        content: B站内容字典
        
    Returns:
        格式化后的消息文本（HTML格式）
    """
    # 分享卡片（ShareCard）不包含 archive_metadata：避免对外泄露"私有存档"信息
    url = content.get('clean_url') or content.get('url') or ""
    content_type = content.get('content_type')
    
    pub_at = content.get('published_at')
    if pub_at and isinstance(pub_at, str):
        pub_at = pub_at.replace('T', ' ')
    
    # 转义标题和作者，确保不为 None
    title = html.escape(str(content.get('title') or '无标题'))
    author = html.escape(str(content.get('author_name') or '未知'))
    
    # 互动数据：从 ContentDetail 字段获取
    view = content.get('view_count', 0)
    like = content.get('like_count', 0)
    favorite = content.get('collect_count', 0)
    share = content.get('share_count', 0)
    reply = content.get('comment_count', 0)
    
    # 平台特有数据
    extra = content.get('extra_stats', {}) or {}
    coin = extra.get('coin', 0)
    danmaku = extra.get('danmaku', 0)
    live_status = extra.get('live_status', 0)

    # 根据类型定制图标和标签
    type_label = "[视频]"
    
    stats_lines = []
    if content_type == 'live':
        status_text = "直播中" if live_status == 1 else ("轮播中" if live_status == 2 else "未开播")
        type_label = f"[直播 {status_text}]"
        # 直播间特有统计：人气值
        stats_lines.append(f"人气：{format_number(view)}")
    elif content_type == 'article':
        type_label = "[专栏]"
        stats_lines.append(f"阅读：{format_number(view)} | 点赞：{format_number(like)} | 评论：{format_number(reply)}")
    elif content_type == 'dynamic':
        type_label = "[动态]"
        stats_lines.append(f"点赞：{format_number(like)} | 转发：{format_number(share)} | 评论：{format_number(reply)}")
    else:
        # 视频/番剧通用模板
        if content_type == 'bangumi':
            type_label = "[番剧/电影]"
        
        stats_lines.append(f"播放：{format_number(view)} | 弹幕：{format_number(danmaku)} | 收藏：{format_number(favorite)}")
        stats_lines.append(f"点赞：{format_number(like)} | 硬币：{format_number(coin)} | 评论：{format_number(reply)}")

    lines = [
        f"<b>{type_label} {title}</b>",
        f"UP：{author}",
        f"日期：{pub_at}" if pub_at else "",
    ]
    lines.extend(stats_lines)
    lines.append(f"\n链接：{url}")
    
    # 移除空行
    lines = [line for line in lines if line]
    
    # ShareCard 优先使用 summary，若为空则使用 body
    desc = content.get('summary') or content.get('body', '')
    if desc:
        clean_desc = html.escape(desc[:300] + "..." if len(desc) > 300 else desc)
        lines.append(f"\n简介：\n{clean_desc}")
        
    if content.get('tags'):
        tags_str = " ".join([f"#{tag}" for tag in content['tags']])
        lines.append(f"\n{tags_str}")
        
    return "\n".join(lines)


def _format_default_message(content: dict) -> str:
    """
    默认的消息格式（通用平台）
    
    Args:
        content: 内容字典
        
    Returns:
        格式化后的消息文本
    """
    text_parts = []
    url = content.get('clean_url') or content.get('url') or ""
    
    if content.get('title'):
        text_parts.append(f"<b>{html.escape(str(content['title']))}</b>")
    if content.get('author_name'):
        text_parts.append(f"作者：{html.escape(str(content['author_name']))}")
    
    # 互动数据
    stats = []
    if content.get('view_count'): 
        stats.append(f"浏览 {format_number(content['view_count'])}")
    if content.get('like_count'): 
        stats.append(f"点赞 {format_number(content['like_count'])}")
    if content.get('collect_count'): 
        stats.append(f"收藏 {format_number(content['collect_count'])}")
    if stats:
        text_parts.append(" | ".join(stats))

    if content.get('body'):
        desc = content['body']
        clean_desc = html.escape(desc[:200] + "..." if len(desc) > 200 else desc)
        text_parts.append(f"\n{clean_desc}")
        
    if content.get('tags'):
        tags_str = " ".join([f"#{tag}" for tag in content['tags']])
        text_parts.append(f"\n{tags_str}")
        
    text_parts.append(f"\n链接：{url}")
    return "\n".join(text_parts)
