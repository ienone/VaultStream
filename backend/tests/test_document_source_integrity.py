"""Document extraction must not overwrite notes or commit replaced source data."""

import asyncio
from io import BytesIO
from types import SimpleNamespace
from threading import Event

from pypdf import PdfWriter
from pypdf.generic import DecodedStreamObject, DictionaryObject, NameObject
import pytest
from sqlalchemy import select
from sqlalchemy.orm.exc import StaleDataError

from app.adapters.storage import get_storage_backend
from app.core.db_adapter import AsyncSessionLocal
from app.models import Content, Platform, ContentStatus
from app.models.media import MediaAsset, MediaType, MediaRole, MediaVariant, MediaVariantKind, MediaVariantStatus
from app.models.search import ContentEmbedding
from app.services import document_text


async def _source(db, slug):
    writer = PdfWriter()
    page = writer.add_blank_page(width=300, height=300)
    font = DictionaryObject({NameObject('/Type'): NameObject('/Font'),
                             NameObject('/Subtype'): NameObject('/Type1'), NameObject('/BaseFont'): NameObject('/Helvetica')})
    page[NameObject('/Resources')] = DictionaryObject({NameObject('/Font'): DictionaryObject({NameObject('/F1'): writer._add_object(font)})})
    stream = DecodedStreamObject()
    stream.set_data(b'BT /F1 12 Tf 20 260 Td (Source-only evidence on page one.) Tj ET')
    page[NameObject('/Contents')] = writer._add_object(stream)
    writer.add_blank_page(width=300, height=300)
    output = BytesIO()
    writer.write(output)
    async def chunks():
        yield output.getvalue()
    storage = get_storage_backend()
    async with storage.stage_stream(chunks=chunks(), content_type='application/pdf', max_bytes=1_000_000) as (stored, path):
        await storage.publish_staged(stored, path)
    content = Content(url=f'capture://document/{slug}', platform=Platform.UNIVERSAL,
                      status=ContentStatus.PARSE_SUCCESS, body='用户保存说明', manual_edit_fields=['body'])
    db.add(content)
    await db.flush()
    asset = MediaAsset(content_id=content.id, media_type=MediaType.DOCUMENT, role=MediaRole.ATTACHMENT,
                       asset_metadata={'filename': 'evidence.pdf'}, variants=[])
    db.add(asset)
    await db.flush()
    variant = MediaVariant(asset_id=asset.id, variant_kind=MediaVariantKind.ORIGINAL_ARCHIVE,
                           status=MediaVariantStatus.READY, storage_key=stored.key, checksum=stored.sha256,
                           mime_type='application/pdf')
    db.add(variant)
    await db.commit()
    return content.id, asset.id, variant.id


async def test_document_extraction_preserves_note_and_invalidates_only_own_index(db_session):
    content_id, asset_id, _ = await _source(db_session, 'owned')
    other_id, _, _ = await _source(db_session, 'other')
    db_session.add_all([ContentEmbedding(content_id=content_id, source_text='stale'),
                        ContentEmbedding(content_id=other_id, source_text='keep')])
    await db_session.commit()
    result = await document_text.extract_content_documents(content_id)
    assert result['text_page_count'] == 1 and result['page_count'] == 2
    async with AsyncSessionLocal() as db:
        content = await db.get(Content, content_id)
        assert content.body == '用户保存说明' and content.manual_edit_fields == ['body']
        items = document_text.build_document_text_items(content, await document_text.document_assets(db, content_id))
        assert items[0].media_asset_id == asset_id and items[0].status == 'partial'
        assert items[0].pages[0].text == 'Source-only evidence on page one.'
        assert items[0].pages[1].text == ''
        assert not list(await db.scalars(select(ContentEmbedding).where(ContentEmbedding.content_id == content_id)))
        assert await db.scalar(select(ContentEmbedding.source_text).where(ContentEmbedding.content_id == other_id)) == 'keep'


@pytest.mark.parametrize('change', ['note', 'variant'])
async def test_document_extraction_discards_concurrent_changes(db_session, monkeypatch, change):
    content_id, _, variant_id = await _source(db_session, f'race-{change}')
    entered, release = asyncio.Event(), asyncio.Event()
    real_extract = document_text.extract_source
    async def delayed(source):
        result = await real_extract(source)
        entered.set()
        await release.wait()
        return result
    monkeypatch.setattr(document_text, 'extract_source', delayed)
    job = asyncio.create_task(document_text.extract_content_documents(content_id))
    await asyncio.wait_for(entered.wait(), 10)
    async with AsyncSessionLocal() as db:
        if change == 'note':
            content = await db.get(Content, content_id)
            content.body = '用户刚刚修改的说明'
        else:
            variant = await db.get(MediaVariant, variant_id)
            variant.storage_key = 'replacement.pdf'
        await db.commit()
    release.set()
    with pytest.raises(StaleDataError):
        await job
    async with AsyncSessionLocal() as db:
        content = await db.get(Content, content_id)
        assert not content.rich_payload
        if change == 'note':
            assert content.body == '用户刚刚修改的说明'


async def test_document_reader_rejects_foreign_asset_and_old_variant(db_session):
    content_id, _, variant_id = await _source(db_session, 'read-boundary')
    other_id, _, _ = await _source(db_session, 'read-foreign')
    await document_text.extract_content_documents(content_id)
    async with AsyncSessionLocal() as db:
        content = await db.get(Content, content_id)
        foreign = await document_text.document_assets(db, other_id)
        assert document_text.build_document_text_items(content, foreign) == []
        variant = await db.get(MediaVariant, variant_id)
        variant.checksum = 'replacement-checksum'
        own = await document_text.document_assets(db, content_id)
        item = document_text.build_document_text_items(content, own)[0]
        assert item.status == 'pending' and item.pages == []


async def test_new_summary_does_not_delete_native_document_pages(db_session, monkeypatch):
    from google import genai
    from app.services import content_summary_service
    content_id, _, _ = await _source(db_session, 'summary-preservation')
    await document_text.extract_content_documents(content_id)
    other_id, _, _ = await _source(db_session, 'summary-other')
    db_session.add_all([ContentEmbedding(content_id=content_id, source_text='old summary'),
                        ContentEmbedding(content_id=other_id, source_text='unrelated')])
    await db_session.commit()
    async def config():
        return 'test-placeholder', 'test-model', 'v1beta'
    monkeypatch.setattr(content_summary_service, '_get_summary_llm_config', config)
    prompts = []
    def generate(**kwargs):
        prompts.append(kwargs['contents'])
        return SimpleNamespace(parsed={
            'summary': 'Generated overview', 'tags': [],
            'rag_chunks': [{'title': 'Generated', 'content': 'Derived interpretation'}],
        })
    monkeypatch.setattr(genai, 'Client', lambda **kwargs: SimpleNamespace(models=SimpleNamespace(
        generate_content=generate)))
    async with AsyncSessionLocal() as db:
        content = await content_summary_service.generate_summary_for_content(db, content_id, force=True)
        pages = document_text.build_document_text_items(content, await document_text.document_assets(db, content_id))[0].pages
        assert len(pages) == 2 and pages[0].text == 'Source-only evidence on page one.'
        assert content.body == '用户保存说明'
        assert content.rich_payload['chunks'][-1]['generated'] is True
        assert 'Source-only evidence on page one.' in prompts[0]
        assert '第 2 页：\n[未读取到原生文本]' in prompts[0]
        assert content.summary.startswith('【仅概括已提取的 PDF 文本')
        assert not list(await db.scalars(select(ContentEmbedding).where(ContentEmbedding.content_id == content_id)))
        assert await db.scalar(select(ContentEmbedding.source_text).where(ContentEmbedding.content_id == other_id)) == 'unrelated'
        db.add(ContentEmbedding(content_id=content_id, source_text='current index'))
        await db.commit()
        await content_summary_service.generate_summary_for_content(db, content_id)
        assert len(prompts) == 1
        assert await db.scalar(select(ContentEmbedding.source_text).where(ContentEmbedding.content_id == content_id)) == 'current index'
        content.body = 'Updated user note'
        await db.commit()
        await content_summary_service.generate_summary_for_content(db, content_id)
        assert len(prompts) == 2 and 'Updated user note' in prompts[-1]
        await content_summary_service.generate_summary_for_content(db, content_id, force=True)
        assert len(prompts) == 3


async def test_summary_cannot_commit_after_source_changes(db_session, monkeypatch):
    from google import genai
    from app.services import content_summary_service
    content_id, _, _ = await _source(db_session, 'summary-race')
    await document_text.extract_content_documents(content_id)
    entered, release = asyncio.Event(), Event()
    loop = asyncio.get_running_loop()
    async def config():
        return 'test-placeholder', 'test-model', 'v1beta'
    def generate(**kwargs):
        loop.call_soon_threadsafe(entered.set)
        if not release.wait(10):
            raise TimeoutError('test did not release model boundary')
        return SimpleNamespace(parsed={'summary': 'Stale result', 'tags': [], 'rag_chunks': []})
    monkeypatch.setattr(content_summary_service, '_get_summary_llm_config', config)
    monkeypatch.setattr(genai, 'Client', lambda **kwargs: SimpleNamespace(models=SimpleNamespace(generate_content=generate)))
    async with AsyncSessionLocal() as db:
        job = asyncio.create_task(content_summary_service.generate_summary_for_content(db, content_id, force=True))
        try:
            await asyncio.wait_for(entered.wait(), 10)
            async with AsyncSessionLocal() as writer:
                current = await writer.get(Content, content_id)
                current.body = 'New source, written while the model is running'
                await writer.commit()
        finally:
            release.set()
        with pytest.raises(StaleDataError):
            await job
    async with AsyncSessionLocal() as db:
        current = await db.get(Content, content_id)
        assert current.summary is None
        assert current.body == 'New source, written while the model is running'


async def test_pending_pdf_does_not_send_note_only_or_reuse_old_summary(db_session, monkeypatch):
    from app.services import content_summary_service
    content_id, _, _ = await _source(db_session, 'summary-pending')
    async with AsyncSessionLocal() as db:
        content = await db.get(Content, content_id)
        content.summary = 'Old note-only summary'
        content.rich_payload = {'chunks': [{'generated': True, 'content': 'Old note'}]}
        await db.commit()
    async def unexpected_config():
        pytest.fail('Pending document must not reach the model boundary')
    monkeypatch.setattr(content_summary_service, '_get_summary_llm_config', unexpected_config)
    async with AsyncSessionLocal() as db:
        with pytest.raises(content_summary_service.SummaryGenerationError) as caught:
            await content_summary_service.generate_summary_for_content(db, content_id)
        assert caught.value.status_code == 409
        assert (await db.get(Content, content_id)).summary == 'Old note-only summary'
