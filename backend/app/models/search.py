"""
语义检索相关模型定义
"""
from datetime import datetime
from typing import Any, Optional

from sqlalchemy import DateTime, ForeignKey, Index, Integer, String, Text, UniqueConstraint
from sqlalchemy.orm import Mapped, mapped_column, relationship
from sqlalchemy import JSON

from app.core.time_utils import utcnow
from app.models.base import Base


class ContentEmbedding(Base):
    """内容向量索引。每条内容最多一条当前向量记录。"""

    __tablename__ = "content_embeddings"
    __table_args__ = (
        UniqueConstraint("content_id", name="uq_content_embeddings_content_id"),
        Index("ix_content_embeddings_indexed_at", "indexed_at"),
        Index("ix_content_embeddings_model", "embedding_model"),
    )

    id: Mapped[int] = mapped_column(Integer, primary_key=True, index=True)
    content_id: Mapped[int] = mapped_column(
        Integer,
        ForeignKey("contents.id", ondelete="CASCADE"),
        index=True,
    )

    embedding_model: Mapped[str] = mapped_column(String(100), default="gemini-embedding-2-preview")
    embedding: Mapped[Any] = mapped_column(JSON, default=list)
    text_hash: Mapped[Optional[str]] = mapped_column(String(64), default=None)
    source_text: Mapped[Optional[str]] = mapped_column(Text, default=None)

    indexed_at: Mapped[Optional[datetime]] = mapped_column(DateTime, default=utcnow)
    created_at: Mapped[Optional[datetime]] = mapped_column(DateTime, default=utcnow)
    updated_at: Mapped[Optional[datetime]] = mapped_column(DateTime, default=utcnow, onupdate=utcnow)

    content = relationship("Content")
