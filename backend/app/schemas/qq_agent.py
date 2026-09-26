"""QQ transport contract; identity is authorized by the server, never by the model."""
from typing import Any
import json

from pydantic import BaseModel, ConfigDict, Field, field_validator, model_validator
from urllib.parse import urlsplit

from app.schemas.agent import ContentParseError


class QQAttachment(BaseModel):
    model_config = ConfigDict(extra="forbid")
    url: str = Field(min_length=1, max_length=10000)
    filename: str = Field(min_length=1, max_length=500)
    mime_type: str | None = Field(default=None, max_length=200)


class QQMessageMaterial(BaseModel):
    model_config = ConfigDict(extra="forbid")
    message_id: str = Field(min_length=1, max_length=120)
    text: str = Field(default="", max_length=100000)
    links: list[str] = Field(default_factory=list, max_length=20)
    attachments: list[QQAttachment] = Field(default_factory=list, max_length=10)

    @field_validator("links")
    @classmethod
    def validate_links(cls, value):
        for url in value:
            parsed = urlsplit(url)
            if len(url) > 10000 or parsed.scheme not in {"http", "https"} or not parsed.hostname or parsed.username or parsed.password:
                raise ValueError("links must contain HTTP(S) URLs")
        return value


class QQAgentRequest(QQMessageMaterial):
    user_id: str = Field(pattern=r"^[0-9]{5,20}$")
    quote: QQMessageMaterial | None = None
    forwarded: list[QQMessageMaterial] = Field(default_factory=list, max_length=20)

    @model_validator(mode="after")
    def bounded_materials(self):
        if len(json.dumps(self.model_dump(), ensure_ascii=False).encode()) > 256 * 1024:
            raise ValueError("QQ message materials exceed 256 KiB")
        return self


class QQAgentDecisionRequest(BaseModel):
    model_config = ConfigDict(extra="forbid")
    user_id: str = Field(pattern=r"^[0-9]{5,20}$")
    approved: bool


class QQCaptureReceipt(BaseModel):
    content_id: int
    capture_kind: str
    status: str
    title: str | None = None
    author: str | None = None
    summary: str | None = None
    body: str | None = None
    url: str | None = None
    route: str
    collection_url: str | None = None
    parse_error: ContentParseError | None = None


class QQAgentResponse(BaseModel):
    session_id: str
    run_id: str
    status: str
    message: str = ""
    confirmation_required: bool = False
    confirmation: dict[str, Any] | None = None
    captures: list[QQCaptureReceipt] = Field(default_factory=list)
    duplicate: bool = False
