import re
from typing import Optional, Dict, Any
from bs4 import BeautifulSoup
from .models import ZhihuPin, ZhihuAuthor
from .base import extract_initial_data, preprocess_zhihu_html, extract_images
from app.adapters.base import ParsedContent, LAYOUT_GALLERY
from app.adapters.utils import generate_title_from_text
from datetime import datetime

from urllib.parse import unquote, urlparse, parse_qs

def parse_pin(html_content: str, url: str) -> Optional[ParsedContent]:
    data = extract_initial_data(html_content)
    if not data:
        return None

    pin_id = url.split('/')[-1]
    entities = data.get('initialState', {}).get('entities', {})
    pin_data = entities.get('pins', {}).get(pin_id)

    if not pin_data:
        return None

    author_data = pin_data.get('author', {})
    if isinstance(author_data, str):
        # author is just an ID, look it up in users
        author_id = author_data
        author_data = entities.get('users', {}).get(author_id, {})

    author = ZhihuAuthor(
        id=author_data.get('id'),
        urlToken=author_data.get('urlToken'),
        name=author_data.get('name', 'Unknown'),
        avatarUrl=author_data.get('avatarUrl'),
        headline=author_data.get('headline'),
        gender=author_data.get('gender')
    )
    
    # 确保 pin_data['author'] 包含完整的作者信息，以便前端回退逻辑生效
    pin_data['author'] = author.model_dump()

    content_html = pin_data.get('contentHtml', '') or pin_data.get('content', '')
    if isinstance(content_html, list):
        # Sometimes content is a list of dicts, convert to text?
        # Usually it's HTML string. If list, it's rich content nodes.
        content_html = "" # Fallback or process list if needed
    
    # Preprocess HTML
    processed_html = preprocess_zhihu_html(content_html) if isinstance(content_html, str) else ""
    
    media_urls = []
    
    # Strategy 1: Extract from HTML
    media_urls.extend(extract_images(processed_html))
        
    # Strategy 2: Check explicit 'content' list for images
    if 'content' in pin_data and isinstance(pin_data['content'], list):
        for item in pin_data['content']:
            if isinstance(item, dict) and item.get('type') == 'image':
                url = item.get('url')
                if url and isinstance(url, str):
                    media_urls.append(url)
                    
    # --- 强力去重逻辑 (针对知乎不同尺寸后缀的同一图片) ---
    def get_zhihu_img_id(url):
        # 提取核心标识符，例如 v2-b93ed6e308f35de5c416930827326bf1
        match = re.search(r'(v2-[a-f0-9]+)', url)
        return match.group(1) if match else url

    unique_media = {}
    for u in media_urls:
        img_id = get_zhihu_img_id(u)
        # 如果已经有这个 ID 了，优先保留高清的 (通常带 720w 或 r)
        if img_id not in unique_media or ("720w" in u or "_r" in u):
            unique_media[img_id] = u
    
    media_urls = list(unique_media.values())

    # Remove author avatar from media_urls if present (exact match or similar pattern)
    if author.avatar_url or author.url_token:
        # 知乎头像通常包含用户 ID 或特定的 v2-xxx 标识
        avatar_identifiers = []
        if author.avatar_url:
            avatar_clean = author.avatar_url.split('?')[0]
            avatar_hash = re.search(r'v2-([a-f0-9]+)', avatar_clean)
            if avatar_hash:
                avatar_identifiers.append(avatar_hash.group(1))
        
        if author.url_token:
            avatar_identifiers.append(author.url_token)

        filtered_urls = []
        for u in media_urls:
            u_clean = u.split('?')[0]
            # 检查 URL 是否包含已知的头像标识符，或者具有明显的头像路径特征
            is_avatar = any(ident in u_clean for ident in avatar_identifiers if ident)
            if is_avatar and ("zhimg.com" in u_clean or "zhihu.com" in u_clean):
                if "/people/" in u_clean or "/v2-" in u_clean or "avatar" in u_clean.lower():
                    continue
            filtered_urls.append(u)
        media_urls = filtered_urls

    # Convert HTML to text for description (Pins are short)
    # Use Markdown for description to support links
    
    description = ""
    if 'content' in pin_data and isinstance(pin_data['content'], list):
         # Extract text from content nodes directly (preferred)
         parts = []
         for item in pin_data['content']:
             if isinstance(item, dict):
                 if item.get('type') == 'text':
                     # Handle simple HTML in text if present (like <br>)
                     text_content = item.get('content', '')
                     # If text contains HTML tags (like <a>), parse it to markdown
                     if '<a' in text_content or '<br' in text_content:
                         from markdownify import markdownify as md
                         text_content = md(text_content)
                     parts.append(text_content)
                 elif item.get('type') == 'link':
                     # Convert to Markdown link
                     url = item.get('url', '')
                     # Handle Zhihu redirect links
                     if 'link.zhihu.com' in url:
                         try:
                             parsed = urlparse(url)
                             query = parse_qs(parsed.query)
                             if 'target' in query:
                                 url = query['target'][0]
                         except:
                             pass
                     
                     title = item.get('title', 'Link')
                     parts.append(f"[{title}]({url})")
                 elif item.get('type') == 'hashtag':
                      parts.append(f" #{item.get('title')} ")
         description = "".join(parts)
    
    if not description and processed_html:
        # Fallback to HTML text extraction, trying to preserve links via Markdown conversion
        from markdownify import markdownify as md
        description = md(processed_html)

    created = pin_data.get('created')
    published_at = datetime.fromtimestamp(created) if created else None

    stats = {
        "like": pin_data.get('reactionCount', 0),
        "reply": pin_data.get('commentCount', 0),
        "share": pin_data.get('repinCount', 0),
        "reaction_count": pin_data.get('reactionCount', 0),
        "comment_count": pin_data.get('commentCount', 0),
        "repin_count": pin_data.get('repinCount', 0),
    }

    # 生成标题：使用通用工具函数
    pin_title = generate_title_from_text(description, max_len=60, fallback="知乎想法")

    # Construct Archive
    if isinstance(pin_data, dict):
        archive_images = [{"url": u} for u in media_urls]
        if author.avatar_url:
            archive_images.append({"url": author.avatar_url, "type": "avatar"})
            
        archive = {
            "version": 2,
            "type": "zhihu_pin",
            "title": pin_title,
            "plain_text": description,
            "markdown": description, # Pins are simple, just use plain text as markdown
            "images": archive_images,
            "links": [],
            "stored_images": [],
            "stored_videos": []
        }
        pin_data['archive'] = archive

    return ParsedContent(
        platform="zhihu",
        content_type="pin",
        content_id=str(pin_id),
        clean_url=url,
        title=pin_title,
        description=description,
        author_name=author.name,
        author_id=author.url_token or str(author.id),
        author_avatar_url=author.avatar_url,
        author_url=f"https://www.zhihu.com/people/{author.url_token}" if author.url_token else None,
        cover_url=media_urls[0] if media_urls else None,
        media_urls=media_urls,
        published_at=published_at,
        archive_metadata=pin_data,
        stats=stats,
        layout_type=LAYOUT_GALLERY,
    )
