"""Removed source chunks must disappear from the persistent retrieval index."""
from unittest.mock import AsyncMock
from sqlalchemy import select
from app.models import Content, ContentEmbedding, ContentStatus, Platform
from app.services.embedding_service import EmbeddingService

async def test_reindex_removes_old_chunks_without_touching_other_content(db_session, monkeypatch):
    service = EmbeddingService()
    monkeypatch.setattr(service, '_embed_document_text', AsyncMock(return_value=[1.0, 0.0]))
    content = Content(url='https://example.com/shrinking-transcript', platform=Platform.UNIVERSAL,
        status=ContentStatus.PARSE_SUCCESS, title='视频', body='当前简介',
        rich_payload={'chunks': [{'content': '保留字幕'}, {'content': '已撤回的错误字幕'}]})
    other = Content(url='https://example.com/other-transcript', platform=Platform.UNIVERSAL,
        status=ContentStatus.PARSE_SUCCESS, title='其他内容', body='其他正文')
    db_session.add_all([content, other]); await db_session.commit()
    await service.index_content(content.id, session=db_session)
    await service.index_content(other.id, session=db_session)
    await db_session.commit()
    content.rich_payload = {'chunks': [{'content': '保留字幕'}]}
    await db_session.commit()
    await service.index_content(content.id, session=db_session)
    await db_session.commit()
    rows = (await db_session.execute(select(ContentEmbedding.chunk_index, ContentEmbedding.source_text)
        .where(ContentEmbedding.content_id == content.id))).all()
    assert {row.chunk_index for row in rows} == {-1, 0}
    assert all('已撤回' not in row.source_text for row in rows)
    assert await db_session.scalar(select(ContentEmbedding.id).where(ContentEmbedding.content_id == other.id)) is not None


async def test_remote_embedding_wait_does_not_hold_sqlite_writer_lock(tmp_path, monkeypatch):
    from sqlalchemy import update
    from sqlalchemy.ext.asyncio import create_async_engine, async_sessionmaker
    from app.models import Base
    from app.services import embedding_service as module

    engine = create_async_engine(f'sqlite+aiosqlite:///{tmp_path / "concurrent.db"}', connect_args={'timeout': 0.1})
    sessions = async_sessionmaker(engine, expire_on_commit=False)
    try:
        async with engine.begin() as connection:
            await connection.run_sync(Base.metadata.create_all)
        async with sessions() as session:
            content = Content(url='https://example.com/slow-index', platform=Platform.UNIVERSAL,
                status=ContentStatus.PARSE_SUCCESS, body='简介', rich_payload={'chunks': [{'content': '字幕'}]})
            unrelated = Content(url='https://example.com/independent-write', platform=Platform.UNIVERSAL, body='旧正文')
            session.add_all([content, unrelated]); await session.commit()
            content_id, unrelated_id = content.id, unrelated.id
        service = EmbeddingService()
        monkeypatch.setattr(module, 'AsyncSessionLocal', sessions)
        monkeypatch.setattr(service, '_get_document_embedding_signature', AsyncMock(return_value='test-signature'))
        monkeypatch.setattr(service, '_get_embedding_model', AsyncMock(return_value='test-model'))
        calls, write_errors = 0, []

        async def remote_boundary(text, media):
            nonlocal calls
            calls += 1
            if calls == 2:
                # A second connection writes while the indexing task awaits its provider.
                try:
                    async with sessions() as writer:
                        await writer.execute(update(Content).where(Content.id == unrelated_id).values(body='已更新'))
                        await writer.commit()
                except Exception as exc:
                    write_errors.append(type(exc).__name__)
            return [1.0, 0.0]

        monkeypatch.setattr(service, '_embed_document_text', remote_boundary)
        assert await service.index_content(content_id)
        assert calls == 2
        assert write_errors == []
        async with sessions() as session:
            assert (await session.get(Content, unrelated_id)).body == '已更新'
    finally:
        await engine.dispose()


async def test_long_body_tail_is_indexed_and_removed_after_source_shrinks(db_session, monkeypatch):
    service = EmbeddingService()
    monkeypatch.setattr(service, '_embed_document_text', AsyncMock(return_value=[1.0, 0.0]))
    body = ''.join(f'第{i}段原始资料。' for i in range(650)) + '末尾独有证据：归还设备后办理注销。'
    content = Content(url='https://example.com/long-body-tail', platform=Platform.UNIVERSAL,
        status=ContentStatus.PARSE_SUCCESS, body=body,
        rich_payload={'chunks': [{'content': '平台字幕', 'segment_type': 'transcript'}]})
    db_session.add(content); await db_session.commit()
    await service.index_content(content.id, session=db_session); await db_session.commit()
    rows = list((await db_session.scalars(select(ContentEmbedding).where(ContentEmbedding.content_id == content.id))).all())
    body_rows = sorted((r for r in rows if r.chunk_index < -1), key=lambda r: -r.chunk_index)
    assert body_rows and any('末尾独有证据' in r.source_text for r in body_rows)
    restored = body_rows[0].source_text + ''.join(r.source_text[200:] for r in body_rows[1:])
    assert restored == body
    assert any(r.chunk_index == 0 and r.source_text == '平台字幕' for r in rows)
    content.body = '短正文'; await db_session.commit()
    await service.index_content(content.id, session=db_session); await db_session.commit()
    assert await db_session.scalar(select(ContentEmbedding.id).where(ContentEmbedding.content_id == content.id, ContentEmbedding.chunk_index < -1)) is None


async def test_current_index_requires_every_current_source_unit(db_session, monkeypatch):
    from sqlalchemy import delete
    service = EmbeddingService()
    monkeypatch.setattr(service, '_embed_document_text', AsyncMock(return_value=[1.0, 0.0]))
    content = Content(url='https://example.com/complete-index-check', platform=Platform.UNIVERSAL,
        status=ContentStatus.PARSE_SUCCESS, body='原正文', rich_payload={'chunks': [{'content': '字幕证据'}]})
    db_session.add(content); await db_session.commit()
    await service.index_content(content.id, session=db_session); await db_session.commit()
    assert await service.has_current_content_index(content.id, session=db_session)
    await db_session.execute(delete(ContentEmbedding).where(ContentEmbedding.content_id == content.id, ContentEmbedding.chunk_index == 0))
    await db_session.commit()
    assert not await service.has_current_content_index(content.id, session=db_session)
    await service.index_content(content.id, session=db_session); await db_session.commit()
    content.body = '正文已经修改'; await db_session.commit()
    assert not await service.has_current_content_index(content.id, session=db_session)
    await service.index_content(content.id, session=db_session); await db_session.commit()
    row = await db_session.scalar(select(ContentEmbedding).where(ContentEmbedding.content_id == content.id, ContentEmbedding.chunk_index == 0))
    row.index_status = 'failed'; await db_session.commit()
    assert not await service.has_current_content_index(content.id, session=db_session)


async def test_source_edit_during_embedding_discards_stale_result(db_session, monkeypatch):
    from sqlalchemy import update
    from sqlalchemy.ext.asyncio import async_sessionmaker
    service = EmbeddingService()
    content = Content(url='https://example.com/concurrent-source-edit', platform=Platform.UNIVERSAL,
        status=ContentStatus.PARSE_SUCCESS, body='旧的来源原文')
    db_session.add(content); await db_session.commit(); cid = content.id
    sessions = async_sessionmaker(db_session.bind, expire_on_commit=False)
    async def remote_boundary(text, media):
        async with sessions() as editor:
            await editor.execute(update(Content).where(Content.id == cid).values(body='已经更正的原文'))
            await editor.commit()
        return [1.0, 0.0]
    monkeypatch.setattr(service, '_embed_document_text', remote_boundary)
    assert await service.index_content(cid) is False
    async with sessions() as observer:
        assert (await observer.get(Content, cid)).body == '已经更正的原文'
        assert await observer.scalar(select(ContentEmbedding.id).where(ContentEmbedding.content_id == cid)) is None


async def test_retry_rejects_source_revision_changed_during_model_call(db_session, monkeypatch, client):
    import pytest
    from sqlalchemy import update
    from sqlalchemy.ext.asyncio import async_sessionmaker
    from sqlalchemy.orm.exc import StaleDataError
    service = EmbeddingService()
    monkeypatch.setattr(service, '_embed_document_text', AsyncMock(return_value=[1.0, 0.0]))
    content = Content(url='https://example.com/retry-source-edit', platform=Platform.UNIVERSAL,
        status=ContentStatus.PARSE_SUCCESS, body='重试前原文')
    db_session.add(content); await db_session.commit(); cid = content.id
    await service.index_content(cid, session=db_session); await db_session.commit()
    row = await db_session.scalar(select(ContentEmbedding).where(ContentEmbedding.content_id == cid))
    row.index_status = 'failed'; await db_session.commit(); eid = row.id
    sessions = async_sessionmaker(db_session.bind, expire_on_commit=False)
    async def remote_boundary(text, media):
        async with sessions() as editor:
            await editor.execute(update(Content).where(Content.id == cid).values(body='重试期间更正的原文'))
            await editor.commit()
        return [0.0, 1.0]
    monkeypatch.setattr(service, '_embed_document_text', remote_boundary)
    with pytest.raises(StaleDataError):
        await service.retry_embedding(eid, session=db_session)
    await db_session.rollback()
    async with sessions() as observer:
        assert (await observer.get(Content, cid)).body == '重试期间更正的原文'
        assert (await observer.get(ContentEmbedding, eid)).index_status == 'failed'
    monkeypatch.setattr(EmbeddingService, '_embed_document_text', AsyncMock(side_effect=remote_boundary))
    response = await client.post(f'/api/v1/search/semantic/embeddings/{eid}/retry')
    assert response.status_code == 409
    assert response.json()['detail'] == '原文已变化，请刷新后重新索引'
