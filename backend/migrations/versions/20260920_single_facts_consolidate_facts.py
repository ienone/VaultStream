"""Consolidate mutable facts and preserve references before removing copies."""
import json

from alembic import op
import sqlalchemy as sa

revision = '20260920_single_facts'
down_revision = '20260920_media_archive_items'
branch_labels = None
depends_on = None


def _object(raw):
    return json.loads(raw) if raw else {}


def _agent_data(db):
    # Confirmation arguments are the approved snapshot; the tool call now owns them.
    for row in db.execute(sa.text('SELECT * FROM agent_confirmations')).mappings():
        db.execute(sa.text('''UPDATE agent_tool_calls SET tool_name=:tool_name,
            permission_level=:permission_level, args=:args,
            result=CASE WHEN result IS NULL OR result='null' THEN :result ELSE result END,
            error=CASE WHEN error IS NULL OR error='null' THEN :error ELSE error END
            WHERE id=:tool_call_id'''), dict(row))
    # Preserve otherwise unrepresented run text, without resurrecting cleared sessions.
    for row in db.execute(sa.text('SELECT * FROM agent_runs')).mappings():
        messages = db.execute(sa.text('SELECT role, content FROM agent_messages WHERE run_id=:id'), row).all()
        if not messages:
            continue
        for role, value in (('user', row['input_message']), ('assistant', row['output_message'])):
            if not value or (row['input_message'] or '').startswith('invoke:') or (role, value) in messages:
                continue
            db.execute(sa.text('''INSERT INTO agent_messages
                (session_id,run_id,role,content,payload,created_at)
                VALUES (:session_id,:id,:role,:content,'{}',:created_at)'''),
                {**row, 'role': role, 'content': value})
    db.execute(sa.text('''UPDATE agent_messages SET tool_call_id=json_extract(payload,'$.tool_call_id')
        WHERE role='tool' '''))
    for row in db.execute(sa.text('SELECT id, role, payload, tool_call_id FROM agent_messages')).mappings():
        payload = _object(row['payload']) or {}
        if row['role'] == 'tool':
            if not row['tool_call_id']:
                raise RuntimeError(f"Tool message {row['id']} has no durable call reference")
            db.execute(sa.text('''UPDATE agent_tool_calls SET
                result=CASE WHEN result IS NULL OR result='null' THEN :result ELSE result END,
                error=CASE WHEN error IS NULL OR error='null' THEN :error ELSE error END
                WHERE id=:call_id'''), {'call_id': row['tool_call_id'],
                'result': json.dumps(payload.get('result')), 'error': json.dumps(payload.get('error'))})
            db.execute(sa.text("UPDATE agent_messages SET content='',payload='{}' WHERE id=:id"), row)
        elif 'usage' in payload:
            payload.pop('usage')
            db.execute(sa.text('UPDATE agent_messages SET payload=:payload WHERE id=:id'),
                       {'id': row['id'], 'payload': json.dumps(payload, ensure_ascii=False)})


def _content_data(db):
    db.execute(sa.text('''INSERT OR IGNORE INTO content_discovery_links
        (content_id,discovery_source_id,url,created_at)
        SELECT id,discovery_source_id,url,COALESCE(discovered_at,created_at,CURRENT_TIMESTAMP)
        FROM contents WHERE discovery_source_id IS NOT NULL'''))
    db.execute(sa.text('''UPDATE contents SET resolved_url=clean_url
        WHERE clean_url IS NOT NULL AND clean_url IS NOT canonical_url'''))
    for row in db.execute(sa.text('''SELECT id, platform, content_type, body, archive_metadata,
        extra_stats, view_count, share_count, comment_count, collect_count FROM contents''')).mappings():
        metadata = _object(row['archive_metadata'])
        if isinstance(metadata, dict):
            for name in ('archive', 'processed_archive'):
                archive = metadata.get(name)
                if not isinstance(archive, dict):
                    continue
                seen = {row['body']} if row['body'] else set()
                for field in ('markdown', 'plain_text', 'html', 'raw_html'):
                    value = archive.get(field)
                    if isinstance(value, str):
                        if not value or value in seen:
                            archive.pop(field)
                        else:
                            seen.add(value)
        stats = _object(row['extra_stats']) or {}
        counts = {key: row[key] for key in ('view_count','share_count','comment_count','collect_count')}
        kind = row['content_type']
        if row['platform'] == 'zhihu':
            for alias in ('voteup_count','comment_count','visit_count','favorited_count'):
                stats.pop(alias, None)
            if kind == 'user_profile':
                counts.update(view_count=0, share_count=0)
            elif kind == 'question':
                stats.setdefault('answer_count', row['comment_count'])
                counts.update(comment_count=0, collect_count=0)
            elif kind == 'column':
                stats.setdefault('followers', row['view_count'])
                stats.setdefault('articles_count', row['comment_count'])
                counts.update(view_count=0, comment_count=0)
            elif kind == 'collection':
                stats.setdefault('follower_count', row['collect_count'])
                counts['collect_count'] = 0
        elif row['platform'] == 'weibo':
            if kind == 'user_profile':
                for key, old in (('followers','view_count'),('friends','share_count'),('statuses','comment_count')):
                    stats.setdefault(key, row[old])
                    counts[old] = 0
            else:
                for alias in ('repost','attitudes','comments'):
                    stats.pop(alias, None)
        db.execute(sa.text('''UPDATE contents SET archive_metadata=:metadata,extra_stats=:stats,
            view_count=:view_count,share_count=:share_count,comment_count=:comment_count,
            collect_count=:collect_count WHERE id=:id'''), {'id':row['id'], **counts,
            'metadata': json.dumps(metadata, ensure_ascii=False) if row['archive_metadata'] else None,
            'stats': json.dumps(stats, ensure_ascii=False)})


def _favorites_data(db):
    runs = db.execute(sa.text("SELECT result FROM background_task_runs WHERE task='favorites_sync'")).all()
    represented = []
    for raw, in runs:
        result = _object(raw) or {}
        represented.extend((result.get('results') or {}).values())
        if isinstance(result.get('result'), dict):
            represented.append(result['result'])
    rows = db.execute(sa.text("""SELECT key,value,updated_at FROM system_settings
        WHERE key LIKE 'favorites_sync_last_result%' ORDER BY key""")).all()
    for key, raw, at in rows:
        value = _object(raw)
        results = value if key == 'favorites_sync_last_result' else {key.removeprefix('favorites_sync_last_result_'): value}
        for platform, result in (results or {}).items():
            if not isinstance(result, dict) or result in represented:
                continue
            represented.append(result)
            db.execute(sa.text('''INSERT INTO background_task_runs
                (run_id,task,status,started_at,finished_at,error,metadata,result,created_at,updated_at)
                VALUES (:id,'favorites_sync',:status,:at,:at,:error,'{}',:result,:at,:at)'''),
                {'id': f'migrated-{key}-{platform}', 'at':at,
                 'status':'success' if result.get('status') in ('success','skipped') else 'error',
                 'error':result.get('error') or result.get('error_message'),
                 'result':json.dumps({'platform':platform,'result':result}, ensure_ascii=False)})
    # Some older workers only wrote a summary. Preserve their last terminal event
    # before retiring the settings path; existing run histories remain authoritative.
    summaries = db.execute(sa.text("SELECT key,value,updated_at FROM system_settings WHERE key LIKE 'background_task_state:%'"))
    for key, raw, updated_at in summaries:
        state = _object(raw) or {}
        task = key.removeprefix('background_task_state:')
        if state.get('status') not in ('ok','error') or db.execute(sa.text(
            'SELECT 1 FROM background_task_runs WHERE task=:task LIMIT 1'), {'task':task}).first():
            continue
        failed = state['status'] == 'error'
        at = state.get('last_error_at' if failed else 'last_success_at') or updated_at
        db.execute(sa.text("""INSERT INTO background_task_runs
            (run_id,task,status,started_at,finished_at,error,metadata,result,created_at,updated_at)
            VALUES (:id,:task,:status,:at,:at,:error,'{}','{}',:at,:at)"""),
            {'id':f'migrated-state-{task}','task':task,'status':'error' if failed else 'success',
             'at':at,'error':state.get('last_error') if failed else None})
    db.execute(sa.text("""DELETE FROM system_settings WHERE key LIKE 'background_task_state:%'
        OR key LIKE 'favorites_sync_last_result%' OR key='favorites_sync_last_sync_at'"""))


def upgrade() -> None:
    db = op.get_bind()
    # Native additions let data move before batch replacement removes the old fields.
    op.add_column('agent_messages', sa.Column('tool_call_id', sa.String(64), nullable=True))
    op.add_column('bot_runtime', sa.Column('bot_config_id', sa.Integer(), nullable=True))
    op.add_column('contents', sa.Column('resolved_url', sa.Text(), nullable=True))
    _agent_data(db)
    _content_data(db)
    _favorites_data(db)
    # Runtime observations can only be attached when exactly one config matches.
    db.execute(sa.text('''UPDATE bot_runtime SET bot_config_id=(
        SELECT min(c.id) FROM bot_configs c WHERE c.platform=bot_runtime.platform
        AND c.bot_id=bot_runtime.bot_id HAVING count(*)=1)'''))
    db.execute(sa.text('''DELETE FROM bot_runtime WHERE bot_config_id IS NULL OR id NOT IN
        (SELECT max(id) FROM bot_runtime GROUP BY bot_config_id)'''))
    db.execute(sa.text("""UPDATE content_embeddings SET last_indexed_at=COALESCE(last_indexed_at,indexed_at)
        WHERE index_status='indexed'"""))
    # Match the destination that the old worker would actually send to.
    db.execute(sa.text("""UPDATE content_queue_items SET target_id=json_extract(nsfw_routing_result,'$.target_id')
        WHERE json_extract(nsfw_routing_result,'$.target_id') IS NOT NULL
        AND json_extract(nsfw_routing_result,'$.target_id') != ''"""))

    with op.batch_alter_table('agent_confirmations') as batch:
        batch.drop_index('ix_agent_confirmations_tool_name')
        for name in ('tool_name','args','permission_level','error','result'):
            batch.drop_column(name)
    with op.batch_alter_table('agent_messages') as batch:
        batch.create_index('ix_agent_messages_tool_call_id', ['tool_call_id'])
        batch.create_foreign_key('fk_agent_messages_call', 'agent_tool_calls', ['tool_call_id'], ['id'], ondelete='CASCADE')
        batch.create_foreign_key('fk_agent_messages_run', 'agent_runs', ['run_id'], ['id'], ondelete='CASCADE')
    with op.batch_alter_table('agent_runs') as batch:
        batch.drop_column('input_message')
        batch.drop_column('output_message')
    with op.batch_alter_table('agent_sessions') as batch:
        batch.drop_column('context_budget')
    with op.batch_alter_table('bot_runtime') as batch:
        batch.alter_column('bot_config_id', existing_type=sa.Integer(), nullable=False)
        batch.create_index('ix_bot_runtime_bot_config_id', ['bot_config_id'], unique=True)
        batch.create_foreign_key('fk_bot_runtime_config', 'bot_configs', ['bot_config_id'], ['id'], ondelete='CASCADE')
    with op.batch_alter_table('content_embeddings') as batch:
        batch.drop_index('ix_content_embeddings_indexed_at')
        batch.create_index('ix_content_embeddings_last_indexed_at', ['last_indexed_at'])
        batch.drop_column('indexed_at')
    with op.batch_alter_table('content_queue_items') as batch:
        for name in ('rendered_payload','nsfw_routing_result','passed_rate_limit','rate_limit_reason'):
            batch.drop_column(name)
    # Batch replacement does not copy FTS triggers. Preserve their exact definitions.
    triggers = db.execute(sa.text("SELECT sql FROM sqlite_master WHERE type='trigger' AND tbl_name='contents'")).scalars().all()
    with op.batch_alter_table('contents', naming_convention={
        'fk': 'fk_%(table_name)s_%(column_0_name)s_%(referred_table_name)s',
    }) as batch:
        batch.drop_index('ix_contents_discovery_source_id')
        batch.drop_constraint('fk_contents_discovery_source_id_discovery_sources', type_='foreignkey')
        batch.drop_column('clean_url')
        batch.drop_column('discovery_source_id')
    for sql in triggers:
        db.exec_driver_sql(sql)


def downgrade() -> None:
    raise RuntimeError('Fact consolidation is forward-only; restore a database backup to roll back.')
