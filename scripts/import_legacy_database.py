"""Explicitly import the pre-Alembic deployment into a separate current database.

The source stays untouched. This is not an automatic startup migration.
"""
from __future__ import annotations

import argparse
from datetime import datetime
import importlib
import json
from pathlib import Path
import sqlite3
import sys
import tempfile

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'backend'))

from alembic import command
from sqlalchemy import Boolean, DateTime, JSON, create_engine, text
from app.core.database import _create_schema, migration_config
from app.models import Base

_ALLOWED_TABLES = {
    'discovery_sources', 'distribution_rules', 'bot_configs', 'bot_runtime', 'tasks',
    'system_settings', 'contents', 'bot_chats', 'content_sources', 'content_discovery_links',
    'distribution_targets', 'pushed_records', 'content_queue_items', 'realtime_events',
}
_DROPPED = {
    'contents': {'clean_url', 'discovery_source_id'},
    'tasks': {'max_retries', 'retry_count'},
    'distribution_rules': {'auto_approve_conditions'},
    'content_queue_items': {'approved_at', 'needs_approval', 'nsfw_routing_result',
                            'passed_rate_limit', 'rate_limit_reason', 'rendered_payload'},
}


def import_database(source: Path, target: Path) -> dict:
    if not source.is_file() or target.exists():
        raise ValueError('Source must exist and destination must not exist')
    src = sqlite3.connect(f'file:{source.resolve()}?mode=ro', uri=True)
    names = {r[0] for r in src.execute("SELECT name FROM sqlite_master WHERE type='table'")}
    if names - _ALLOWED_TABLES - {'sqlite_sequence'}:
        raise ValueError('This importer only accepts the inspected pre-Alembic schema')
    # These transitions require separate conversion when actual rows exist.
    for table in ('bot_runtime', 'content_queue_items', 'distribution_targets'):
        if src.execute(f'SELECT count(*) FROM {table}').fetchone()[0]:
            raise ValueError(f'Nonempty {table} needs explicit migration mapping')
    for (raw,) in src.execute('SELECT auto_approve_conditions FROM distribution_rules'):
        if raw and json.loads(raw):
            raise ValueError('Legacy automatic-approval conditions need explicit review')
    with tempfile.TemporaryDirectory(prefix='vaultstream-legacy-') as tmp:
        work = Path(tmp) / 'source.db'
        copied = sqlite3.connect(work)
        src.backup(copied)
        copied.close()
        src.close()
        old_engine = create_engine(f'sqlite:///{work}', hide_parameters=True)
        facts = importlib.import_module('migrations.versions.20260920_single_facts_consolidate_facts')
        media = importlib.import_module('migrations.versions.20260920_media_archive_items')
        with old_engine.begin() as conn:
            conn.exec_driver_sql('ALTER TABLE contents ADD COLUMN resolved_url TEXT')
            facts._content_data(conn)
            for row in conn.execute(text('SELECT id, archive_metadata FROM contents')).mappings():
                metadata = json.loads(row['archive_metadata']) if row['archive_metadata'] else None
                if not isinstance(metadata, dict):
                    continue
                for name in ('archive', 'processed_archive'):
                    if isinstance(metadata.get(name), dict):
                        media._merge_archive(metadata[name])
                conn.execute(text('UPDATE contents SET archive_metadata=:value WHERE id=:id'),
                             {'id': row['id'], 'value': json.dumps(metadata, ensure_ascii=False)})
        dest_engine = create_engine(f'sqlite:///{target.resolve()}', hide_parameters=True)
        counts = {}
        try:
            with dest_engine.begin() as dest, old_engine.connect() as old:
                _create_schema(dest)
                for table in Base.metadata.sorted_tables:
                    if table.name not in names:
                        continue
                    columns = {r[1] for r in old.exec_driver_sql(f'PRAGMA table_info("{table.name}")')}
                    unknown = columns - set(table.columns.keys()) - _DROPPED.get(table.name, set())
                    if unknown:
                        raise ValueError(f'Unmapped columns in {table.name}: {sorted(unknown)}')
                    count = 0
                    for row in old.execute(text(f'SELECT * FROM "{table.name}"')).mappings():
                        values = {}
                        for col in table.columns:
                            if col.name not in row:
                                continue
                            value = row[col.name]
                            if value is not None:
                                if isinstance(col.type, JSON) and isinstance(value, str): value = json.loads(value)
                                elif isinstance(col.type, DateTime): value = datetime.fromisoformat(value)
                                elif isinstance(col.type, Boolean): value = bool(value)
                            values[col.name] = value
                        dest.execute(table.insert().values(**values))
                        count += 1
                    counts[table.name] = count
                for row in old.execute(text('SELECT * FROM realtime_events')).mappings():
                    dest.execute(text('INSERT INTO realtime_events (id,event_type,payload,source_instance,created_at) '
                                      'VALUES (:id,:event_type,:payload,:source_instance,:created_at)'), dict(row))
                if dest.exec_driver_sql('PRAGMA foreign_key_check').fetchall():
                    raise ValueError('Imported database has invalid foreign keys')
                if dest.exec_driver_sql('PRAGMA integrity_check').scalar() != 'ok':
                    raise ValueError('Imported database failed integrity check')
                fts = dest.exec_driver_sql('SELECT count(*) FROM contents_fts').scalar()
                if fts != counts['contents']:
                    raise ValueError('Imported full-text index is incomplete')
                cfg = migration_config()
                cfg.attributes['connection'] = dest
                command.stamp(cfg, 'head')
        finally:
            dest_engine.dispose()
            old_engine.dispose()
    return {'rows': counts, 'fts_rows': fts, 'integrity': 'ok'}


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source', type=Path, required=True)
    parser.add_argument('--target', type=Path, required=True)
    args = parser.parse_args()
    print(json.dumps(import_database(args.source, args.target)))
