"""Fill missing, unprotected titles without fetching sources or triggering delivery."""
import argparse
import json
import sqlite3
import sys
from datetime import datetime, timezone
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'backend'))
from app.utils.content_title import derive_title, needs_title


def backfill(db_path: Path, apply: bool) -> dict:
    if not db_path.is_file():
        raise ValueError(f'Database does not exist: {db_path}')
    connection = sqlite3.connect(f'file:{db_path}?mode={"rw" if apply else "ro"}', uri=True, timeout=30)
    connection.row_factory = sqlite3.Row
    changed = 0
    protected = 0
    empty = 0
    platforms = {}
    backup = None
    try:
        if apply:
            # SQLite backup includes WAL; never copy the live main file alone.
            backup = db_path.with_name(f'{db_path.name}.before-titles-{datetime.now(timezone.utc):%Y%m%dT%H%M%S%fZ}')
            with sqlite3.connect(backup) as target:
                connection.backup(target)
            backup.chmod(0o600)
            connection.execute('BEGIN IMMEDIATE')
        for row in connection.execute('SELECT id, platform, title, body, manual_edit_fields FROM contents WHERE deleted_at IS NULL'):
            if not needs_title(row['title']):
                continue
            if 'title' in json.loads(row['manual_edit_fields'] or '[]'):
                protected += 1
                continue
            title = derive_title(row['body'])
            if not title:
                empty += 1
                continue
            changed += 1
            platforms[row['platform']] = platforms.get(row['platform'], 0) + 1
            if apply:
                connection.execute('UPDATE contents SET title=?, updated_at=? WHERE id=?',
                                   (title, datetime.now(timezone.utc).replace(tzinfo=None).isoformat(' '), row['id']))
        if apply:
            connection.commit()
        return {'mode': 'apply' if apply else 'dry_run', 'updated' if apply else 'candidates': changed,
                'platforms': platforms, 'protected': protected, 'no_text': empty, 'backup': str(backup) if backup else None}
    finally:
        connection.close()


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--db', type=Path, required=True)
    parser.add_argument('--apply', action='store_true')
    args = parser.parse_args()
    print(json.dumps(backfill(args.db.resolve(), args.apply), ensure_ascii=False))
