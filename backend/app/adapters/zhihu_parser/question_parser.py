from typing import Optional, Dict, Any
from markdownify import markdownify as md
from bs4 import BeautifulSoup
from .models import ZhihuQuestion, ZhihuAuthor
from .base import extract_initial_data
from app.adapters.base import ParsedContent
from datetime import datetime

def parse_question(html_content: str, url: str) -> Optional[ParsedContent]:
    data = extract_initial_data(html_content)
    if not data:
        return None

    question_id = url.split('/')[-1]
    entities = data.get('initialState', {}).get('entities', {})
    question_data = entities.get('questions', {}).get(question_id)

    if not question_data:
         # Fallback search
        if entities.get('questions'):
            # Try to match based on keys that look like IDs
            # But safer to just fail or pick first? Let's pick first if specific ID not found
            # but usually ID extraction from URL is reliable.
            # Handle cases where URL has query params
            question_id = question_id.split('?')[0]
            question_data = entities.get('questions', {}).get(question_id)
    
    if not question_data:
        return None

    # Author (Question asker)
    author_data = question_data.get('author', {})
    if isinstance(author_data, str):
        author_data = entities.get('users', {}).get(author_data, {})

    author = ZhihuAuthor(
        id=author_data.get('id'),
        urlToken=author_data.get('urlToken'),
        name=author_data.get('name', 'Anonymous'),
        avatarUrl=author_data.get('avatarUrl'),
        headline=author_data.get('headline'),
        gender=author_data.get('gender')
    )

    # Content/Detail
    detail_html = question_data.get('detail', '')
    
    # Preprocess HTML
    processed_html = preprocess_zhihu_html(detail_html)
    
    # Extract images (convert to links if needed, but for now we keep media_urls)
    # The prompt says "problem description images should be links to images".
    # Markdownify will turn img tags into ![alt](url). 
    # If we want links, we might need custom post-processing or just rely on media_urls being shown in gallery.
    # Let's rely on media_urls and maybe clean up markdown later if requested.
    # For now, standard extraction.
    media_urls = extract_images(processed_html)
    
    markdown_detail = md(processed_html, heading_style="ATX")

    # Stats
    stats = {
        "visit_count": question_data.get('visitCount', 0),
        "answer_count": question_data.get('answerCount', 0),
        "follower_count": question_data.get('followerCount', 0),
        "comment_count": question_data.get('commentCount', 0),
    }

    # Answers Preview - Structure them for Cards!
    top_answers = []
    answers_map = entities.get('answers', {})
    
    # Try to find the order if possible, otherwise just take first few
    # Usually 'question_data' might have an 'answers' list of IDs?
    # Or just use the map.
    
    count = 0
    for aid, ans in answers_map.items():
        if count >= 10: break
        
        a_author_data = ans.get('author', {})
        if isinstance(a_author_data, str):
            a_author_data = entities.get('users', {}).get(a_author_data, {})
            
        a_content = ans.get('content', '')
        a_processed = preprocess_zhihu_html(a_content)
        a_excerpt = ans.get('excerpt', '')
        
        # Extract first image from answer for cover
        a_images = extract_images(a_processed)
        a_cover = ans.get('thumbnail') or (a_images[0] if a_images else None)

        top_answers.append({
            "id": aid,
            "author": {
                "name": a_author_data.get('name', 'Unknown'),
                "avatar_url": a_author_data.get('avatarUrl'),
                "headline": a_author_data.get('headline'),
            },
            "excerpt": a_excerpt,
            "voteup_count": ans.get('voteupCount', 0),
            "comment_count": ans.get('commentCount', 0),
            "cover_url": a_cover,
            "url": f"https://www.zhihu.com/question/{question_id}/answer/{aid}",
            "created_time": ans.get('created_time') or ans.get('created'),
            "is_answer": True 
        })
        count += 1
    
    # Sort top answers by voteup_count if we just grabbed them randomly
    top_answers.sort(key=lambda x: x['voteup_count'], reverse=True)

    # Remove images from markdown if they are in media_urls (since we show them in gallery)
    # Markdownify converts img to ![alt](src). We can regex replace them.
    import re
    full_description = re.sub(r'!\[.*?\]\(.*?\)', '', markdown_detail).strip()
    # Also clean up excessive newlines
    full_description = re.sub(r'\n{3,}', '\n\n', full_description) 

    created = question_data.get('created')
    published_at = datetime.fromtimestamp(created) if created else None
    
    # Add answers to metadata
    if isinstance(question_data, dict):
        question_data['top_answers'] = top_answers

    return ParsedContent(
        platform="zhihu",
        content_type="question",
        content_id=str(question_id),
        clean_url=url,
        title=question_data.get('title'),
        description=full_description,
        author_name=author.name,
        author_id=author.url_token or str(author.id),
        cover_url=None, 
        media_urls=media_urls,
        published_at=published_at,
        raw_metadata=question_data,
        stats=stats
    )
