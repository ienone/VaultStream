from __future__ import annotations

from datetime import timedelta

import pytest
from sqlalchemy import select

from app.core.time_utils import utcnow
from app.models import Content, ContentEmbedding, ContentStatus, Platform, ReviewStatus
from app.services.embedding_service import EmbeddingService


@pytest.mark.asyncio
async def test_text_only_document_embedding_uses_retrieval_document(monkeypatch):
    svc = EmbeddingService()
    captured: dict[str, str] = {}
    content = Content(
        platform=Platform.BILIBILI,
        url="https://www.bilibili.com/video/BV-embed-doc",
        canonical_url="embed://doc/1",
        status=ContentStatus.PARSE_SUCCESS,
        review_status=ReviewStatus.APPROVED,
        title="Rust 异步实践",
        body="Tokio runtime benchmark",
    )

    async def _fake_embed_text(text: str) -> list[float]:
        captured["text"] = text
        return [0.1, 0.2]

    monkeypatch.setattr(svc, "_embed_text", _fake_embed_text)

    vector = await svc._embed_document_text(svc._build_content_text(content), [])

    assert vector == [0.1, 0.2]
    assert captured["text"].startswith("VaultStream retrieval document:\n")
    assert "Rust 异步实践" in captured["text"]


@pytest.mark.asyncio
async def test_embed_query_uses_retrieval_query(monkeypatch):
    svc = EmbeddingService()
    captured: dict[str, str] = {}

    async def _fake_embed_text(text: str) -> list[float]:
        captured["text"] = text
        return [0.3, 0.4]

    monkeypatch.setattr(svc, "_embed_text", _fake_embed_text)

    vector = await svc.embed_query("rust async")

    assert vector == [0.3, 0.4]
    assert captured["text"] == "VaultStream retrieval query:\nrust async"


@pytest.mark.asyncio
async def test_index_content_creates_embedding_record(db_session, monkeypatch):
    now = utcnow()
    content = Content(
        platform=Platform.BILIBILI,
        url="https://www.bilibili.com/video/BV-embed-index",
        canonical_url="embed://index/1",
        status=ContentStatus.PARSE_SUCCESS,
        review_status=ReviewStatus.APPROVED,
        title="Rust 异步实践",
        body="Tokio runtime benchmark",
        created_at=now,
    )
    db_session.add(content)
    await db_session.commit()

    svc = EmbeddingService()

    async def _fake_embed_text(text: str) -> list[float]:
        assert text.startswith("VaultStream retrieval document:\n")
        assert "Rust 异步实践" in text
        return [0.5, 0.5]

    monkeypatch.setattr(svc, "_embed_text", _fake_embed_text)

    changed = await svc.index_content(content.id, session=db_session)
    assert changed is True

    record = (
        await db_session.execute(
            select(ContentEmbedding).where(ContentEmbedding.content_id == content.id)
        )
    ).scalar_one_or_none()
    assert record is not None
    assert isinstance(record.embedding, list)
    assert len(record.embedding) == 2
    assert record.embedding_model == "gemini-embedding-2"
    assert record.embedding_model_signature == await svc._get_document_embedding_signature()
    assert record.index_status == "indexed"
    assert record.chunk_index == -1
    assert record.source_text and "Tokio runtime benchmark" in record.source_text
    assert record.last_attempted_at is not None
    assert record.last_indexed_at is not None


@pytest.mark.asyncio
async def test_search_hybrid_returns_ranked_hits(db_session, monkeypatch):
    now = utcnow()
    item1 = Content(
        platform=Platform.BILIBILI,
        url="https://www.bilibili.com/video/BV-embed-search-1",
        canonical_url="embed://search/1",
        status=ContentStatus.PARSE_SUCCESS,
        review_status=ReviewStatus.APPROVED,
        title="Rust 异步运行时",
        body="Tokio async-std 对比",
        created_at=now,
    )
    item2 = Content(
        platform=Platform.ZHIHU,
        url="https://www.zhihu.com/question/123/answer/456",
        canonical_url="embed://search/2",
        status=ContentStatus.PARSE_SUCCESS,
        review_status=ReviewStatus.APPROVED,
        title="Python 协程",
        body="asyncio 入门",
        created_at=now,
    )
    db_session.add_all([item1, item2])
    await db_session.flush()
    svc = EmbeddingService()
    model_signature = await svc._get_document_embedding_signature()

    db_session.add_all(
        [
            ContentEmbedding(
                content_id=item1.id,
                embedding_model="gemini-embedding-2",
                embedding_model_signature=model_signature,
                index_status="indexed",
                embedding=[1.0, 0.0],
            ),
            ContentEmbedding(
                content_id=item2.id,
                embedding_model="gemini-embedding-2",
                embedding_model_signature=model_signature,
                index_status="indexed",
                embedding=[0.0, 1.0],
            ),
        ]
    )
    await db_session.commit()

    async def _fake_embed_query(_: str) -> list[float]:
        return [1.0, 0.0]

    monkeypatch.setattr(svc, "embed_query", _fake_embed_query)

    hits = await svc.search(query="Rust", top_k=5, session=db_session)
    assert len(hits) >= 1
    assert hits[0].content.id == item1.id
    assert hits[0].match_source in ("vector", "fts", "hybrid")


@pytest.mark.asyncio
async def test_search_respects_platform_and_date_filters(db_session, monkeypatch):
    now = utcnow()
    old_item = Content(
        platform=Platform.BILIBILI,
        url="https://www.bilibili.com/video/BV-embed-old",
        canonical_url="embed://filter/old",
        status=ContentStatus.PARSE_SUCCESS,
        review_status=ReviewStatus.APPROVED,
        title="Rust 旧内容",
        body="old",
        created_at=now - timedelta(days=30),
    )
    new_item = Content(
        platform=Platform.ZHIHU,
        url="https://www.zhihu.com/question/7/answer/8",
        canonical_url="embed://filter/new",
        status=ContentStatus.PARSE_SUCCESS,
        review_status=ReviewStatus.APPROVED,
        title="Rust 新内容",
        body="new",
        created_at=now,
    )
    db_session.add_all([old_item, new_item])
    await db_session.flush()
    svc = EmbeddingService()
    model_signature = await svc._get_document_embedding_signature()
    db_session.add_all(
        [
            ContentEmbedding(
                content_id=old_item.id,
                embedding_model="gemini-embedding-2",
                embedding_model_signature=model_signature,
                index_status="indexed",
                embedding=[1.0, 0.0],
            ),
            ContentEmbedding(
                content_id=new_item.id,
                embedding_model="gemini-embedding-2",
                embedding_model_signature=model_signature,
                index_status="indexed",
                embedding=[1.0, 0.0],
            ),
        ]
    )
    await db_session.commit()

    async def _fake_embed_query(_: str) -> list[float]:
        return [1.0, 0.0]

    monkeypatch.setattr(svc, "embed_query", _fake_embed_query)

    hits = await svc.search(
        query="Rust",
        top_k=10,
        platforms=["zhihu"],
        date_from=now - timedelta(days=1),
        session=db_session,
    )

    ids = {hit.content.id for hit in hits}
    assert new_item.id in ids
    assert old_item.id not in ids


@pytest.mark.asyncio
async def test_search_ignores_embeddings_with_non_matching_signature(db_session, monkeypatch):
    now = utcnow()
    item = Content(
        platform=Platform.BILIBILI,
        url="https://www.bilibili.com/video/BV-embed-signature",
        canonical_url="embed://signature/1",
        status=ContentStatus.PARSE_SUCCESS,
        review_status=ReviewStatus.APPROVED,
        title="Rust 向量检索",
        body="vector search",
        created_at=now,
    )
    db_session.add(item)
    await db_session.flush()
    db_session.add(
        ContentEmbedding(
            content_id=item.id,
            embedding_model="gemini-embedding-2",
            embedding_model_signature="gemini-embedding-2|dim=768|prefix=vaultstream_rag_v1|role=document",
            index_status="indexed",
            embedding=[1.0, 0.0],
        )
    )
    await db_session.commit()

    svc = EmbeddingService()

    async def _fake_embed_query(_: str) -> list[float]:
        return [1.0, 0.0]

    monkeypatch.setattr(svc, "embed_query", _fake_embed_query)

    hits = await svc.search(query="Rust 向量", top_k=5, session=db_session)

    assert all(hit.content.id != item.id or hit.match_source != "vector" for hit in hits)


@pytest.mark.asyncio
async def test_vector_rank_limits_database_scan(db_session, monkeypatch):
    now = utcnow()
    items = []
    for idx in range(4):
        item = Content(
            platform=Platform.BILIBILI,
            url=f"https://www.bilibili.com/video/BV-vector-limit-{idx}",
            canonical_url=f"embed://vector-limit/{idx}",
            status=ContentStatus.PARSE_SUCCESS,
            review_status=ReviewStatus.APPROVED,
            title=f"Vector item {idx}",
            body="vector row limit",
            created_at=now,
        )
        db_session.add(item)
        items.append(item)

    await db_session.flush()
    svc = EmbeddingService()
    model_signature = await svc._get_document_embedding_signature()

    for idx, item in enumerate(items):
        db_session.add(
            ContentEmbedding(
                content_id=item.id,
                embedding_model="gemini-embedding-2",
                embedding_model_signature=model_signature,
                index_status="indexed",
                embedding=[1.0, 0.0],
                indexed_at=now - timedelta(minutes=idx),
            )
        )
    await db_session.commit()

    async def _fake_setting(key: str, default=None):
        if key == "embedding_search_max_rows":
            return 2
        return default

    monkeypatch.setattr(
        "app.services.embedding_service.get_setting_value",
        _fake_setting,
    )

    ranked = await svc._vector_rank_ids(
        session=db_session,
        query_vec=[1.0, 0.0],
        filters=await svc._build_content_filters(
            session=db_session,
            platforms=None,
            statuses=None,
            tags=None,
            author=None,
            date_from=None,
            date_to=None,
            scope="library",
        ),
        limit=1,
    )

    assert [content_id for content_id, *_ in ranked] == [items[0].id]
