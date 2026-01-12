from typing import Optional, Dict, Any
from markdownify import markdownify as md
from bs4 import BeautifulSoup
from .models import ZhihuAnswer, ZhihuAuthor
from .base import extract_initial_data, preprocess_zhihu_html, extract_images
from app.adapters.base import ParsedContent
from datetime import datetime

def parse_answer(html_content: str, url: str) -> Optional[ParsedContent]:
    data = extract_initial_data(html_content)
    if not data:
        return None

    # URL format: https://www.zhihu.com/question/{question_id}/answer/{answer_id}
    # OR https://www.zhihu.com/answer/{answer_id} (redirects usually)
    
    parts = url.split('/')
    if 'answer' in parts:
        answer_id = parts[parts.index('answer') + 1]
    else:
        return None

    entities = data.get('initialState', {}).get('entities', {})
    answer_data = entities.get('answers', {}).get(answer_id)
    
    if not answer_data:
        # Fallback to searching values
        for k, v in entities.get('answers', {}).items():
            if str(k) == str(answer_id):
                answer_data = v
                break
    
    if not answer_data:
        return None

    # Related Question
    question_data = answer_data.get('question', {})
    if not question_data and 'questions' in entities:
         # Try to find the question in entities if not embedded
         qid = answer_data.get('question', {}).get('id') 
         # Wait, sometimes answer_data['question'] is a dict with minimal info
         if isinstance(question_data, dict) and 'id' in question_data:
             qid = question_data['id']
             if str(qid) in entities['questions']:
                 question_data = entities['questions'][str(qid)]
             elif int(qid) in entities['questions']: # check int key
                 question_data = entities['questions'][int(qid)]

    question_title = question_data.get('title') if isinstance(question_data, dict) else ""
    question_id = question_data.get('id') if isinstance(question_data, dict) else None

    # Author
    author_data = answer_data.get('author', {})
    if isinstance(author_data, str):
        author_data = entities.get('users', {}).get(author_data, {})

    author = ZhihuAuthor(
        id=author_data.get('id'),
        urlToken=author_data.get('urlToken'),
        name=author_data.get('name', 'Unknown'),
        avatarUrl=author_data.get('avatarUrl'),
        headline=author_data.get('headline'),
        gender=author_data.get('gender')
    )

    # Content
    content_html = answer_data.get('content', '')
    
    # Preprocess HTML (handle equations, code blocks, lazy images)
    processed_html = preprocess_zhihu_html(content_html)
    
    # Extract images using the improved helper
    media_urls = extract_images(processed_html)
    
    markdown_content = md(processed_html, heading_style="ATX")
    
    # The frontend now handles question title and layout separately
    full_description = markdown_content

    created = answer_data.get('created_time') or answer_data.get('created')
    updated = answer_data.get('updated_time') or answer_data.get('updatedTime')
    published_at = datetime.fromtimestamp(created) if created else None
    updated_at = datetime.fromtimestamp(updated) if updated else None

    # Standardize stats for universal mapping
    stats = {
        "like": answer_data.get('voteupCount', 0),
        "reply": answer_data.get('commentCount', 0),
        "thanks_count": answer_data.get('thanksCount', 0),
        "voteup_count": answer_data.get('voteupCount', 0),
        "comment_count": answer_data.get('commentCount', 0),
    }

    # Enrich raw_metadata with question info and stats for frontend
    if isinstance(answer_data, dict):
        answer_data['associated_question'] = {
            "id": question_id,
            "title": question_title,
            "url": f"https://www.zhihu.com/question/{question_id}" if question_id else None,
            "visit_count": question_data.get('visitCount', 0) if isinstance(question_data, dict) else 0,
            "answer_count": question_data.get('answerCount', 0) if isinstance(question_data, dict) else 0,
            "follower_count": question_data.get('followerCount', 0) if isinstance(question_data, dict) else 0,
            "comment_count": question_data.get('commentCount', 0) if isinstance(question_data, dict) else 0,
        }

    return ParsedContent(
        platform="zhihu",
        content_type="answer",
        content_id=str(answer_id),
        clean_url=url,
        title=f"回答：{question_title}" if question_title else f"知乎回答 {answer_id}",
        description=full_description,
        author_name=author.name,
        author_id=author.url_token or str(author.id),
        cover_url=answer_data.get('thumbnail') or (media_urls[0] if media_urls else None),
        media_urls=media_urls,
        published_at=published_at,
        raw_metadata=answer_data,
        stats=stats
    )
