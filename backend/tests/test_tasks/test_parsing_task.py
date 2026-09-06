"""Reparsing must persist candidates without overwriting the user's edits."""
from app.adapters.base import ParsedContent
from app.core.db_adapter import AsyncSessionLocal
from app.models import Content, ContentStatus, Platform
from app.tasks.parsing import ContentParser


async def test_update_content_preserves_manual_fields_and_records_candidate(db_session):
    content = Content(
        url='https://example.test/manual-edit', platform=Platform.UNIVERSAL,
        title='Manual title', body='Manual body',
        manual_edit_fields=['title', 'body'], status=ContentStatus.UNPROCESSED,
    )
    db_session.add(content)
    await db_session.commit()
    parsed = ParsedContent(
        platform='universal', content_type='article', content_id='manual-edit',
        clean_url=content.url, title='Parsed title', body='Parsed body', layout_type='article',
    )
    # No media or stats need an external adapter. The ORM write, media fact
    # update and post-ingest policy checks execute normally.
    await ContentParser()._update_content(db_session, content, parsed, None)
    async with AsyncSessionLocal() as observer:
        saved = await observer.get(Content, content.id)
        assert (saved.title, saved.body) == ('Manual title', 'Manual body')
        assert saved.parse_candidate['fields'] == {
            'title': 'Parsed title', 'body': 'Parsed body',
        }
        assert saved.status == ContentStatus.PARSE_SUCCESS
