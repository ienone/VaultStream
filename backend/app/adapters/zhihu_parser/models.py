from typing import Optional
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
