from typing import Optional, Dict, Any
from bs4 import BeautifulSoup
from .models import ZhihuPin, ZhihuAuthor
from .base import extract_initial_data, preprocess_zhihu_html, extract_images
from app.adapters.base import ParsedContent
from datetime import datetime

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
                    
    # Deduplicate preserving order
    media_urls = list(dict.fromkeys(media_urls))

    # Convert HTML to text for description (Pins are short)
    description = ""
    if processed_html:
        description = BeautifulSoup(processed_html, 'html.parser').get_text("\n")
    elif 'content' in pin_data and isinstance(pin_data['content'], list):
         # Extract text from content nodes
         parts = []
         for item in pin_data['content']:
             if isinstance(item, dict) and item.get('type') == 'text':
                 parts.append(item.get('content', ''))
         description = "\n".join(parts)

    created = pin_data.get('created')
    published_at = datetime.fromtimestamp(created) if created else None

    stats = {
        "reaction_count": pin_data.get('reactionCount', 0),
        "comment_count": pin_data.get('commentCount', 0),
        "repin_count": pin_data.get('repinCount', 0),
        "like_count": pin_data.get('likeCount', 0),
    }

    return ParsedContent(
        platform="zhihu",
        content_type="pin",
        content_id=str(pin_id),
        clean_url=url,
        title=description[:50] + "..." if description else "Zhihu Pin",
        description=description,
        author_name=author.name,
        author_id=author.url_token or str(author.id),
        cover_url=media_urls[0] if media_urls else None,
        media_urls=media_urls,
        published_at=published_at,
        raw_metadata=pin_data,
        stats=stats
    )
