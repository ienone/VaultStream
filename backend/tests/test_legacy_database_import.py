"""An explicit legacy import preserves identities and never rewrites its source."""
import hashlib
import importlib.util
from pathlib import Path
import sqlite3

from sqlalchemy import create_engine, text

from app.models import Base

spec = importlib.util.spec_from_file_location(
    'legacy_import', Path(__file__).resolve().parents[2] / 'scripts/import_legacy_database.py')
legacy = importlib.util.module_from_spec(spec)
spec.loader.exec_module(legacy)


def test_legacy_import_preserves_data_and_source(tmp_path):
    source, target = tmp_path / 'legacy.db', tmp_path / 'current.db'
    engine = create_engine(f'sqlite:///{source}')
    with engine.begin() as db:
        for table in Base.metadata.sorted_tables:
            if table.name in legacy._ALLOWED_TABLES:
                table.create(db)
        db.execute(Base.metadata.tables['contents'].insert().values(
            id=42, platform='universal', url='https://example.org/article',
            title='Saved article', body='body', archive_metadata={'archive': {
                'images': [{'url': 'https://example.org/image'}],
                'stored_images': [{'orig_url': 'https://example.org/image', 'key': 'test.webp'}],
            }}))
        db.execute(Base.metadata.tables['content_sources'].insert().values(
            id=12, content_id=42, source='user_submit'))
        db.execute(Base.metadata.tables['system_settings'].insert().values(
            key='test_setting', value=80))
        db.exec_driver_sql('ALTER TABLE contents DROP COLUMN resolved_url')
        db.exec_driver_sql('ALTER TABLE contents ADD COLUMN clean_url TEXT')
        db.exec_driver_sql('ALTER TABLE contents ADD COLUMN discovery_source_id INTEGER')
        db.exec_driver_sql("UPDATE contents SET clean_url='https://example.org/resolved'")
        db.exec_driver_sql('ALTER TABLE distribution_rules ADD COLUMN auto_approve_conditions JSON')
        db.exec_driver_sql('CREATE TABLE realtime_events(id INTEGER PRIMARY KEY,event_type TEXT,payload TEXT,source_instance TEXT,created_at DATETIME)')
    engine.dispose()
    before = hashlib.sha256(source.read_bytes()).hexdigest()
    result = legacy.import_database(source, target)
    assert hashlib.sha256(source.read_bytes()).hexdigest() == before
    assert result['rows']['contents'] == result['fts_rows'] == 1
    with sqlite3.connect(target) as db:
        assert db.execute('SELECT id,title,resolved_url FROM contents').fetchone() == (
            42, 'Saved article', 'https://example.org/resolved')
        assert db.execute('SELECT id,content_id FROM content_sources').fetchone() == (12, 42)
        assert not db.execute('PRAGMA foreign_key_check').fetchall()
        raw = db.execute('SELECT archive_metadata FROM contents').fetchone()[0]
        assert 'stored_images' not in raw and 'test.webp' in raw
        assert db.execute('SELECT value FROM system_settings').fetchone()[0] == 80
