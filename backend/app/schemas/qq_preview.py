"""QQ group preview contract; these resources never enter the collection."""

from typing import Annotated, Literal

from pydantic import BaseModel, ConfigDict, Field


class QQPreviewRequest(BaseModel):
    model_config = ConfigDict(extra="forbid")

    group_id: str = Field(pattern=r"^[0-9]{1,20}$")
    user_id: str = Field(pattern=r"^[0-9]{1,20}$")
    message_id: str = Field(min_length=1, max_length=100)
    urls: list[Annotated[str, Field(min_length=1, max_length=8192)]] = Field(min_length=1, max_length=20)
    reserve_send: bool = True


class QQPreviewItem(BaseModel):
    url: str
    status: Literal["parsed", "unsupported", "failed"]
    platform: str | None = None
    content_type: str | None = None
    title: str | None = None
    body: str | None = None
    author: str | None = None
    media_urls: list[str] = Field(default_factory=list)
    image_url: str | None = None
    text: str | None = None
    reason: str | None = None
    send_allowed: bool = False


class QQPreviewResponse(BaseModel):
    duplicate: bool = False
    items: list[QQPreviewItem] = Field(default_factory=list)
