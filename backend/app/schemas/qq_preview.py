"""Trusted Bot message identity and ephemeral parse/delivery receipts."""

from typing import Annotated, Literal

from pydantic import BaseModel, ConfigDict, Field


class QQPreviewRequest(BaseModel):
    model_config = ConfigDict(extra="forbid")

    bot_id: str = Field(pattern=r"^[0-9]{1,20}$")
    chat_id: str = Field(pattern=r"^[0-9]{1,20}$")
    private: bool
    user_id: str = Field(pattern=r"^[0-9]{1,20}$")
    message_id: str = Field(min_length=1, max_length=100)
    request_text: str = Field(default="", max_length=16000)
    urls: list[Annotated[str, Field(min_length=1, max_length=8192)]] = Field(min_length=1, max_length=20)


class QQPreviewItem(BaseModel):
    url: str
    status: Literal["sent", "unsupported", "failed", "delivery_unknown", "rate_limited"]
    text: str = ""
    message_id: str | None = None


class QQPreviewResponse(BaseModel):
    duplicate: bool = False
    items: list[QQPreviewItem] = Field(default_factory=list)
