from __future__ import annotations

from datetime import timedelta

import pytest
from httpx import AsyncClient

from app.core.time_utils import utcnow
from app.models import (
    Content,
    ContentEmbedding,
    ContentStatus,
    LayoutType,
    Platform,
    ReviewStatus,
)
from app.services.config_service import EmbeddingAIConfig
from app.services.embedding_service import EmbeddingService


def _embedding_config(
    *,
    api_key: str | None = "embedding-key",
    model: str = "gemini-embedding-2",
    output_dimensionality: int = 1536,
    search_max_rows: int = 5000,
) -> EmbeddingAIConfig:
    return EmbeddingAIConfig(
        api_key=api_key,
        model=model,
        output_dimensionality=output_dimensionality,
        search_max_rows=search_max_rows,
    )


@pytest.mark.asyncio
async def test_semantic_search_returns_ranked_results(
    client: AsyncClient,
    db_session,
    monkeypatch,
):
    async def _fake_embed_query(self, query: str) -> list[float]:
        return [1.0, 0.0]

    async def _fake_signature(self) -> str:
        return "test-embedding-signature"

    monkeypatch.setattr(EmbeddingService, "embed_query", _fake_embed_query)
    monkeypatch.setattr(
        EmbeddingService,
        "_get_document_embedding_signature",
        _fake_signature,
    )

    now = utcnow()
    item = Content(
        platform=Platform.BILIBILI,
        url="https://www.bilibili.com/video/BV-semantic-1",
        canonical_url="semantic://bilibili/1",
        status=ContentStatus.PARSE_SUCCESS,
        review_status=ReviewStatus.APPROVED,
        title="Rust 异步运行时对比",
        body="Tokio 和 async-std 在不同场景下的性能差异。",
        content_type="video",
        layout_type=LayoutType.GALLERY,
        created_at=now,
    )
    db_session.add(item)
    await db_session.flush()
    db_session.add(
        ContentEmbedding(
            content_id=item.id,
            embedding_model="gemini-embedding-2",
            embedding_model_signature="test-embedding-signature",
            index_status="indexed",
            embedding=[1.0, 0.0],
            indexed_at=now,
        )
    )
    await db_session.commit()

    resp = await client.get(
        "/api/v1/search/semantic",
        params={"q": "Rust 异步", "top_k": 5},
    )
    assert resp.status_code == 200
    data = resp.json()
    assert data["query"] == "Rust 异步"
    assert data["top_k"] == 5
    assert isinstance(data["results"], list)
    assert len(data["results"]) <= 5

    assert any(r["content_id"] == item.id for r in data["results"])
    result = next(r for r in data["results"] if r["content_id"] == item.id)
    assert result["match_source"] in ("fts", "vector", "hybrid")
    assert isinstance(result["score"], float)
    assert result["status"] == "parse_success"
    assert result["content_type"] == "video"
    assert result["effective_layout_type"] == "gallery"


@pytest.mark.asyncio
async def test_semantic_search_supports_platform_and_date_filters(
    client: AsyncClient,
    db_session,
    monkeypatch,
):
    async def _fake_embed_query(self, query: str) -> list[float]:
        return [1.0, 0.0]

    monkeypatch.setattr(EmbeddingService, "embed_query", _fake_embed_query)

    now = utcnow()
    old_item = Content(
        platform=Platform.BILIBILI,
        url="https://www.bilibili.com/video/BV-semantic-old",
        canonical_url="semantic://bilibili/old",
        status=ContentStatus.PARSE_SUCCESS,
        review_status=ReviewStatus.APPROVED,
        title="Rust 旧文章",
        body="旧内容",
        created_at=now - timedelta(days=30),
    )
    zhihu_item = Content(
        platform=Platform.ZHIHU,
        url="https://www.zhihu.com/question/1/answer/2",
        canonical_url="semantic://zhihu/1",
        status=ContentStatus.PARSE_SUCCESS,
        review_status=ReviewStatus.APPROVED,
        title="Rust 新文章",
        body="新内容",
        created_at=now,
    )
    db_session.add_all([old_item, zhihu_item])
    await db_session.commit()

    resp = await client.get(
        "/api/v1/search/semantic",
        params={
            "q": "Rust",
            "platform": "zhihu",
            "status": "parse_success",
            "date_from": (now - timedelta(days=1)).isoformat(),
            "top_k": 10,
        },
    )
    assert resp.status_code == 200
    data = resp.json()
    ids = {r["content_id"] for r in data["results"]}
    assert zhihu_item.id in ids
    assert old_item.id not in ids


@pytest.mark.asyncio
async def test_semantic_search_rejects_invalid_platform(client: AsyncClient):
    resp = await client.get(
        "/api/v1/search/semantic",
        params={"q": "Rust", "platform": "invalid-platform"},
    )
    assert resp.status_code == 400
    assert "Invalid platform" in str(resp.json())


@pytest.mark.asyncio
async def test_semantic_search_rejects_invalid_status(client: AsyncClient):
    resp = await client.get(
        "/api/v1/search/semantic",
        params={"q": "Rust", "status": "invalid-status"},
    )
    assert resp.status_code == 400
    assert "Invalid status" in str(resp.json())


@pytest.mark.asyncio
async def test_semantic_index_status_and_reindex_dry_run(client: AsyncClient, db_session):
    content = Content(
        platform=Platform.BILIBILI,
        url="https://www.bilibili.com/video/BV-reindex-dry-run",
        canonical_url="semantic://reindex/dry-run",
        status=ContentStatus.PARSE_SUCCESS,
        review_status=ReviewStatus.APPROVED,
        title="Gemini RAG 索引状态",
        body="用于估算 reindex 调用量。",
        created_at=utcnow(),
    )
    db_session.add(content)
    await db_session.commit()
    await db_session.refresh(content)

    status = await client.get("/api/v1/search/semantic/index-status")
    assert status.status_code == 200
    status_data = status.json()
    assert "status_counts" in status_data
    assert "recent_failures" in status_data
    assert "current_model_signature" in status_data

    dry_run = await client.post(
        "/api/v1/search/semantic/reindex",
        json={"scope": "single", "content_id": content.id, "dry_run": True},
    )
    assert dry_run.status_code == 200
    data = dry_run.json()
    assert data["scheduled"] is False
    assert data["candidate_count"] == 1
    assert data["estimated_embedding_calls"] >= 1
    assert data["run_id"] is None


@pytest.mark.asyncio
async def test_semantic_reindex_scheduled_returns_run_id_and_records_success(
    client: AsyncClient,
    monkeypatch,
):
    async def fake_plan_reindex(self, *, scope, content_id, limit, session):
        return [321], 2

    async def fake_reindex_scope(
        self,
        *,
        scope,
        content_id,
        limit,
        batch_size,
        delay_seconds,
        session,
    ):
        return {
            "scope": scope,
            "content_id": content_id,
            "candidate_count": 1,
            "estimated_embedding_calls": 2,
            "indexed": 1,
            "failed": 0,
        }

    monkeypatch.setattr(EmbeddingService, "plan_reindex", fake_plan_reindex)
    monkeypatch.setattr(EmbeddingService, "reindex_scope", fake_reindex_scope)

    response = await client.post(
        "/api/v1/search/semantic/reindex",
        json={"scope": "failed", "limit": 100, "dry_run": False},
    )
    assert response.status_code == 200
    data = response.json()
    assert data["scheduled"] is True
    assert data["run_id"]

    diagnostics = await client.get("/api/v1/background-tasks/diagnostics")
    assert diagnostics.status_code == 200
    runs = diagnostics.json()["recent_task_runs"]
    latest = next(run for run in runs if run["run_id"] == data["run_id"])
    assert latest["task"] == "semantic_reindex"
    assert latest["status"] == "success"
    assert latest["scope"] == "failed"
    assert latest["result"]["indexed"] == 1
    assert latest["result"]["failed"] == 0


@pytest.mark.asyncio
async def test_retry_semantic_embedding_records_run(
    client: AsyncClient,
    db_session,
    monkeypatch,
):
    async def fake_signature(self):
        return "gemini-embedding-2|dim=3|prefix=test|role=document"

    async def fake_model(self):
        return "gemini-embedding-2"

    async def fake_embed_document_text(self, text_val, media_refs):
        assert "retry me" in text_val
        return [0.1, 0.2, 0.3]

    monkeypatch.setattr(EmbeddingService, "_get_document_embedding_signature", fake_signature)
    monkeypatch.setattr(EmbeddingService, "_get_embedding_model", fake_model)
    monkeypatch.setattr(EmbeddingService, "_embed_document_text", fake_embed_document_text)

    content = Content(
        platform=Platform.RSS,
        url="https://example.com/retry-embedding",
        canonical_url="semantic://retry-embedding",
        status=ContentStatus.PARSE_SUCCESS,
        review_status=ReviewStatus.APPROVED,
        title="Retry embedding",
        rich_payload={
            "chunks": [
                {
                    "title": "Chunk 0",
                    "content": "retry me with semantic embedding",
                    "media_refs": [],
                }
            ]
        },
        created_at=utcnow(),
    )
    db_session.add(content)
    await db_session.flush()
    embedding = ContentEmbedding(
        content_id=content.id,
        chunk_index=0,
        chunk_title="Chunk 0",
        source_text="retry me with semantic embedding",
        embedding=[],
        index_status="failed",
        failure_reason="embedding api unavailable",
        retry_count=1,
    )
    db_session.add(embedding)
    await db_session.commit()
    await db_session.refresh(embedding)

    response = await client.post(f"/api/v1/search/semantic/embeddings/{embedding.id}/retry")
    assert response.status_code == 200
    data = response.json()
    assert data["run_id"]
    assert data["embedding_id"] == embedding.id
    assert data["index_status"] == "indexed"
    assert data["failure_reason"] is None

    await db_session.refresh(embedding)
    assert embedding.index_status == "indexed"
    assert embedding.embedding == [0.1, 0.2, 0.3]

    diagnostics = await client.get("/api/v1/background-tasks/diagnostics")
    runs = diagnostics.json()["recent_task_runs"]
    latest = next(run for run in runs if run["run_id"] == data["run_id"])
    assert latest["task"] == "semantic_reindex"
    assert latest["status"] == "success"
    assert latest["scope"] == "embedding"
    assert latest["embedding_id"] == embedding.id
    assert latest["result"]["indexed"] == 1
    assert latest["result"]["failed"] == 0


@pytest.mark.asyncio
async def test_embedding_signature_uses_gemini_2_without_task_type(monkeypatch):
    async def _fake_config(self):
        return _embedding_config(output_dimensionality=1536)

    monkeypatch.setattr(
        "app.services.embedding_service.ConfigService.get_embedding_ai_config",
        _fake_config,
    )
    signature = await EmbeddingService()._get_document_embedding_signature()
    assert signature == "gemini-embedding-2|dim=1536|prefix=vaultstream_rag_v1|role=document"
    assert "task" not in signature.lower()


@pytest.mark.asyncio
async def test_embedding_rejects_non_gemini_2_model(monkeypatch):
    async def _fake_config(self):
        return _embedding_config(model="text-embedding-3-small")

    monkeypatch.setattr(
        "app.services.embedding_service.ConfigService.get_embedding_ai_config",
        _fake_config,
    )
    with pytest.raises(RuntimeError, match="Only gemini-embedding-2"):
        await EmbeddingService()._get_embedding_model()
