from __future__ import annotations

import json
import uuid
from dataclasses import dataclass, field
from datetime import datetime
from typing import Any, Callable, Dict, Iterable, Optional

from langchain_core.messages import AIMessage, BaseMessage, HumanMessage, SystemMessage
from langchain_core.tools import StructuredTool
from langgraph.prebuilt import create_react_agent
from sqlalchemy import desc, func, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.llm_factory import LLMFactory
from app.core.logging import logger
from app.core.time_utils import utcnow
from app.models import (
    AgentConfirmation,
    AgentContextSummary,
    AgentMessage,
    AgentRun,
    AgentSession,
    AgentToolCall,
)
from app.services.agent.tool_registry import (
    AgentToolContext,
    AgentToolError,
    AgentToolRegistry,
)
from app.services.agent.tools import register_builtin_tools
from app.services.settings_service import get_setting_value

_REGISTRY: AgentToolRegistry | None = None


def get_tool_registry() -> AgentToolRegistry:
    global _REGISTRY
    if _REGISTRY is None:
        registry = AgentToolRegistry()
        register_builtin_tools(registry)
        _REGISTRY = registry
    return _REGISTRY


def _new_id(prefix: str) -> str:
    return f"{prefix}_{uuid.uuid4().hex}"


def _jsonable(value: Any) -> Any:
    try:
        json.dumps(value, ensure_ascii=False)
        return value
    except Exception:
        return json.loads(json.dumps(value, ensure_ascii=False, default=str))


def _message_text(message: BaseMessage) -> str:
    content = getattr(message, "content", "")
    if isinstance(content, str):
        return content
    return json.dumps(content, ensure_ascii=False, default=str)


AgentEventSink = Callable[[Dict[str, Any]], None]


def _event_collector(
    events: list[Dict[str, Any]],
    event_sink: AgentEventSink | None = None,
) -> AgentEventSink:
    def _emit(event: Dict[str, Any]) -> None:
        events.append(event)
        if event_sink is not None:
            event_sink(event)

    return _emit


@dataclass
class AgentRunResult:
    session_id: str
    run_id: str
    status: str
    message: str = ""
    tool: Optional[str] = None
    result: Dict[str, Any] = field(default_factory=dict)
    events: list[Dict[str, Any]] = field(default_factory=list)
    confirmation: Optional[Dict[str, Any]] = None
    usage: Dict[str, Any] = field(default_factory=dict)

    @property
    def confirmation_required(self) -> bool:
        return self.status == "waiting_confirmation" and self.confirmation is not None


class AgentService:
    """LangGraph-backed Agent runtime with durable sessions and tool calls."""

    def __init__(self, db: AsyncSession, *, app: Any | None = None) -> None:
        self.db = db
        self.app = app
        self.registry = get_tool_registry()

    async def ensure_session(self, session_id: str | None, *, title: str | None = None) -> AgentSession:
        if session_id:
            session = await self.db.get(AgentSession, session_id)
            if session and session.deleted_at is None:
                return session
        else:
            session_id = _new_id("sess")

        session = AgentSession(
            id=session_id,
            title=title or "新会话",
            context_budget=await self._context_budget(),
            created_at=utcnow(),
            updated_at=utcnow(),
        )
        self.db.add(session)
        await self.db.flush()
        return session

    async def list_sessions(self, *, limit: int = 50) -> list[dict[str, Any]]:
        rows = (
            await self.db.execute(
                select(AgentSession)
                .where(AgentSession.deleted_at.is_(None))
                .order_by(desc(AgentSession.last_message_at), desc(AgentSession.updated_at))
                .limit(max(1, min(limit, 100)))
            )
        ).scalars().all()
        if not rows:
            return []

        pending_counts = dict(
            (
                await self.db.execute(
                    select(AgentConfirmation.session_id, func.count(AgentConfirmation.id))
                    .where(
                        AgentConfirmation.session_id.in_([s.id for s in rows]),
                        AgentConfirmation.status == "pending",
                    )
                    .group_by(AgentConfirmation.session_id)
                )
            ).all()
        )
        return [
            {
                "id": s.id,
                "title": s.title,
                "status": s.status,
                "created_at": s.created_at,
                "updated_at": s.updated_at,
                "last_message_at": s.last_message_at,
                "pending_confirmations": int(pending_counts.get(s.id, 0)),
            }
            for s in rows
        ]

    async def rename_session(self, session_id: str, title: str) -> AgentSession:
        session = await self._require_session(session_id)
        session.title = title.strip()
        session.updated_at = utcnow()
        await self.db.commit()
        await self.db.refresh(session)
        return session

    async def delete_session(self, session_id: str) -> None:
        session = await self._require_session(session_id)
        session.deleted_at = utcnow()
        session.status = "deleted"
        await self.db.commit()

    async def clear_session(self, session_id: str) -> None:
        session = await self._require_session(session_id)
        for model in (AgentMessage, AgentContextSummary):
            rows = (await self.db.execute(select(model).where(model.session_id == session_id))).scalars().all()
            for row in rows:
                await self.db.delete(row)
        session.last_message_at = None
        session.updated_at = utcnow()
        await self.db.commit()

    async def list_messages(
        self,
        session_id: str,
        *,
        limit: int = 50,
        before_id: int | None = None,
    ) -> tuple[list[AgentMessage], int | None]:
        await self._require_session(session_id)
        stmt = select(AgentMessage).where(AgentMessage.session_id == session_id)
        if before_id is not None:
            stmt = stmt.where(AgentMessage.id < before_id)
        rows = (
            await self.db.execute(
                stmt.order_by(desc(AgentMessage.id)).limit(max(1, min(limit, 100)) + 1)
            )
        ).scalars().all()
        next_before = rows[-1].id if len(rows) > limit else None
        rows = rows[:limit]
        rows.reverse()
        return rows, next_before

    async def run_message(
        self,
        *,
        message: str,
        session_id: str | None = None,
        event_sink: AgentEventSink | None = None,
    ) -> AgentRunResult:
        user_message = message.strip()
        if not user_message:
            raise AgentToolError(
                error_code="agent_invalid_message",
                message="message is required",
                retryable=True,
                suggested_fix="Send a non-empty natural language request.",
            )

        session = await self.ensure_session(session_id, title=self._derive_title(user_message))
        now = utcnow()
        run = AgentRun(
            id=_new_id("run"),
            session_id=session.id,
            status="running",
            input_message=user_message,
            created_at=now,
            updated_at=now,
        )
        self.db.add(run)
        self.db.add(
            AgentMessage(
                session_id=session.id,
                run_id=run.id,
                role="user",
                content=user_message,
                payload={},
                created_at=now,
            )
        )
        session.last_message_at = now
        if session.title == "新会话":
            session.title = self._derive_title(user_message)
        await self.db.flush()

        events: list[Dict[str, Any]] = []
        emit_event = _event_collector(events, event_sink)
        emit_event({"type": "start", "session_id": session.id, "run_id": run.id})
        try:
            llm = await LLMFactory.get_agent_chat_llm()
            if llm is None:
                raise AgentToolError(
                    error_code="agent_model_unavailable",
                    message="Agent chat LLM is not configured",
                    retryable=True,
                    suggested_fix="Configure agent_chat_api_key/model/base_url or text_llm_api_key/model/base_url.",
                )

            graph = create_react_agent(
                llm,
                self._build_langchain_tools(session=session, run=run, emit_event=emit_event),
                prompt=self._system_prompt(),
                version="v2",
            )
            messages = await self._build_context_messages(session.id, run.id, emit_event)
            result = await graph.ainvoke(
                {"messages": messages},
                config={"recursion_limit": 8, "configurable": {"thread_id": session.id}},
            )
            output_messages = result.get("messages") or []
            final_message = ""
            usage = self._collect_usage(output_messages)
            if output_messages:
                final_message = _message_text(output_messages[-1]).strip()
            if not final_message and run.status == "waiting_confirmation":
                final_message = "需要确认后才能继续执行该操作。"

            await self.db.refresh(run)
            if run.status == "stopped":
                final_message = "已停止当前 run。"
                run.output_message = final_message
                run.updated_at = utcnow()
                await self.db.commit()
                emit_event(
                    {
                        "type": "final",
                        "session_id": session.id,
                        "run_id": run.id,
                        "status": "stopped",
                        "message": final_message,
                    }
                )
                return AgentRunResult(
                    session_id=session.id,
                    run_id=run.id,
                    status="stopped",
                    message=final_message,
                    events=events,
                    usage=usage,
                )
            if run.status == "waiting_confirmation":
                pending = await self._latest_pending_confirmation(run.id)
                if final_message:
                    self.db.add(
                        AgentMessage(
                            session_id=session.id,
                            run_id=run.id,
                            role="assistant",
                            content=final_message,
                            payload={"status": "waiting_confirmation"},
                        )
                    )
                run.output_message = final_message
                run.usage = usage
                run.updated_at = utcnow()
                await self.db.commit()
                emit_event(
                    {
                        "type": "final",
                        "session_id": session.id,
                        "run_id": run.id,
                        "status": run.status,
                        "message": final_message,
                    }
                )
                return AgentRunResult(
                    session_id=session.id,
                    run_id=run.id,
                    status=run.status,
                    message=final_message,
                    events=events,
                    confirmation=self._confirmation_payload(pending) if pending else None,
                    usage=usage,
                )

            run.status = "completed"
            run.output_message = final_message
            run.usage = usage
            run.completed_at = utcnow()
            run.updated_at = run.completed_at
            self.db.add(
                AgentMessage(
                    session_id=session.id,
                    run_id=run.id,
                    role="assistant",
                    content=final_message,
                    payload={"usage": usage},
                )
            )
            await self.db.commit()
            if final_message:
                emit_event({"type": "assistant_delta", "content": final_message})
            emit_event({"type": "usage", "usage": usage})
            emit_event(
                {
                    "type": "final",
                    "session_id": session.id,
                    "run_id": run.id,
                    "status": "completed",
                    "message": final_message,
                }
            )
            return AgentRunResult(
                session_id=session.id,
                run_id=run.id,
                status="completed",
                message=final_message,
                result={"message": final_message},
                events=events,
                usage=usage,
            )
        except AgentToolError as exc:
            await self._fail_run(run, exc)
            emit_event({"type": "error", **exc.to_payload()})
            await self.db.commit()
            raise
        except Exception as exc:
            logger.exception("Agent run failed")
            error = AgentToolError(
                error_code="agent_execution_failed",
                message="Agent execution failed",
                retryable=True,
                details={"exception": exc.__class__.__name__},
                suggested_fix="Retry the request or reduce it to a smaller step.",
            )
            await self._fail_run(run, error)
            emit_event({"type": "error", **error.to_payload()})
            await self.db.commit()
            raise error from exc

    async def invoke_tool(
        self,
        *,
        tool_name: str,
        args: Dict[str, Any],
        confirmed: bool = False,
        session_id: str | None = None,
    ) -> AgentRunResult:
        spec = self.registry.get(tool_name)
        args = self.registry.validate_args(tool_name, args)
        session = await self.ensure_session(session_id, title=f"工具: {tool_name}")
        run = AgentRun(
            id=_new_id("run"),
            session_id=session.id,
            status="running",
            input_message=f"invoke:{tool_name}",
        )
        self.db.add(run)
        await self.db.flush()
        events: list[Dict[str, Any]] = []
        emit_event = _event_collector(events)
        emit_event({"type": "start", "session_id": session.id, "run_id": run.id})

        if spec.requires_confirmation and not confirmed:
            call = await self._record_tool_call(
                run=run,
                session=session,
                tool_name=tool_name,
                args=args,
                status="confirmation_required",
            )
            confirmation = await self._create_confirmation(run=run, session=session, call=call, args=args)
            await self.db.commit()
            payload = self._confirmation_payload(confirmation)
            emit_event({"type": "confirmation_required", "confirmation": payload})
            return AgentRunResult(
                session_id=session.id,
                run_id=run.id,
                status="waiting_confirmation",
                tool=tool_name,
                events=events,
                confirmation=payload,
            )

        call = await self._record_tool_call(run=run, session=session, tool_name=tool_name, args=args, status="running")
        emit_event(
            {
                "type": "tool_call",
                "tool_call_id": call.id,
                "tool": tool_name,
                "args": args,
                "permission_level": spec.permission_level.value,
            }
        )
        result = await self._execute_tool_call(
            spec.name,
            args,
            run=run,
            session=session,
            call=call,
            emit_event=emit_event,
        )
        if isinstance(result, dict) and result.get("ok") is False and isinstance(result.get("error"), dict):
            error_payload = result["error"]
            error = AgentToolError(
                error_code=str(error_payload.get("error_code") or "agent_tool_execution_failed"),
                message=str(error_payload.get("message") or "Tool execution failed"),
                retryable=bool(error_payload.get("retryable", False)),
                details=error_payload.get("details") if isinstance(error_payload.get("details"), dict) else {},
                suggested_fix=error_payload.get("suggested_fix"),
            )
            await self._fail_run(run, error)
            await self.db.commit()
            raise error
        run.status = "completed"
        run.output_message = json.dumps(result, ensure_ascii=False, default=str)
        run.completed_at = utcnow()
        await self.db.commit()
        emit_event({"type": "final", "session_id": session.id, "run_id": run.id, "status": "completed", "result": result})
        return AgentRunResult(
            session_id=session.id,
            run_id=run.id,
            status="completed",
            tool=tool_name,
            result=result,
            events=events,
        )

    async def decide_confirmation(self, confirmation_id: str, *, approved: bool) -> AgentRunResult:
        confirmation = await self.db.get(AgentConfirmation, confirmation_id)
        if confirmation is None or confirmation.status != "pending":
            raise AgentToolError(
                error_code="agent_confirmation_not_found",
                message="Pending confirmation not found",
                retryable=False,
            )
        run = await self.db.get(AgentRun, confirmation.run_id)
        session = await self.db.get(AgentSession, confirmation.session_id)
        call = await self.db.get(AgentToolCall, confirmation.tool_call_id)
        if run is None or session is None or call is None:
            raise AgentToolError(
                error_code="agent_confirmation_corrupt",
                message="Confirmation references a missing run, session or tool call",
                retryable=False,
            )

        events: list[Dict[str, Any]] = []
        emit_event = _event_collector(events)
        emit_event({"type": "start", "session_id": session.id, "run_id": run.id})
        confirmation.decided_at = utcnow()
        if not approved:
            confirmation.status = "rejected"
            call.status = "denied"
            run.status = "completed"
            run.output_message = "已拒绝执行该操作。"
            run.completed_at = utcnow()
            self.db.add(
                AgentMessage(
                    session_id=session.id,
                    run_id=run.id,
                    role="assistant",
                    content=run.output_message,
                    payload={"confirmation_id": confirmation.id, "approved": False},
                )
            )
            await self.db.commit()
            emit_event({"type": "final", "status": run.status, "message": run.output_message})
            return AgentRunResult(
                session_id=session.id,
                run_id=run.id,
                status=run.status,
                tool=confirmation.tool_name,
                message=run.output_message,
                events=events,
            )

        confirmation.status = "approved"
        call.status = "running"
        spec = self.registry.get(confirmation.tool_name)
        try:
            result = await self._execute_tool_call(
                spec.name,
                confirmation.args or {},
                run=run,
                session=session,
                call=call,
                emit_event=emit_event,
                confirmed=True,
            )
            confirmation.result = _jsonable(result)
            run.status = "completed"
            run.output_message = f"已执行 {confirmation.tool_name}。"
            run.completed_at = utcnow()
            self.db.add(
                AgentMessage(
                    session_id=session.id,
                    run_id=run.id,
                    role="tool",
                    content=json.dumps(result, ensure_ascii=False, default=str),
                    payload={"tool": confirmation.tool_name, "tool_call_id": call.id},
                )
            )
            self.db.add(
                AgentMessage(
                    session_id=session.id,
                    run_id=run.id,
                    role="assistant",
                    content=run.output_message,
                    payload={"confirmation_id": confirmation.id, "approved": True},
                )
            )
            await self.db.commit()
            emit_event(
                {
                    "type": "final",
                    "session_id": session.id,
                    "run_id": run.id,
                    "status": run.status,
                    "message": run.output_message,
                    "result": result,
                }
            )
            return AgentRunResult(
                session_id=session.id,
                run_id=run.id,
                status=run.status,
                tool=confirmation.tool_name,
                message=run.output_message,
                result=result,
                events=events,
            )
        except AgentToolError as exc:
            confirmation.status = "failed"
            confirmation.error = exc.to_payload()
            await self._fail_run(run, exc)
            await self.db.commit()
            emit_event({"type": "error", **exc.to_payload()})
            raise

    async def stop_run(self, run_id: str) -> AgentRun:
        run = await self.db.get(AgentRun, run_id)
        if run is None:
            raise AgentToolError(error_code="agent_run_not_found", message="Agent run not found")
        if run.status in {"running", "waiting_confirmation"}:
            run.status = "stopped"
            run.completed_at = utcnow()
            run.updated_at = run.completed_at
            await self.db.commit()
            await self.db.refresh(run)
        return run

    async def redo_last(self, session_id: str) -> AgentRunResult:
        await self._require_session(session_id)
        message = (
            await self.db.execute(
                select(AgentMessage)
                .where(AgentMessage.session_id == session_id, AgentMessage.role == "user")
                .order_by(desc(AgentMessage.id))
                .limit(1)
            )
        ).scalar_one_or_none()
        if message is None:
            raise AgentToolError(error_code="agent_no_message_to_redo", message="No user message to redo")
        return await self.run_message(message=message.content, session_id=session_id)

    def _build_langchain_tools(
        self,
        *,
        session: AgentSession,
        run: AgentRun,
        emit_event: AgentEventSink,
    ) -> list[StructuredTool]:
        tools: list[StructuredTool] = []
        for spec in self.registry.list_specs():
            async def _call(_spec_name: str = spec.name, **kwargs: Any) -> Dict[str, Any]:
                spec_inner = self.registry.get(_spec_name)
                call = await self._record_tool_call(
                    run=run,
                    session=session,
                    tool_name=spec_inner.name,
                    args=kwargs,
                    status="running",
                )
                emit_event(
                    {
                        "type": "tool_call",
                        "tool_call_id": call.id,
                        "tool": spec_inner.name,
                        "args": kwargs,
                        "permission_level": spec_inner.permission_level.value,
                    }
                )
                if spec_inner.requires_confirmation:
                    call.status = "confirmation_required"
                    confirmation = await self._create_confirmation(
                        run=run,
                        session=session,
                        call=call,
                        args=kwargs,
                    )
                    await self.db.flush()
                    payload = self._confirmation_payload(confirmation)
                    emit_event({"type": "confirmation_required", "confirmation": payload})
                    return {"ok": False, "confirmation_required": True, "confirmation": payload}

                return await self._execute_tool_call(
                    spec_inner.name,
                    kwargs,
                    run=run,
                    session=session,
                    call=call,
                    emit_event=emit_event,
                )

            tools.append(
                StructuredTool.from_function(
                    coroutine=_call,
                    name=spec.name,
                    description=(
                        f"{spec.description}\n"
                        f"permission_level={spec.permission_level.value}. "
                        "If the result contains confirmation_required=true, stop and ask the user to approve or reject."
                    ),
                    args_schema=spec.args_model,
                )
            )
        return tools

    async def _execute_tool_call(
        self,
        tool_name: str,
        args: Dict[str, Any],
        *,
        run: AgentRun,
        session: AgentSession,
        call: AgentToolCall,
        emit_event: AgentEventSink,
        confirmed: bool = False,
    ) -> Dict[str, Any]:
        context = AgentToolContext(
            db=self.db,
            app=self.app,
            run_id=run.id,
            session_id=session.id,
            confirmed=confirmed,
        )
        try:
            result = await self.registry.invoke(tool_name, args or {}, context)
        except AgentToolError as exc:
            call.status = "failed"
            call.error = exc.to_payload()
            call.completed_at = utcnow()
            await self.db.flush()
            payload = {"ok": False, "error": exc.to_payload()}
            emit_event({"type": "tool_result", "tool_call_id": call.id, "tool": tool_name, **payload})
            return payload
        except Exception as exc:
            error = AgentToolError(
                error_code="agent_tool_execution_failed",
                message="Tool execution failed",
                retryable=True,
                details={"exception": exc.__class__.__name__},
                suggested_fix="Retry with narrower arguments or inspect the backend logs.",
            )
            call.status = "failed"
            call.error = error.to_payload()
            call.completed_at = utcnow()
            await self.db.flush()
            payload = {"ok": False, "error": error.to_payload()}
            emit_event({"type": "tool_result", "tool_call_id": call.id, "tool": tool_name, **payload})
            return payload

        call.status = "completed"
        call.result = _jsonable(result)
        call.completed_at = utcnow()
        await self.db.flush()
        payload = {"ok": True, "result": result}
        emit_event({"type": "tool_result", "tool_call_id": call.id, "tool": tool_name, **payload})
        return result

    async def _record_tool_call(
        self,
        *,
        run: AgentRun,
        session: AgentSession,
        tool_name: str,
        args: Dict[str, Any],
        status: str,
    ) -> AgentToolCall:
        spec = self.registry.get(tool_name)
        call = AgentToolCall(
            id=_new_id("tool"),
            run_id=run.id,
            session_id=session.id,
            tool_name=tool_name,
            permission_level=spec.permission_level.value,
            status=status,
            args=_jsonable(args),
        )
        self.db.add(call)
        await self.db.flush()
        return call

    async def _create_confirmation(
        self,
        *,
        run: AgentRun,
        session: AgentSession,
        call: AgentToolCall,
        args: Dict[str, Any],
    ) -> AgentConfirmation:
        spec = self.registry.get(call.tool_name)
        run.status = "waiting_confirmation"
        run.updated_at = utcnow()
        confirmation = AgentConfirmation(
            id=_new_id("confirm"),
            session_id=session.id,
            run_id=run.id,
            tool_call_id=call.id,
            tool_name=call.tool_name,
            permission_level=spec.permission_level.value,
            status="pending",
            args=_jsonable(args),
            summary=self._confirmation_summary(call.tool_name, args),
        )
        self.db.add(confirmation)
        await self.db.flush()
        return confirmation

    async def _build_context_messages(
        self,
        session_id: str,
        run_id: str,
        emit_event: AgentEventSink,
    ) -> list[BaseMessage]:
        if isinstance(emit_event, list):
            emit_event = _event_collector(emit_event)

        rows = (
            await self.db.execute(
                select(AgentMessage)
                .where(AgentMessage.session_id == session_id)
                .order_by(AgentMessage.id.asc())
                .limit(80)
            )
        ).scalars().all()

        budget = await self._context_budget()
        token_estimate = self._estimate_tokens(m.content for m in rows)
        messages = rows
        latest_summary = (
            await self.db.execute(
                select(AgentContextSummary)
                .where(AgentContextSummary.session_id == session_id)
                .order_by(desc(AgentContextSummary.id))
                .limit(1)
            )
        ).scalar_one_or_none()

        if token_estimate > budget and len(rows) > 10:
            keep = rows[-8:]
            covered = rows[:-8]
            summary_text = self._compress_messages(covered)
            summary = AgentContextSummary(
                session_id=session_id,
                run_id=run_id,
                summary=summary_text,
                covered_message_count=len(covered),
                token_estimate=self._estimate_tokens(m.content for m in covered),
            )
            self.db.add(summary)
            await self.db.flush()
            latest_summary = summary
            messages = keep
            emit_event(
                {
                    "type": "context_summary",
                    "summary_id": summary.id,
                    "covered_message_count": summary.covered_message_count,
                    "token_estimate": summary.token_estimate,
                }
            )

        result: list[BaseMessage] = []
        if latest_summary is not None:
            result.append(SystemMessage(content=f"历史摘要:\n{latest_summary.summary}"))
        for row in messages:
            if row.role == "user":
                result.append(HumanMessage(content=row.content))
            elif row.role == "assistant":
                result.append(AIMessage(content=row.content))
        return result

    async def _fail_run(self, run: AgentRun, error: AgentToolError) -> None:
        run.status = "failed"
        run.error_code = error.error_code
        run.error_message = error.message
        run.completed_at = utcnow()
        run.updated_at = run.completed_at

    async def _context_budget(self) -> int:
        raw = await get_setting_value("agent_context_budget", 6000)
        try:
            return max(1000, min(int(raw), 50000))
        except Exception:
            return 6000

    async def _require_session(self, session_id: str) -> AgentSession:
        session = await self.db.get(AgentSession, session_id)
        if session is None or session.deleted_at is not None:
            raise AgentToolError(error_code="agent_session_not_found", message="Agent session not found")
        return session

    async def _latest_pending_confirmation(self, run_id: str) -> AgentConfirmation | None:
        return (
            await self.db.execute(
                select(AgentConfirmation)
                .where(AgentConfirmation.run_id == run_id, AgentConfirmation.status == "pending")
                .order_by(desc(AgentConfirmation.created_at))
                .limit(1)
            )
        ).scalar_one_or_none()

    def _confirmation_payload(self, confirmation: AgentConfirmation | None) -> Optional[Dict[str, Any]]:
        if confirmation is None:
            return None
        return {
            "id": confirmation.id,
            "session_id": confirmation.session_id,
            "run_id": confirmation.run_id,
            "tool_call_id": confirmation.tool_call_id,
            "tool_name": confirmation.tool_name,
            "permission_level": confirmation.permission_level,
            "status": confirmation.status,
            "args": confirmation.args or {},
            "summary": confirmation.summary,
            "created_at": confirmation.created_at.isoformat() if confirmation.created_at else None,
        }

    def _confirmation_summary(self, tool_name: str, args: Dict[str, Any]) -> str:
        preview = json.dumps(args, ensure_ascii=False, default=str)
        if len(preview) > 500:
            preview = preview[:500] + "..."
        return f"工具 {tool_name} 将执行会改变系统或外部状态的操作，参数: {preview}"

    def _system_prompt(self) -> str:
        tool_lines = [
            f"- {tool.name}: {tool.description} (permission={tool.permission_level.value})"
            for tool in self.registry.list_specs()
        ]
        return (
            "你是 VaultStream 的内容库与分发 Agent。必须通过工具读取或修改系统状态，"
            "不要编造内容库事实。\n"
            "回答内容库问题时优先调用 search_content，并引用检索结果的 content_id、title 和 url。"
            "写操作、外部同步、批量推送、创建规则、标签修改都必须尊重工具返回的确认要求。"
            "工具报错会包含 error_code、message、retryable、details、suggested_fix；"
            "如果 retryable=true，可以修正参数后最多再试一次。\n"
            "可用工具:\n"
            + "\n".join(tool_lines)
        )

    def _derive_title(self, message: str) -> str:
        title = " ".join(message.split())
        return title[:30] or "新会话"

    def _estimate_tokens(self, chunks: Iterable[str]) -> int:
        chars = sum(len(chunk or "") for chunk in chunks)
        return max(1, chars // 4)

    def _compress_messages(self, rows: list[AgentMessage]) -> str:
        parts = []
        for row in rows[-20:]:
            content = " ".join((row.content or "").split())
            if len(content) > 120:
                content = content[:120] + "..."
            parts.append(f"{row.role}: {content}")
        return "\n".join(parts)

    def _collect_usage(self, messages: list[Any]) -> Dict[str, Any]:
        totals: dict[str, int] = {}
        for message in messages:
            usage = getattr(message, "usage_metadata", None)
            if not isinstance(usage, dict):
                usage = (getattr(message, "response_metadata", None) or {}).get("token_usage")
            if isinstance(usage, dict):
                for key, value in usage.items():
                    if isinstance(value, int):
                        totals[key] = totals.get(key, 0) + value
        return totals


async def run_agent_message(message: str, context: AgentToolContext) -> AgentRunResult:
    service = AgentService(context.db, app=context.app)
    return await service.run_message(message=message, session_id=context.session_id)
