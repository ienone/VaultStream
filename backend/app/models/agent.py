"""
Agent runtime persistence models.
"""
from datetime import datetime
from typing import Any, Optional

from sqlalchemy import DateTime, ForeignKey, Index, Integer, String, Text
from sqlalchemy import JSON
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.core.time_utils import utcnow
from app.models.base import Base


class AgentSession(Base):
    """A durable Agent conversation."""

    __tablename__ = "agent_sessions"
    __table_args__ = (
        Index("ix_agent_sessions_updated_at", "updated_at"),
    )

    id: Mapped[str] = mapped_column(String(64), primary_key=True)
    title: Mapped[str] = mapped_column(String(200), default="新会话")
    status: Mapped[str] = mapped_column(String(40), default="active", index=True)
    context_budget: Mapped[int] = mapped_column(Integer, default=6000)
    created_at: Mapped[datetime] = mapped_column(DateTime, default=utcnow)
    updated_at: Mapped[datetime] = mapped_column(DateTime, default=utcnow, onupdate=utcnow)
    last_message_at: Mapped[Optional[datetime]] = mapped_column(DateTime, default=None)
    deleted_at: Mapped[Optional[datetime]] = mapped_column(DateTime, default=None)

    messages = relationship("AgentMessage", back_populates="session")
    runs = relationship("AgentRun", back_populates="session")


class AgentMessage(Base):
    """A persisted conversation message."""

    __tablename__ = "agent_messages"
    __table_args__ = (
        Index("ix_agent_messages_session_created", "session_id", "created_at"),
    )

    id: Mapped[int] = mapped_column(Integer, primary_key=True, index=True)
    session_id: Mapped[str] = mapped_column(
        String(64),
        ForeignKey("agent_sessions.id", ondelete="CASCADE"),
        index=True,
    )
    run_id: Mapped[Optional[str]] = mapped_column(String(64), index=True, default=None)
    role: Mapped[str] = mapped_column(String(40), index=True)
    content: Mapped[str] = mapped_column(Text, default="")
    payload: Mapped[Optional[Any]] = mapped_column(JSON, default=dict)
    created_at: Mapped[datetime] = mapped_column(DateTime, default=utcnow, index=True)

    session = relationship("AgentSession", back_populates="messages")


class AgentRun(Base):
    """A single Agent execution attempt."""

    __tablename__ = "agent_runs"
    __table_args__ = (
        Index("ix_agent_runs_session_created", "session_id", "created_at"),
    )

    id: Mapped[str] = mapped_column(String(64), primary_key=True)
    session_id: Mapped[str] = mapped_column(
        String(64),
        ForeignKey("agent_sessions.id", ondelete="CASCADE"),
        index=True,
    )
    status: Mapped[str] = mapped_column(String(40), default="running", index=True)
    input_message: Mapped[str] = mapped_column(Text, default="")
    output_message: Mapped[Optional[str]] = mapped_column(Text, default=None)
    error_code: Mapped[Optional[str]] = mapped_column(String(120), default=None)
    error_message: Mapped[Optional[str]] = mapped_column(Text, default=None)
    usage: Mapped[Optional[Any]] = mapped_column(JSON, default=dict)
    created_at: Mapped[datetime] = mapped_column(DateTime, default=utcnow, index=True)
    updated_at: Mapped[datetime] = mapped_column(DateTime, default=utcnow, onupdate=utcnow)
    completed_at: Mapped[Optional[datetime]] = mapped_column(DateTime, default=None)

    session = relationship("AgentSession", back_populates="runs")


class AgentToolCall(Base):
    """A model-requested tool call and its result."""

    __tablename__ = "agent_tool_calls"
    __table_args__ = (
        Index("ix_agent_tool_calls_run_created", "run_id", "created_at"),
        Index("ix_agent_tool_calls_session_created", "session_id", "created_at"),
    )

    id: Mapped[str] = mapped_column(String(64), primary_key=True)
    run_id: Mapped[str] = mapped_column(String(64), ForeignKey("agent_runs.id", ondelete="CASCADE"), index=True)
    session_id: Mapped[str] = mapped_column(String(64), ForeignKey("agent_sessions.id", ondelete="CASCADE"), index=True)
    tool_name: Mapped[str] = mapped_column(String(120), index=True)
    permission_level: Mapped[str] = mapped_column(String(60), default="read")
    status: Mapped[str] = mapped_column(String(60), default="running", index=True)
    args: Mapped[Optional[Any]] = mapped_column(JSON, default=dict)
    result: Mapped[Optional[Any]] = mapped_column(JSON, default=None)
    error: Mapped[Optional[Any]] = mapped_column(JSON, default=None)
    created_at: Mapped[datetime] = mapped_column(DateTime, default=utcnow)
    completed_at: Mapped[Optional[datetime]] = mapped_column(DateTime, default=None)


class AgentConfirmation(Base):
    """A pending or decided confirmation for a side-effecting tool call."""

    __tablename__ = "agent_confirmations"
    __table_args__ = (
        Index("ix_agent_confirmations_session_status", "session_id", "status"),
        Index("ix_agent_confirmations_run_status", "run_id", "status"),
    )

    id: Mapped[str] = mapped_column(String(64), primary_key=True)
    session_id: Mapped[str] = mapped_column(String(64), ForeignKey("agent_sessions.id", ondelete="CASCADE"), index=True)
    run_id: Mapped[str] = mapped_column(String(64), ForeignKey("agent_runs.id", ondelete="CASCADE"), index=True)
    tool_call_id: Mapped[str] = mapped_column(String(64), ForeignKey("agent_tool_calls.id", ondelete="CASCADE"), index=True)
    tool_name: Mapped[str] = mapped_column(String(120), index=True)
    permission_level: Mapped[str] = mapped_column(String(60), default="write")
    status: Mapped[str] = mapped_column(String(40), default="pending", index=True)
    args: Mapped[Optional[Any]] = mapped_column(JSON, default=dict)
    summary: Mapped[str] = mapped_column(Text, default="")
    result: Mapped[Optional[Any]] = mapped_column(JSON, default=None)
    error: Mapped[Optional[Any]] = mapped_column(JSON, default=None)
    created_at: Mapped[datetime] = mapped_column(DateTime, default=utcnow)
    decided_at: Mapped[Optional[datetime]] = mapped_column(DateTime, default=None)


class AgentContextSummary(Base):
    """Traceable context compression output."""

    __tablename__ = "agent_context_summaries"
    __table_args__ = (
        Index("ix_agent_context_summaries_session_created", "session_id", "created_at"),
    )

    id: Mapped[int] = mapped_column(Integer, primary_key=True, index=True)
    session_id: Mapped[str] = mapped_column(String(64), ForeignKey("agent_sessions.id", ondelete="CASCADE"), index=True)
    run_id: Mapped[Optional[str]] = mapped_column(String(64), ForeignKey("agent_runs.id", ondelete="SET NULL"), default=None)
    summary: Mapped[str] = mapped_column(Text, default="")
    covered_message_count: Mapped[int] = mapped_column(Integer, default=0)
    token_estimate: Mapped[int] = mapped_column(Integer, default=0)
    created_at: Mapped[datetime] = mapped_column(DateTime, default=utcnow)
