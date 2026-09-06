from __future__ import annotations

from typing import Any, Dict, List, Optional

from pydantic import BaseModel, ConfigDict, Field


class ActionInfo(BaseModel):
    name: str
    description: str
    input_schema: Dict[str, Any] = Field(default_factory=dict)
    result_schema: Dict[str, Any] = Field(default_factory=dict)
    risk_level: str = "read"
    require_confirmation: bool = False
    permissions: List[str] = Field(default_factory=list)


class ActionInvokeRequest(BaseModel):
    input: Dict[str, Any] = Field(default_factory=dict)
    session_id: Optional[str] = None

    model_config = ConfigDict(extra="forbid")


class ActionInvokeResponse(BaseModel):
    action_name: str
    ok: bool
    status: str
    session_id: str
    run_id: str
    result: Optional[Dict[str, Any]] = None
    steps: List[Dict[str, Any]] = Field(default_factory=list)
    requires_confirmation: bool = False
    pending_confirmation: Optional[Dict[str, Any]] = None
