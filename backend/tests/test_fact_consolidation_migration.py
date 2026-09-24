"""Removing fact copies must preserve references, history, and SQLite FTS triggers."""
import json
from datetime import datetime

from alembic import command
from alembic.autogenerate import compare_metadata
from alembic.migration import MigrationContext
import sqlalchemy as sa

from app.core.database import migration_config
from app.models import Base


def _previous_metadata():
    metadata = sa.MetaData()
    for table in Base.metadata.sorted_tables:
        table.to_metadata(metadata)

    def remove(table_name, column_name):
        table = metadata.tables[table_name]
        column = table.c[column_name]
        for constraint in list(table.constraints):
            if column in list(constraint.columns):
                table.constraints.remove(constraint)
        for index in list(table.indexes):
            if column in list(index.columns):
                table.indexes.remove(index)
        table._columns.remove(column)

    def add(table, name, type_, **kw):
        metadata.tables[table].append_column(sa.Column(name, type_, **kw))

    remove('contents', 'resolved_url')
    add('contents', 'clean_url', sa.Text())
    metadata.tables['contents'].append_column(sa.Column('discovery_source_id', sa.Integer(), sa.ForeignKey('discovery_sources.id'), index=True))
    remove('bot_runtime', 'bot_config_id')
    remove('agent_messages', 'tool_call_id')
    table = metadata.tables['agent_messages']
    for constraint in list(table.foreign_key_constraints):
        if 'run_id' in constraint.columns:
            table.constraints.remove(constraint)
    add('agent_sessions', 'context_budget', sa.Integer(), default=6000)
    add('agent_runs', 'input_message', sa.Text(), default='')
    add('agent_runs', 'output_message', sa.Text())
    for name, type_ in [('tool_name',sa.String(120)),('permission_level',sa.String(60)),('args',sa.JSON()),('result',sa.JSON()),('error',sa.JSON())]:
        add('agent_confirmations', name, type_, index=name=='tool_name')
    for name, type_ in [('rendered_payload',sa.JSON()),('nsfw_routing_result',sa.JSON()),('passed_rate_limit',sa.Boolean()),('rate_limit_reason',sa.String(200))]:
        add('content_queue_items',name,type_)
    table = metadata.tables['content_embeddings']
    table.indexes.remove(next(index for index in table.indexes if index.name=='ix_content_embeddings_last_indexed_at'))
    add('content_embeddings','indexed_at',sa.DateTime(),index=True)
    return metadata


def test_consolidation_preserves_related_rows_and_readable_history():
    engine = sa.create_engine('sqlite://')
    metadata = _previous_metadata()
    now = datetime(2026,9,20)
    with engine.connect() as db:
        db.exec_driver_sql('PRAGMA foreign_keys=ON')
        metadata.create_all(db)
        def insert(table, **values):
            db.execute(metadata.tables[table].insert().values(**values))
        insert('discovery_sources',id=1,kind='rss',name='source')
        insert('contents',id=1,platform='zhihu',url='https://example.com/raw',canonical_url='https://example.com/id',
               clean_url='https://example.com/resolved', discovery_source_id=1, body='current body',content_type='answer',
               like_count=17, extra_stats={'voteup_count':17,'thanks_count':2},
               archive_metadata={'archive':{'markdown':'current body','plain_text':'current body','html':'<p>source</p>'}})
        insert('media_assets',id=1,content_id=1,media_type='image',role='cover',original_url='https://example.com/cover')
        insert('media_variants',id=1,asset_id=1,variant_kind='optimized',storage_key='a.webp',status='ready')
        insert('content_embeddings',content_id=1,index_status='indexed',indexed_at=now)
        insert('agent_sessions',id='session')
        insert('agent_runs',id='run',session_id='session',input_message='question',output_message='answer',usage={'tokens':7})
        insert('agent_tool_calls',id='call',session_id='session',run_id='run',tool_name='read',args={'id':1},result=None)
        insert('agent_confirmations',id='confirm',session_id='session',run_id='run',tool_call_id='call',tool_name='read',permission_level='write',args={'id':1},result=None)
        insert('agent_messages',session_id='session',run_id='run',role='user',content='question')
        payload={'tool':'read','tool_call_id':'call','ok':True,'result':{'value':42}}
        insert('agent_messages',session_id='session',run_id='run',role='tool',content=json.dumps(payload),payload=payload)
        insert('agent_messages',session_id='session',run_id='run',role='assistant',content='answer',payload={'usage':{'tokens':7}})
        insert('bot_configs',id=1,platform='telegram',name='bot',bot_id='111')
        insert('bot_runtime',id=1,platform='telegram',bot_id='111')
        insert('bot_chats',id=1,bot_config_id=1,chat_id='normal',chat_type='channel')
        insert('distribution_rules',id=1,name='rule',match_conditions={})
        insert('content_queue_items',id=1,content_id=1,rule_id=1,bot_chat_id=1,target_platform='telegram',target_id='normal',nsfw_routing_result={'target_id':'separate'})
        result={'status':'success','failed_items':[],'imported':2}
        insert('system_settings',key='favorites_sync_last_result_zhihu',value=result,updated_at=now)
        insert('system_settings',key='favorites_sync_last_result',value={'zhihu':result},updated_at=now)
        insert('system_settings',key='background_task_state:cookie_check',value={'status':'error','last_error':'previous failure'},updated_at=now)
        db.exec_driver_sql('CREATE VIRTUAL TABLE contents_fts USING fts5(content_id UNINDEXED,title)')
        trigger="CREATE TRIGGER audit_fts AFTER INSERT ON contents BEGIN INSERT INTO contents_fts(content_id,title) VALUES (new.id,new.title); END"
        db.exec_driver_sql(trigger)
        db.commit()
        config=migration_config();config.attributes['connection']=db
        command.stamp(config,'20260920_media_archive_items')
        db.commit()
        command.upgrade(config,'head')
        db.commit()
        for table in ('contents','media_assets','media_variants','agent_runs','agent_tool_calls','agent_confirmations','bot_runtime','content_queue_items'):
            assert db.exec_driver_sql(f'SELECT count(*) FROM {table}').scalar()==1,table
        assert db.exec_driver_sql('SELECT count(*) FROM content_discovery_links').scalar()==1
        assert db.exec_driver_sql('SELECT count(*) FROM agent_messages').scalar()==3
        assert json.loads(db.exec_driver_sql('SELECT result FROM agent_tool_calls').scalar())=={'value':42}
        assert db.exec_driver_sql("SELECT content,payload,tool_call_id FROM agent_messages WHERE role='tool'").one()==('', '{}', 'call')
        assert db.exec_driver_sql('SELECT bot_config_id FROM bot_runtime').scalar()==1
        assert db.exec_driver_sql('SELECT target_id FROM content_queue_items').scalar()=='separate'
        assert db.exec_driver_sql('SELECT resolved_url FROM contents').scalar()=='https://example.com/resolved'
        assert json.loads(db.exec_driver_sql('SELECT archive_metadata FROM contents').scalar())['archive']=={'html':'<p>source</p>'}
        assert json.loads(db.exec_driver_sql('SELECT extra_stats FROM contents').scalar())=={'thanks_count':2}
        assert db.exec_driver_sql('SELECT count(*) FROM background_task_runs').scalar()==2
        assert db.exec_driver_sql("SELECT error FROM background_task_runs WHERE task='cookie_check'").scalar()=='previous failure'
        assert db.exec_driver_sql('SELECT count(*) FROM system_settings').scalar()==0
        assert db.exec_driver_sql('PRAGMA foreign_key_check').all()==[]
        assert db.exec_driver_sql('PRAGMA integrity_check').scalar()=='ok'
        assert db.exec_driver_sql("SELECT sql FROM sqlite_master WHERE name='audit_fts'").scalar()==trigger
        db.execute(Base.metadata.tables['contents'].insert().values(platform='universal',url='https://example.com/new',title='indexed'))
        assert db.exec_driver_sql("SELECT count(*) FROM contents_fts WHERE title MATCH 'indexed'").scalar()==1
        diffs=compare_metadata(MigrationContext.configure(db,opts={'include_object':lambda obj,name,kind,reflected,other: not (kind=='table' and reflected and (name.startswith('contents_fts') or name=='alembic_version'))}),Base.metadata)
        assert diffs==[]
    engine.dispose()
