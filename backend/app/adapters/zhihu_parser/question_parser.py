from typing import Optional, Dict, Any
from markdownify import markdownify as md
from bs4 import BeautifulSoup
from .models import ZhihuQuestion, ZhihuAuthor
from .base import extract_initial_data, preprocess_zhihu_html, extract_images
from app.adapters.base import ParsedContent, LAYOUT_ARTICLE
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
        "view": question_data.get('visitCount', 0),
        "reply": question_data.get('answerCount', 0),
        "favorite": question_data.get('followerCount', 0),
        "like": question_data.get('voteupCount', 0) or 0,
        "comment_count": question_data.get('commentCount', 0),
        "visit_count": question_data.get('visitCount', 0),
        "answer_count": question_data.get('answerCount', 0),
        "follower_count": question_data.get('followerCount', 0),
    }

    # Answers Preview - Structure them for Cards!
    top_answers = []
    answers_map = entities.get('answers', {})
    
    # Try to find the order if possible, otherwise just take first few
    # Usually 'question_data' might have an 'answers' list of IDs?
    
    count = 0
    for aid, ans in answers_map.items():
        if count >= 10: break
        
        # Ensure answer belongs to this question
        if str(ans.get('question', {}).get('id')) != str(question_id):
            continue

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
            "author_name": a_author_data.get('name', 'Unknown'),
            "author_avatar_url": a_author_data.get('avatarUrl'),
            "author_headline": a_author_data.get('headline'),
            "excerpt": a_excerpt,
            "like_count": ans.get('voteupCount', 0),
            "comment_count": ans.get('commentCount', 0),
            "cover_url": a_cover,
            "url": f"https://www.zhihu.com/question/{question_id}/answer/{aid}",
            "created_time": ans.get('created_time') or ans.get('created'),
            "is_answer": True 
        })
        count += 1
    
    # Sort top answers by like_count if we just grabbed them randomly
    top_answers.sort(key=lambda x: x.get('like_count', 0), reverse=True)

    # Remove images from markdown if they are in media_urls (since we show them in gallery)
    # Using a more robust regex to remove markdown images and links to images
    import re
    # 1. Remove markdown images ![alt](url)
    full_description = re.sub(r'!\[.*?\]\(.*?\)', '', markdown_detail)
    # 2. Remove raw image URLs that are likely the same as media_urls
    # Only remove if it's a standalone line or followed by space/newline to avoid partial matching
    for m_url in media_urls:
        full_description = full_description.replace(m_url, '')

    # 3. Clean up leftover empty links or malformed markdown from images
    full_description = re.sub(r'\[\]\(\)', '', full_description)
    
    # 4. Also remove any remaining suspected image URLs (optional, but keep it safe)
    # full_description = re.sub(r'https?://\S+\.(?:jpg|jpeg|png|gif|webp)(?:\?\S+)?', '', full_description)
    
    full_description = full_description.strip()
    
    # Also clean up excessive newlines
    full_description = re.sub(r'\n{3,}', '\n\n', full_description) 

    created = question_data.get('created')
    published_at = datetime.fromtimestamp(created) if created else None
    
    # Add answers to metadata
    if isinstance(question_data, dict):
        question_data['top_answers'] = top_answers
        # Ensure stats are also in raw_metadata for frontend to find them if it looks there
        question_data['stats'] = stats
        
        # Build archive structure for media processing
        archive_images = [{"url": u} for u in media_urls]
        
        # Add question author avatar
        if author.avatar_url:
            archive_images.append({"url": author.avatar_url, "type": "avatar"})
        
        # Add top answers' avatars and covers
        for ans in top_answers:
            if ans.get('author_avatar_url'):
                archive_images.append({"url": ans['author_avatar_url'], "type": "answer_avatar"})
            if ans.get('cover_url'):
                archive_images.append({"url": ans['cover_url'], "type": "answer_cover"})
        
        question_data['archive'] = {
            "version": 2,
            "type": "zhihu_question",
            "title": question_data.get('title'),
            "plain_text": full_description,
            "markdown": full_description,
            "images": archive_images,
            "links": [],
            "stored_images": [],
        }

    return ParsedContent(
        platform="zhihu",
        content_type="question",
        content_id=str(question_id),
        clean_url=url,
        title=question_data.get('title'),
        description=full_description,
        author_name=author.name,
        author_id=author.url_token or str(author.id),
        # cover_url priority: 1. media_urls[0] (from description), 2. top_answer cover, 3. None
        cover_url=media_urls[0] if media_urls else (top_answers[0]['cover_url'] if top_answers and top_answers[0].get('cover_url') else None), 
        media_urls=media_urls,
        published_at=published_at,
        raw_metadata=question_data,
        stats=stats,
        layout_type=LAYOUT_ARTICLE,
    )
