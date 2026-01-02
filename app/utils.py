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
    url = content.get('clean_url') or content.get('url')
    content_type = content.get('content_type')
    
    pub_at = content.get('published_at')
    if pub_at and isinstance(pub_at, str):
        pub_at = pub_at.replace('T', ' ')
    
    # 转义标题和作者
    title = html.escape(content.get('title', '无标题'))
    author = html.escape(content.get('author_name', '未知'))
    
    # 互动数据
    stats_data = content.get('stats') or {}
    view = stats_data.get('view', 0)
    danmaku = stats_data.get('danmaku', 0)
    favorite = stats_data.get('favorite', 0)
    like = stats_data.get('like', 0)
    coin = stats_data.get('coin', 0)
    reply = stats_data.get('reply', 0)

    # 根据类型定制图标和标签
    type_icon = "📺"
    type_name = meta.get('tname', '视频')
    
    if content_type == 'article':
        type_icon = "📝"
        type_name = "专栏"
    elif content_type == 'bangumi':
        type_icon = "🎬"
        type_name = meta.get('type_desc', '番剧/电影')

    lines = [
        f"<b>{type_icon} {title}</b>",
        f"类型：{type_name} | UP：{author}",
        f"日期：{pub_at}" if pub_at else "",
        f"播放：{format_number(view)} | 弹幕：{format_number(danmaku)} | 收藏：{format_number(favorite)}",
        f"点赞：{format_number(like)} | 硬币：{format_number(coin)} | 评论：{format_number(reply)}",
        f"\n🔗 {url}",
    ]
    
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
    url = content.get('clean_url') or content.get('url')
    
    if content.get('title'):
        text_parts.append(f"<b>📌 {html.escape(content['title'])}</b>")
    if content.get('author_name'):
        text_parts.append(f"👤 {html.escape(content['author_name'])}")
    
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
