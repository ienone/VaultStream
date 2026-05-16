"""
语义检索相关模型定义
"""
from datetime import datetime
from typing import Any, Optional

from sqlalchemy import DateTime, ForeignKey, Index, Integer, String, Text
from sqlalchemy.orm import Mapped, mapped_column, relationship
from sqlalchemy import JSON

from app.core.time_utils import utcnow
from app.models.base import Base


class ContentEmbedding(Base):
    """内容向量索引。支持一篇文章多个语义切片。"""

    __tablename__ = "content_embeddings"
    __table_args__ = (
        Index("ix_content_embeddings_content_chunk", "content_id", "chunk_index"),
        Index("ix_content_embeddings_indexed_at", "indexed_at"),
        Index("ix_content_embeddings_model", "embedding_model"),
    )


    id: Mapped[int] = mapped_column(Integer, primary_key=True, index=True)
    content_id: Mapped[int] = mapped_column(
        Integer,
        ForeignKey("contents.id", ondelete="CASCADE"),
        index=True,
    )

    chunk_index: Mapped[int] = mapped_column(Integer, default=-1, index=True) # -1 表示全文/摘要，0+ 表示语义块
    chunk_title: Mapped[Optional[str]] = mapped_column(Text, default=None)

    embedding_model: Mapped[str] = mapped_column(String(200), default="gemini-embedding-2")
    embedding_model_signature: Mapped[Optional[str]] = mapped_column(String(240), default=None, index=True)
    embedding: Mapped[Any] = mapped_column(JSON, default=list)
    text_hash: Mapped[Optional[str]] = mapped_column(String(64), default=None)
    source_text: Mapped[Optional[str]] = mapped_column(Text, default=None)
    index_status: Mapped[str] = mapped_column(String(40), default="pending", index=True)
    failure_reason: Mapped[Optional[str]] = mapped_column(Text, default=None)
    retry_count: Mapped[int] = mapped_column(Integer, default=0)
    last_indexed_at: Mapped[Optional[datetime]] = mapped_column(DateTime, default=None)

    indexed_at: Mapped[Optional[datetime]] = mapped_column(DateTime, default=utcnow)
    created_at: Mapped[Optional[datetime]] = mapped_column(DateTime, default=utcnow)
    updated_at: Mapped[Optional[datetime]] = mapped_column(DateTime, default=utcnow, onupdate=utcnow)

    content = relationship("Content")
