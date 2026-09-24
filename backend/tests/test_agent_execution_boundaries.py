import asyncio
import pytest
from fastapi import FastAPI, Request
from sqlalchemy.ext.asyncio import async_sessionmaker
from app.models import AgentConfirmation, AgentRun, AgentToolCall
from app.services.agent.service import AgentService
from app.services.agent.tool_registry import AgentToolContext, AgentToolError, AgentToolRegistry
from app.services.agent.tools.api_bridge import _api_get_tool


async def test_bridge_validates_the_path_that_asgi_receives(db_session):
    app = FastAPI()
    reached = []

    @app.get('/api/v1/{path:path}')
    async def endpoint(path: str, request: Request):
        reached.append(request.url.path)
        return {'query': request.query_params.get('q')}

    context = AgentToolContext(db=db_session, app=app)
    for path in (
        '/api/v1/contents/../agent/sessions',
        '/contents/%2e%2e/agent/sessions',
        '/contents/%252e%252e/agent/sessions',
        '/contents/..%2fagent/sessions',
        '/contents/./1',
        '/contents//../agent/sessions',
        '/contents\\..\\agent/sessions',
        '/contents?ignored=/../agent/sessions',
        '/contents#fragment',
        '/contents/\n../agent/sessions',
        '//elsewhere/contents',
    ):
        with pytest.raises(AgentToolError) as error:
            await _api_get_tool({'path': path}, context)
        assert error.value.error_code == 'agent_api_path_not_allowed'
    assert reached == []

    result = await _api_get_tool(
        {'path': '/contents/7', 'query': {'q': '标题 /../ % 中文'}}, context
    )
    assert reached == ['/api/v1/contents/7']
    assert result['data']['query'] == '标题 /../ % 中文'


@pytest.mark.parametrize('second_decision', [True, False])
async def test_confirmation_commits_one_owner_before_external_action(
    db_session, second_decision
):
    registry = AgentToolRegistry()
    started = asyncio.Event()
    finish = asyncio.Event()
    executions = []
    sessions = async_sessionmaker(db_session.bind, expire_on_commit=False)

    async def external_action(args, context):
        executions.append(context.run_id)
        # A separate connection observes durable ownership before the effect.
        async with sessions() as observer:
            run = await observer.get(AgentRun, context.run_id)
            assert run.status == 'running'
        started.set()
        await asyncio.wait_for(finish.wait(), timeout=5)
        return {'sent': True}

    registry.register(name='send_once', description='local test action',
                      permission_level='external_side_effect', handler=external_action)
    service = AgentService(db_session)
    service.registry = registry
    pending = await service.invoke_tool(tool_name='send_once', args={})
    confirmation_id = pending.confirmation['id']

    async with sessions() as first_db, sessions() as second_db:
        # Both clients can cache pending; the database must decide ownership.
        first = await first_db.get(AgentConfirmation, confirmation_id)
        second = await second_db.get(AgentConfirmation, confirmation_id)
        assert first.status == second.status == 'pending'
        first_service = AgentService(first_db)
        second_service = AgentService(second_db)
        first_service.registry = second_service.registry = registry
        winner = asyncio.create_task(first_service.decide_confirmation(
            confirmation_id, approved=True
        ))
        try:
            await asyncio.wait_for(started.wait(), timeout=5)
            with pytest.raises(AgentToolError) as error:
                await second_service.decide_confirmation(
                    confirmation_id, approved=second_decision
                )
            assert error.value.error_code == 'agent_confirmation_not_found'
        finally:
            finish.set()
            result = await winner
        assert result.status == 'completed'

    assert len(executions) == 1
    async with sessions() as observer:
        confirmation = await observer.get(AgentConfirmation, confirmation_id)
        call = await observer.get(AgentToolCall, confirmation.tool_call_id)
        assert confirmation.status == 'approved'
        assert call.status == 'completed'


async def test_parallel_model_tools_serialize_shared_session_writes(db_session):
    from sqlalchemy import select
    from app.models import AgentMessage
    registry = AgentToolRegistry()
    active = 0
    peak = 0

    async def read_local(args, context):
        nonlocal active, peak
        active += 1
        peak = max(peak, active)
        await asyncio.sleep(0)
        assert await context.db.get(AgentRun, context.run_id)
        active -= 1
        return {'found': True}

    for name in ['first_read', 'second_read']:
        registry.register(name=name, description='local read', permission_level='read', handler=read_local)
    service = AgentService(db_session)
    service.registry = registry
    session = await service.ensure_session(None, title='parallel tool regression')
    run = AgentRun(id='parallel-tool-regression', session_id=session.id, status='running')
    db_session.add(run)
    await db_session.commit()
    tools = service._build_langchain_tools(session=session, run=run, emit_event=lambda event: None)
    results = await asyncio.gather(*(tool.ainvoke({}) for tool in tools))
    await db_session.commit()
    assert peak == 1
    assert all(result['found'] for result in results)
    calls = (await db_session.execute(select(AgentToolCall).where(AgentToolCall.run_id == run.id))).scalars().all()
    assert {call.tool_name for call in calls} == {'first_read', 'second_read'}
    assert all(call.status == 'completed' for call in calls)
    messages = (await db_session.execute(select(AgentMessage).where(AgentMessage.run_id == run.id))).scalars().all()
    assert len(messages) == 2


async def test_failed_tool_transaction_preserves_run_and_structured_error(db_session, monkeypatch):
    from unittest.mock import AsyncMock
    from sqlalchemy import select
    from app.models import AgentMessage
    service = AgentService(db_session)

    class BrokenGraph:
        async def ainvoke(self, *args, **kwargs):
            run = await db_session.scalar(select(AgentRun).join(AgentMessage, AgentMessage.run_id == AgentRun.id).where(AgentMessage.content == 'transaction regression'))
            db_session.add(AgentRun(id=run.id, session_id=run.session_id, status='running'))
            from sqlalchemy.exc import SAWarning
            with pytest.warns(SAWarning, match="conflicts with persistent instance"):
                await db_session.flush()

    monkeypatch.setattr('app.services.agent.service.LLMFactory.get_agent_chat_llm', AsyncMock(return_value=object()))
    monkeypatch.setattr('app.services.agent.service.create_react_agent', lambda *args, **kwargs: BrokenGraph())
    with pytest.raises(AgentToolError) as error:
        await service.run_message(message='transaction regression')
    assert error.value.error_code == 'agent_execution_failed'
    assert db_session.is_active
    run = await db_session.scalar(select(AgentRun).join(AgentMessage, AgentMessage.run_id == AgentRun.id).where(AgentMessage.content == 'transaction regression'))
    assert run.status == 'failed'
    assert run.completed_at is not None
    messages = (await db_session.execute(select(AgentMessage).where(AgentMessage.run_id == run.id))).scalars().all()
    assert [m.content for m in messages] == ['transaction regression']


@pytest.mark.parametrize("failed", [False, True])
async def test_model_tool_progress_is_durable_without_holding_writer_lock(db_session, failed):
    from sqlalchemy import select, text, update
    from app.models import AgentMessage, AgentSession
    sessions = async_sessionmaker(db_session.bind, expire_on_commit=False)
    observed = {}
    registry = AgentToolRegistry()

    async def remote_read(args, context):
        async with sessions() as observer:
            call = await observer.scalar(select(AgentToolCall).where(AgentToolCall.run_id == context.run_id))
            observed['started'] = call is not None and call.status == 'running'
            await observer.execute(text('PRAGMA busy_timeout=100'))
            try:
                await observer.execute(update(AgentSession).where(AgentSession.id == independent.id).values(title='independent write succeeded'))
                await observer.commit()
                observed['write'] = True
            except Exception:
                observed['write'] = False
        if failed:
            raise AgentToolError(error_code='remote_unavailable', message='remote unavailable')
        return {'found': True}

    registry.register(name='remote_read', description='remote boundary', permission_level='read', handler=remote_read)
    service = AgentService(db_session); service.registry = registry
    session = await service.ensure_session(None, title='durable model tool')
    independent = await service.ensure_session(None, title='unrelated session')
    run = AgentRun(id=f'durable-model-tool-regression-{failed}', session_id=session.id, status='running')
    db_session.add(run); await db_session.commit()
    tool = service._build_langchain_tools(session=session, run=run, emit_event=lambda event: None)[0]
    result = await tool.ainvoke({})
    assert result == {'found': True} if not failed else result['ok'] is False
    async with sessions() as observer:
        call = await observer.scalar(select(AgentToolCall).where(AgentToolCall.run_id == run.id))
        observed['finished'] = call is not None and call.status == ('failed' if failed else 'completed')
        observed['message'] = await observer.scalar(select(AgentMessage.id).where(AgentMessage.run_id == run.id)) is not None
    assert observed == {'started': True, 'write': True, 'finished': True, 'message': True}


async def test_tool_database_failure_rolls_back_and_finishes_ledger(db_session):
    from sqlalchemy import select
    from app.models import AgentMessage
    registry = AgentToolRegistry()

    async def broken_database_write(args, context):
        # Fail the actual transaction without touching user data or mocking SQL.
        context.db.add(AgentRun(id=context.run_id, session_id=context.session_id, status='running'))
        from sqlalchemy.exc import SAWarning
        with pytest.warns(SAWarning, match='conflicts with persistent instance'):
            await context.db.flush()

    registry.register(name='broken_read', description='database failure boundary', permission_level='read', handler=broken_database_write)
    service = AgentService(db_session); service.registry = registry
    with pytest.raises(AgentToolError) as exc:
        await service.invoke_tool(tool_name='broken_read', args={})
    assert exc.value.error_code == 'agent_tool_execution_failed'
    assert db_session.is_active
    call = await db_session.scalar(select(AgentToolCall).where(AgentToolCall.tool_name == 'broken_read'))
    run = await db_session.get(AgentRun, call.run_id)
    assert call.status == run.status == 'failed'
    assert call.completed_at is not None and run.completed_at is not None
    message = await db_session.scalar(select(AgentMessage).where(AgentMessage.run_id == run.id, AgentMessage.role == 'tool'))
    assert message.rendered_payload['ok'] is False
    assert message.rendered_payload['error']['details']['exception'] == 'IntegrityError'
