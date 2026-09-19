"""Parsing concurrency regressions at the real adapter/SQLite boundary."""
import asyncio

import pytest
from sqlalchemy import delete

from app.adapters.base import ParsedContent
from app.core.db_adapter import AsyncSessionLocal
from app.core.queue_adapter import TaskQueue
from app.models import Content, ContentStatus, Platform, Task, TaskStatus
from app.tasks.parsing import ContentParser


class _PausedAdapter:
    def __init__(self, entered, release, parsed=None, error=None):
        self.entered = entered
        self.release = release
        self.parsed = parsed
        self.error = error

    async def parse(self, _url):
        self.entered.set()
        await self.release.wait()
        if self.error:
            raise self.error
        return self.parsed

    def map_stats_to_content(self, _content, _parsed):
        pass

    async def close(self):
        pass


def _parsed(title, body, media=None):
    return ParsedContent(
        platform='universal', content_type='article', content_id=title,
        clean_url=f'https://example.test/{title}', title=title, body=body,
        layout_type='article', media_urls=media or [],
    )


async def _quiet_postprocessing(monkeypatch):
    async def noop(*_args, **_kwargs):
        return None

    monkeypatch.setattr(ContentParser, '_check_auto_approval', noop)
    monkeypatch.setattr('app.tasks.parsing.PostIngestService.run_for_content', noop)


async def test_network_parse_preserves_edits_made_while_adapter_is_paused(db_session, monkeypatch):
    await _quiet_postprocessing(monkeypatch)
    content = Content(
        url='https://example.test/race-edit', platform=Platform.UNIVERSAL,
        title='Before', body='Before body', status=ContentStatus.UNPROCESSED,
    )
    db_session.add(content)
    await db_session.commit()
    content_id = content.id
    entered, release = asyncio.Event(), asyncio.Event()
    adapter = _PausedAdapter(entered, release, _parsed('Parsed', 'Parsed body'))

    async def factory(_platform):
        return adapter

    monkeypatch.setattr('app.tasks.parsing.create_configured_adapter', factory)
    running = asyncio.create_task(ContentParser().execute_parse(content_id))
    await entered.wait()
    async with AsyncSessionLocal() as editor:
        current = await editor.get(Content, content_id)
        current.title = 'Manual during fetch'
        current.body = 'Manual body during fetch'
        current.manual_edit_fields = ['title', 'body']
        await editor.commit()
    release.set()
    result = await running

    assert result.skipped is False
    async with AsyncSessionLocal() as observer:
        saved = await observer.get(Content, content_id)
        assert (saved.title, saved.body) == ('Manual during fetch', 'Manual body during fetch')
        assert saved.parse_candidate['fields'] == {'title': 'Parsed', 'body': 'Parsed body'}


async def test_hard_delete_during_network_parse_returns_skipped(db_session, monkeypatch):
    content = Content(
        url='https://example.test/delete-race', platform=Platform.UNIVERSAL,
        status=ContentStatus.UNPROCESSED,
    )
    db_session.add(content)
    await db_session.commit()
    content_id = content.id
    entered, release = asyncio.Event(), asyncio.Event()

    async def factory(_platform):
        return _PausedAdapter(entered, release, _parsed('Late', 'Late body'))

    monkeypatch.setattr('app.tasks.parsing.create_configured_adapter', factory)
    running = asyncio.create_task(ContentParser().execute_parse(content_id))
    await entered.wait()
    async with AsyncSessionLocal() as remover:
        await remover.execute(delete(Content).where(Content.id == content_id))
        await remover.commit()
    release.set()
    result = await running
    assert (result.found, result.skipped, result.reason) == (False, True, 'content_not_found')


async def test_postprocessing_failure_does_not_downgrade_committed_parse(db_session, monkeypatch):
    await db_session.execute(delete(Task))
    content = Content(
        url='https://example.test/post-failure', platform=Platform.UNIVERSAL,
        status=ContentStatus.UNPROCESSED,
    )
    db_session.add(content)
    await db_session.flush()
    task = Task(
        task_type='parse_content', payload={'content_id': content.id},
        status=TaskStatus.PENDING,
    )
    db_session.add(task)
    await db_session.commit()
    content_id = content.id
    queue = TaskQueue()
    await queue.connect()
    claim = await queue.dequeue(timeout=1)

    async def factory(_platform):
        ready = asyncio.Event()
        ready.set()
        return _PausedAdapter(asyncio.Event(), ready, _parsed('Committed', 'Body'))

    async def post_failure(*_args, **_kwargs):
        raise RuntimeError('downstream failed')

    async def noop(*_args, **_kwargs):
        return None

    monkeypatch.setattr('app.tasks.parsing.create_configured_adapter', factory)
    monkeypatch.setattr(ContentParser, '_check_auto_approval', noop)
    monkeypatch.setattr('app.tasks.parsing.PostIngestService.run_for_content', post_failure)
    parser = ContentParser()
    with pytest.raises(RuntimeError, match='downstream failed'):
        await parser.execute_parse(content_id, claimed_task=claim)
    assert await parser._settle_parse_error(content_id, claim, RuntimeError('downstream failed'), 'failed') is False

    async with AsyncSessionLocal() as observer:
        saved = await observer.get(Content, content_id)
        saved_task = await observer.get(Task, claim.id)
        assert (saved.title, saved.status) == ('Committed', ContentStatus.PARSE_SUCCESS)
        assert saved_task.status == TaskStatus.COMPLETED
