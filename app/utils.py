import re
import html
from typing import List, Optional

def normalize_bilibili_url(url_or_id: str) -> str:
    """规范化 B 站 URL，支持 BV/av/cv 号"""
    val = url_or_id.strip()
    if not val.startswith(('http://', 'https://')):
        val_lower = val.lower()
        if val_lower.startswith('bv'):
            return f"https://www.bilibili.com/video/{val}"
        elif val_lower.startswith('av'):
            return f"https://www.bilibili.com/video/{val}"
        elif val_lower.startswith('cv'):
            return f"https://www.bilibili.com/read/{val}"
    return val

def parse_tags(tags_str: str) -> List[str]:
    """解析标签字符串，支持中英文逗号、顿号分隔"""
    if not tags_str:
        return []
    # 兼容 , ， 、 分隔
    tags = re.split(r'[,，、]', tags_str)
    return [t.strip() for t in tags if t.strip()]

def format_number(num) -> str:
    """格式化数字，超过1万显示为'万'"""
    if not num: return "0"
    try:
        n = int(num)
        if n >= 10000:
            return f"{n/10000:.2f}万"
        return str(n)
    except:
        return str(num)

def format_content_for_tg(content_dict: dict) -> str:
    """为 Telegram 格式化内容文本"""
    platform = content_dict.get('platform')
    if platform == 'bilibili':
        return _format_bilibili_message(content_dict)
    return _format_default_message(content_dict)

def _format_bilibili_message(content: dict) -> str:
    """格式化B站特有的消息内容"""
    meta = content.get('raw_metadata', {}) or {}
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
    type_name = meta.get('tname', '视频')
    
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
            type_name = meta.get('type_desc', '番剧/电影')
        
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
    
    desc = content.get('description', '')
    if desc:
        clean_desc = html.escape(desc[:300] + "..." if len(desc) > 300 else desc)
        lines.append(f"\n简介：\n{clean_desc}")
        
    if content.get('tags'):
        tags_str = " ".join([f"#{tag}" for tag in content['tags']])
        lines.append(f"\n{tags_str}")
        
    return "\n".join(lines)

def _format_default_message(content: dict) -> str:
    """默认的消息格式"""
    text_parts = []
    url = content.get('clean_url') or content.get('url') or ""
    
    if content.get('title'):
        text_parts.append(f"<b>📌 {html.escape(str(content['title']))}</b>")
    if content.get('author_name'):
        text_parts.append(f"👤 {html.escape(str(content['author_name']))}")
    
    # 互动数据
    stats = []
    if content.get('view_count'): stats.append(f"👁️ {format_number(content['view_count'])}")
    if content.get('like_count'): stats.append(f"👍 {format_number(content['like_count'])}")
    if content.get('collect_count'): stats.append(f"⭐ {format_number(content['collect_count'])}")
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
