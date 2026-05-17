from __future__ import annotations

from datetime import timedelta

import pytest
from httpx import AsyncClient

from app.core.time_utils import utcnow
from app.models import Content, ContentStatus, Platform, ReviewStatus
from app.services.embedding_service import EmbeddingService


@pytest.mark.asyncio
async def test_semantic_search_returns_ranked_results(client: AsyncClient, db_session):
    now = utcnow()
    item = Content(
        platform=Platform.BILIBILI,
        url="https://www.bilibili.com/video/BV-semantic-1",
        canonical_url="semantic://bilibili/1",
        status=ContentStatus.PARSE_SUCCESS,
        review_status=ReviewStatus.APPROVED,
        title="Rust 异步运行时对比",
        body="Tokio 和 async-std 在不同场景下的性能差异。",
        created_at=now,
    )
    db_session.add(item)
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


@pytest.mark.asyncio
async def test_semantic_search_supports_platform_and_date_filters(client: AsyncClient, db_session):
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


@pytest.mark.asyncio
async def test_embedding_signature_uses_gemini_2_without_task_type(monkeypatch):
    async def _fake_setting(key: str, default=None):
        values = {
            "embedding_model": "gemini-embedding-2",
            "embedding_output_dimensionality": "1536",
        }
        return values.get(key, default)

    monkeypatch.setattr("app.services.embedding_service.get_setting_value", _fake_setting)
    signature = await EmbeddingService()._get_document_embedding_signature()
    assert signature == "gemini-embedding-2|dim=1536|prefix=vaultstream_rag_v1|role=document"
    assert "task" not in signature.lower()


@pytest.mark.asyncio
async def test_embedding_rejects_non_gemini_2_model(monkeypatch):
    async def _fake_setting(key: str, default=None):
        if key == "embedding_model":
            return "text-embedding-3-small"
        return default

    monkeypatch.setattr("app.services.embedding_service.get_setting_value", _fake_setting)
    with pytest.raises(RuntimeError, match="Only gemini-embedding-2"):
        await EmbeddingService()._get_embedding_model()
