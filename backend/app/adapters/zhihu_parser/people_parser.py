from typing import Optional, Dict, Any
from .models import ZhihuAuthor
from .base import extract_initial_data
from app.adapters.base import ParsedContent, LAYOUT_GALLERY
from datetime import datetime

def parse_people(html_content: str, url: str) -> Optional[ParsedContent]:
    data = extract_initial_data(html_content)
    if not data:
        return None

    # URL: https://www.zhihu.com/people/{url_token}
    url_token = url.split('/')[-1]
    
    entities = data.get('initialState', {}).get('entities', {})
    users = entities.get('users', {})
    
    user_data = users.get(url_token)
    if not user_data:
        pass

    if not user_data:
        # Basic implementation: try to find one that matches urlToken in values
        for u in users.values():
            if u.get('urlToken') == url_token:
                user_data = u
                break
    
    if not user_data:
        return None

    name = user_data.get('name', 'Unknown')
    headline = user_data.get('headline', '')
    avatar_url = user_data.get('avatarUrl')
    
    stats = {
        "view": user_data.get('followerCount', 0), # Mapping follower to view for consistency with weibo user profile mapping
        "share": user_data.get('followingCount', 0), 
        "like": user_data.get('thankedCount', 0),
        "favorite": user_data.get('favoritedCount', 0),
        "follower_count": user_data.get('followerCount', 0),
        "following_count": user_data.get('followingCount', 0),
        "voteup_count": user_data.get('voteupCount', 0),
        "thanked_count": user_data.get('thankedCount', 0),
        "favorited_count": user_data.get('favoritedCount', 0),
        "logs_count": user_data.get('logsCount', 0), # 参与公共编辑次数
        "following_columns_count": user_data.get('followingColumnsCount', 0),
        "following_topic_count": user_data.get('followingTopicCount', 0),
        "following_question_count": user_data.get('followingQuestionCount', 0),
        "following_favlists_count": user_data.get('followingFavlistsCount', 0),
        "answer_count": user_data.get('answerCount', 0),
        "articles_count": user_data.get('articlesCount', 0),
        "pins_count": user_data.get('pinsCount', 0),
        "question_count": user_data.get('questionCount', 0),
    }
    
    description = headline if headline else ""

    url_token = user_data.get('urlToken')
    
    return ParsedContent(
        platform="zhihu",
        content_type="user_profile",
        content_id=str(user_data.get('id', url_token)),
        clean_url=url,
        title=f"{name} 的知乎主页",
        description=description,
        author_name=name,
        author_id=url_token,
        author_avatar_url=avatar_url,
        author_url=f"https://www.zhihu.com/people/{url_token}" if url_token else None,
        cover_url=avatar_url,
        media_urls=[avatar_url] if avatar_url else [],
        published_at=datetime.now(), # User profile doesn't have a specific pub date
        archive_metadata={"raw_api_response": user_data},
        stats=stats,
        layout_type=LAYOUT_GALLERY,
    )
