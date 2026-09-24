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
    await state.record_task_run_started(task, run_id=f'{task}-new')
    assert (await state.get_task_run(running.run_id))['original'] is True
    assert await state.get_task_run(terminal[0].run_id) is not None
    assert await state.get_task_run(terminal[1].run_id) is None
    assert await state.get_task_run(terminal[-1].run_id) is not None


async def test_latest_platform_result_survives_other_platform_history(db_session):
    from sqlalchemy import select
    old = BackgroundTaskRun(run_id='rare-platform-result',task='favorites_sync',status='success',
                            started_at=utcnow()-timedelta(days=10),finished_at=utcnow()-timedelta(days=10),
                            result={'results':{'rare':{'status':'success','imported':1}}})
    frequent = [BackgroundTaskRun(run_id=f'frequent-platform-{i}',task='favorites_sync',status='success',
                                 started_at=utcnow()-timedelta(days=1)+timedelta(seconds=i),
                                 finished_at=utcnow()-timedelta(days=1)+timedelta(seconds=i),
                                 result={'platform':'frequent','result':{'status':'success','imported':i}})
                for i in range(201)]
    db_session.add_all([old,*frequent]);await db_session.commit()
    await state.record_task_run_success('favorites_sync',platform='frequent',result={'status':'success','imported':202})
    assert await state.get_task_run(old.run_id) is not None
    assert await state.get_task_run(frequent[0].run_id) is None
    latest = dict((platform,run_id) for run_id,platform in (await db_session.execute(select(state.latest_favorites_runs()))).all())
    assert latest['rare']==old.run_id
