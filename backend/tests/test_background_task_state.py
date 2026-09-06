from datetime import timedelta
from uuid import uuid4
from app.models import BackgroundTaskRun, NotificationMessage
from app.core.time_utils import utcnow
from app.services import background_task_state as state


async def test_history_prunes_only_unreferenced_finished_runs(db_session):
    task = f'retention-{uuid4().hex}'
    now = utcnow()
    running = BackgroundTaskRun(run_id=f'{task}-running', task=task, status='running',
                                started_at=now - timedelta(days=10), run_metadata={'original': True})
    terminal = [BackgroundTaskRun(run_id=f'{task}-{index}', task=task, status='success',
                                 started_at=now - timedelta(days=5) + timedelta(seconds=index))
                for index in range(202)]
    db_session.add_all([running, *terminal])
    db_session.add(NotificationMessage(dedupe_key=task, category='task', severity='info',
                                      title='结果回执', source_type='background_task_run',
                                      source_id=terminal[0].run_id, route=f'/tasks/{terminal[0].run_id}'))
    await db_session.commit()
    await state._upsert_run(task, {'run_id': f'{task}-new', 'status': 'running'}, terminal=False)
    assert (await state.get_task_run(running.run_id))['original'] is True
    assert await state.get_task_run(terminal[0].run_id) is not None
    assert await state.get_task_run(terminal[1].run_id) is None
    assert await state.get_task_run(terminal[-1].run_id) is not None
