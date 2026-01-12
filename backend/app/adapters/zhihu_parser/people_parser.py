from typing import Optional, Dict, Any
from .models import ZhihuAuthor
from .base import extract_initial_data
from app.adapters.base import ParsedContent
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
        # Sometimes key is not url_token but id?
        # But 'people' page usually loads user by urlToken
        # Try finding by name match? No.
        # Just grab the first user if strict match fails?
        # Usually entities['users'] has the target user + current user + others.
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
    }
    
    description = headline if headline else ""

    return ParsedContent(
        platform="zhihu",
        content_type="user_profile",
        content_id=str(user_data.get('id', url_token)),
        clean_url=url,
        title=f"{name} 的知乎主页",
        description=description,
        author_name=name,
        author_id=user_data.get('urlToken'),
        cover_url=avatar_url,
        media_urls=[avatar_url] if avatar_url else [],
        published_at=datetime.now(), # User profile doesn't have a specific pub date
        raw_metadata=user_data,
        stats=stats
    )
