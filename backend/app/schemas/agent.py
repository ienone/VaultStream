"""
Agent / Tool Calling schemas.
"""
from datetime import datetime
from typing import Any, Dict, List, Optional

from pydantic import BaseModel, ConfigDict, Field


class AgentToolInfo(BaseModel):
    name: str
    description: str
    permission_level: str = "read"
    risk_level: str = "read"
    require_confirmation: bool = False
    permissions: List[str] = Field(default_factory=list)
    args_schema: Dict[str, Any] = Field(default_factory=dict)
    result_schema: Dict[str, Any] = Field(default_factory=dict)


class AgentToolInvokeRequest(BaseModel):
    args: Dict[str, Any] = Field(default_factory=dict)
    confirmed: bool = False


class AgentToolInvokeResponse(BaseModel):
    tool: str
    ok: bool
    result: Optional[Dict[str, Any]] = None
    error_code: Optional[str] = None
    error_message: Optional[str] = None
    error: Optional[str] = None
    confirmation_required: bool = False
    confirmation: Optional[Dict[str, Any]] = None


class AgentRunRequest(BaseModel):
    message: str
    session_id: Optional[str] = None
    stream: bool = False


class AgentRunResponse(BaseModel):
    session_id: str
    run_id: str
    status: str
    tool: Optional[str] = None
    message: str = ""
    result: Dict[str, Any] = Field(default_factory=dict)
    events: List[Dict[str, Any]] = Field(default_factory=list)
    confirmation_required: bool = False
    confirmation: Optional[Dict[str, Any]] = None
    usage: Dict[str, Any] = Field(default_factory=dict)


class AgentSessionCreateRequest(BaseModel):
    title: Optional[str] = None


class AgentSessionUpdateRequest(BaseModel):
    title: str = Field(min_length=1, max_length=200)


class AgentSessionItem(BaseModel):
    id: str
    title: str
    status: str
    created_at: datetime
    updated_at: datetime
    last_message_at: Optional[datetime] = None
    pending_confirmations: int = 0

    model_config = ConfigDict(from_attributes=True)


class AgentSessionListResponse(BaseModel):
    sessions: List[AgentSessionItem]


class AgentMessageItem(BaseModel):
    id: int
    session_id: str
    run_id: Optional[str] = None
    role: str
    content: str
    payload: Dict[str, Any] = Field(default_factory=dict)
    created_at: datetime

    model_config = ConfigDict(from_attributes=True)


class AgentMessageListResponse(BaseModel):
    messages: List[AgentMessageItem]
    next_before_id: Optional[int] = None


class AgentConfirmationDecisionRequest(BaseModel):
    approved: bool


class AgentConfirmationResponse(BaseModel):
    id: str
    session_id: str
    run_id: str
    tool_call_id: str
    tool_name: str
    permission_level: str
    status: str
    args: Dict[str, Any] = Field(default_factory=dict)
    summary: str = ""
    result: Optional[Dict[str, Any]] = None
    error: Optional[Dict[str, Any]] = None
    created_at: datetime
    decided_at: Optional[datetime] = None

    model_config = ConfigDict(from_attributes=True)


class AgentRunControlResponse(BaseModel):
    run_id: str
    session_id: str
    status: str
    message: str = ""
