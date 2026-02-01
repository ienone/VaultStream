from typing import Optional, Dict, Any
from markdownify import markdownify as md
from bs4 import BeautifulSoup
from .models import ZhihuArticle, ZhihuAuthor, ZhihuTopic
from .base import extract_initial_data, preprocess_zhihu_html, extract_images
from app.adapters.base import ParsedContent, LAYOUT_ARTICLE
from datetime import datetime

def parse_article(html_content: str, url: str) -> Optional[ParsedContent]:
    data = extract_initial_data(html_content)
    if not data:
        return None

    # Article ID is typically at the end of the URL
    article_id = url.split('/')[-1]
    
    # Locate article in entities
    entities = data.get('initialState', {}).get('entities', {})
    article_data = entities.get('articles', {}).get(article_id)
    
    if not article_data:
        # Fallback: try to find any article if ID mismatch (unlikely but possible with redirects)
        if entities.get('articles'):
            article_data = list(entities['articles'].values())[0]
        else:
            return None

    # Author
    author_data = article_data.get('author', {})
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

    # Topics
    topics = []
    for t in article_data.get('topics', []):
        topics.append(t.get('name'))

    # Content Processing
    content_html = article_data.get('content', '')
    
    # Preprocess HTML
    processed_html = preprocess_zhihu_html(content_html)
    
    # Extract images
    media_urls = extract_images(processed_html)

    # Convert to Markdown
    markdown_content = md(processed_html, heading_style="ATX")
    
    # Timestamps
    created = article_data.get('created')
    updated = article_data.get('updated')
    published_at = datetime.fromtimestamp(created) if created else None
    
    # Stats
    stats = {
        "like": article_data.get('voteupCount', 0),
        "reply": article_data.get('commentCount', 0),
        "favorite": article_data.get('favoritedCount', 0),
        "voteup_count": article_data.get('voteupCount', 0),
        "comment_count": article_data.get('commentCount', 0),
        "favorited_count": article_data.get('favoritedCount', 0),
    }

    if isinstance(article_data, dict):
        article_data['stats'] = stats

        # Construct Archive
        archive_images = [{"url": u} for u in media_urls]
        if author.avatar_url:
            archive_images.append({"url": author.avatar_url, "type": "avatar"})

        archive = {
            "version": 2,
            "type": "zhihu_article",
            "title": article_data.get('title', ''),
            "plain_text": BeautifulSoup(processed_html, 'html.parser').get_text("\n"),
            "markdown": markdown_content,
            "images": archive_images,
            "links": [],
            "stored_images": []
        }
        article_data['archive'] = archive
    
    # Cover URL logic: titleImage -> imageUrl -> first image in content
    cover_url = article_data.get('titleImage') or article_data.get('imageUrl')
    if not cover_url and media_urls:
        cover_url = media_urls[0]

    return ParsedContent(
        platform="zhihu",
        content_type="article",
        content_id=str(article_id),
        clean_url=url,
        title=article_data.get('title'),
        description=markdown_content,
        author_name=author.name,
        author_id=author.url_token or str(author.id),
        author_avatar_url=author.avatar_url,
        cover_url=cover_url,
        media_urls=media_urls,
        published_at=published_at,
        raw_metadata=article_data,
        stats=stats,
        layout_type=LAYOUT_ARTICLE,
    )
