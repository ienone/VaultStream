"""
Agent / Tool Calling 相关 schema
"""
from typing import Any, Dict, List, Optional

from pydantic import BaseModel, Field


class AgentToolInfo(BaseModel):
    name: str
    description: str
    args_schema: Dict[str, Any] = Field(default_factory=dict)


class AgentToolInvokeRequest(BaseModel):
    args: Dict[str, Any] = Field(default_factory=dict)


class AgentToolInvokeResponse(BaseModel):
    tool: str
    ok: bool
    result: Optional[Dict[str, Any]] = None
    error: Optional[str] = None


class AgentRunRequest(BaseModel):
    message: str
    session_id: Optional[str] = None


class AgentRunResponse(BaseModel):
    tool: str
    result: Dict[str, Any] = Field(default_factory=dict)
