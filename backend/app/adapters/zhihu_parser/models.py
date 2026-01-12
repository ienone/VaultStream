from typing import List, Optional, Any, Dict
from pydantic import BaseModel, Field

class ZhihuAuthor(BaseModel):
    """知乎用户/作者信息"""
    id: Optional[str] = None
    url_token: Optional[str] = Field(None, alias="urlToken")
    name: str = "Unknown"
    avatar_url: Optional[str] = Field(None, alias="avatarUrl")
    headline: Optional[str] = None
    type: str = "people"
    user_type: Optional[str] = Field(None, alias="userType")
    is_org: Optional[bool] = Field(False, alias="isOrg")
    gender: Optional[int] = None # 1: male, 0: female, -1: unknown
    follower_count: Optional[int] = Field(0, alias="followerCount")

    @property
    def profile_url(self) -> str:
        if self.url_token:
            return f"https://www.zhihu.com/people/{self.url_token}"
        return ""

class ZhihuTopic(BaseModel):
    """话题/标签"""
    id: str
    name: str
    avatar_url: Optional[str] = Field(None, alias="avatarUrl")

class ZhihuContentBase(BaseModel):
    """知乎内容基类 (Article, Answer, Pin, Question)"""
    id: str | int
    type: str
    title: Optional[str] = None
    url: str
    author: Optional[ZhihuAuthor] = None
    created: Optional[int] = None
    updated_time: Optional[int] = Field(None, alias="updatedTime")
    voteup_count: Optional[int] = Field(0, alias="voteupCount")
    comment_count: Optional[int] = Field(0, alias="commentCount")
    content: Optional[str] = None # HTML content, might be in 'content' or 'detail' or 'excerpt'
    
    # 原始数据
    raw_data: Dict[str, Any] = Field(default_factory=dict)
    
    topics: List[ZhihuTopic] = []

    def get_content_html(self) -> str:
        return self.content or ""

class ZhihuArticle(ZhihuContentBase):
    """专栏文章"""
    type: str = "article"
    title_image: Optional[str] = Field(None, alias="titleImage") # Cover

class ZhihuAnswer(ZhihuContentBase):
    """回答"""
    type: str = "answer"
    question: Optional[Any] = None # 关联的问题信息
    excerpt: Optional[str] = None

class ZhihuPin(ZhihuContentBase):
    """想法 (类似微博)"""
    type: str = "pin"
    content_html: Optional[str] = Field(None, alias="contentHtml")
    images: List[Dict[str, Any]] = [] # Pin specific image structure

    def get_content_html(self) -> str:
        return self.content_html or self.content or ""

class ZhihuQuestion(ZhihuContentBase):
    """问题"""
    type: str = "question"
    visit_count: Optional[int] = Field(0, alias="visitCount")
    answer_count: Optional[int] = Field(0, alias="answerCount")
    follower_count: Optional[int] = Field(0, alias="followerCount")
    detail: Optional[str] = None # Question detail

    def get_content_html(self) -> str:
        return self.detail or ""
