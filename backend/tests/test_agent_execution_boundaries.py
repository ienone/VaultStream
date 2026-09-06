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
