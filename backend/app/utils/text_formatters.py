"""
文本格式化工具模块

提供Telegram等平台的内容文本格式化功能
"""
import html
from typing import Dict, Any

from .formatters import format_number


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
    desc = content.get('summary') or content.get('description', '')
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
    # 分享卡片（ShareCard）不包含 raw_metadata：避免对外泄露"私有存档"信息
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
    type_icon = "📺"
    type_name = '视频'
    
    stats_lines = []
    if content_type == 'live':
        type_icon = "🌐"
        status_text = "直播中" if live_status == 1 else ("轮播中" if live_status == 2 else "未开播")
        type_name = f"直播 ({status_text})"
        # 直播间特有统计：人气值
        stats_lines.append(f"人气：{format_number(view)}")
    elif content_type == 'article':
        type_icon = "📝"
        type_name = "专栏"
        stats_lines.append(f"阅读：{format_number(view)} | 点赞：{format_number(like)} | 评论：{format_number(reply)}")
    elif content_type == 'dynamic':
        type_icon = "📱"
        type_name = "动态"
        stats_lines.append(f"点赞：{format_number(like)} | 转发：{format_number(share)} | 评论：{format_number(reply)}")
    else:
        # 视频/番剧通用模板
        if content_type == 'bangumi':
            type_icon = "🎬"
            type_name = '番剧/电影'
        
        stats_lines.append(f"播放：{format_number(view)} | 弹幕：{format_number(danmaku)} | 收藏：{format_number(favorite)}")
        stats_lines.append(f"点赞：{format_number(like)} | 硬币：{format_number(coin)} | 评论：{format_number(reply)}")

    lines = [
        f"<b>{type_icon} {title}</b>",
        f"类型：{type_name} | UP：{author}",
        f"日期：{pub_at}" if pub_at else "",
    ]
    lines.extend(stats_lines)
    lines.append(f"\n🔗 {url}")
    
    # 移除空行
    lines = [line for line in lines if line]
    
    # ShareCard 用 summary 字段；兼容旧字段 description
    desc = content.get('summary') or content.get('description', '')
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
        text_parts.append(f"<b>📌 {html.escape(str(content['title']))}</b>")
    if content.get('author_name'):
        text_parts.append(f"👤 {html.escape(str(content['author_name']))}")
    
    # 互动数据
    stats = []
    if content.get('view_count'): 
        stats.append(f"👁️ {format_number(content['view_count'])}")
    if content.get('like_count'): 
        stats.append(f"👍 {format_number(content['like_count'])}")
    if content.get('collect_count'): 
        stats.append(f"⭐ {format_number(content['collect_count'])}")
    if stats:
        text_parts.append(" | ".join(stats))

    if content.get('description'):
        desc = content['description']
        clean_desc = html.escape(desc[:200] + "..." if len(desc) > 200 else desc)
        text_parts.append(f"\n{clean_desc}")
        
    if content.get('tags'):
        tags_str = " ".join([f"#{tag}" for tag in content['tags']])
        text_parts.append(f"\n{tags_str}")
        
    text_parts.append(f"\n🔗 {url}")
    return "\n".join(text_parts)
