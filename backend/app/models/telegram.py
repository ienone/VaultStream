"""Remote message occurrences are independent of permanent collection sources."""
from sqlalchemy import BigInteger, ForeignKey, String, JSON, Index
from sqlalchemy.orm import Mapped, mapped_column
from app.models.base import Base


class TelegramMessage(Base):
    __tablename__ = "telegram_messages"
    __table_args__ = (Index("ix_telegram_messages_account_fingerprint", "account_id", "fingerprint"),)

    account_id: Mapped[int] = mapped_column(BigInteger, primary_key=True)
    peer_id: Mapped[int] = mapped_column(BigInteger, primary_key=True)
    message_id: Mapped[int] = mapped_column(BigInteger, primary_key=True)
    content_id: Mapped[int] = mapped_column(ForeignKey("contents.id", ondelete="CASCADE"), index=True)
    fingerprint: Mapped[str] = mapped_column(String(64))
    origin: Mapped[dict | None] = mapped_column(JSON, default=None)
