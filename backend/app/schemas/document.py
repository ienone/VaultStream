"""Document reading is separate from time-based audio/video navigation."""

from typing import Literal

from pydantic import BaseModel, Field

DocumentTextStatus = Literal[
    "pending", "ready", "partial", "no_text", "encrypted", "invalid_pdf",
    "limit_exceeded", "timeout", "missing", "source_changed", "failed",
]


class DocumentPageItem(BaseModel):
    chunk_index: int = Field(ge=0)
    page_number: int = Field(ge=1)
    text: str
    source_kind: Literal["pdf_native_text"] = "pdf_native_text"


class DocumentTextItem(BaseModel):
    media_asset_id: int
    filename: str
    status: DocumentTextStatus
    page_count: int = 0
    text_page_count: int = 0
    pages: list[DocumentPageItem] = Field(default_factory=list)


class DocumentExtractionAcceptedResponse(BaseModel):
    content_id: int
    run_id: str = Field(min_length=1)
    status: Literal["processing"] = "processing"


class DocumentTextResponse(BaseModel):
    content_id: int
    documents: list[DocumentTextItem] = Field(default_factory=list)


class DocumentPageSearchItem(BaseModel):
    content_id: int
    content_title: str | None = None
    media_asset_id: int
    filename: str
    page_number: int
    excerpt: str
    match_source: Literal["text", "vector", "hybrid"]
    score: float
    route: str
