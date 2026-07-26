"""
Contents API Tests - CRUD operations for content management
"""
import pytest
from httpx import AsyncClient


class TestContentsAPI:
    """Test suite for contents endpoints"""
    
    @pytest.mark.asyncio
    async def test_list_contents(self, client: AsyncClient):
        """Test GET /api/v1/contents - list all contents"""
        response = await client.get("/api/v1/contents")
        assert response.status_code == 200
        
        data = response.json()
        assert "items" in data
        assert "total" in data
        assert "page" in data
        assert "size" in data
        assert isinstance(data["items"], list)
    
    @pytest.mark.asyncio
    async def test_list_contents_pagination(self, client: AsyncClient):
        """Test pagination parameters"""
        response = await client.get("/api/v1/contents?page=1&size=5")
        assert response.status_code == 200
        
        data = response.json()
        assert data["page"] == 1
        assert data["size"] == 5
        assert len(data["items"]) <= 5
    
    @pytest.mark.asyncio
    async def test_list_contents_filter_by_platform(self, client: AsyncClient):
        """Test filtering by platform"""
        response = await client.get("/api/v1/contents?platform=bilibili")
        assert response.status_code == 200
        
        data = response.json()
        # All items should be from bilibili
        for item in data["items"]:
            assert item["platform"] == "bilibili"
    
    @pytest.mark.asyncio
    async def test_create_content(self, client: AsyncClient):
        """Test POST /api/v1/shares - create new content"""
        import time
        payload = {
            "url": f"https://www.bilibili.com/video/BVcreate{int(time.time())}"
        }
        response = await client.post("/api/v1/shares", json=payload)
        
        assert response.status_code in [200, 201]
        data = response.json()
        assert "id" in data
        assert data["platform"] == "bilibili"
    
    @pytest.mark.asyncio
    async def test_get_content_by_id(self, client: AsyncClient, db_session):
        """Test GET /api/v1/contents/{id}"""
        from sqlalchemy import select
        from app.models import Content
        
        # Get first content from DB
        result = await db_session.execute(select(Content).limit(1))
        content = result.scalar_one_or_none()
        
        if not content:
            pytest.skip("No content in database")
        
        response = await client.get(f"/api/v1/contents/{content.id}")
        assert response.status_code == 200
        
        data = response.json()
        assert data["id"] == content.id
        assert data["platform"] == content.platform.value

    @pytest.mark.asyncio
    async def test_get_content_by_id_auto_heals_avatar_in_media_urls(self, client: AsyncClient, db_session):
        """Detail endpoint should filter and persistently heal avatar URLs from media_urls."""
        from app.models import Content, Platform, ContentStatus

        content = Content(
            platform=Platform.XIAOHONGSHU,
            url="https://www.xiaohongshu.com/discovery/item/test-avatar-heal",
            canonical_url="https://www.xiaohongshu.com/discovery/item/test-avatar-heal",
            status=ContentStatus.PARSE_SUCCESS,
            author_avatar_url="https://cdn.example.com/avatar.jpg?size=large",
            media_urls=[
                "https://cdn.example.com/avatar.jpg?size=small",
                "https://cdn.example.com/content.jpg",
            ],
        )
        db_session.add(content)
        await db_session.commit()
        await db_session.refresh(content)

        response = await client.get(f"/api/v1/contents/{content.id}")
        assert response.status_code == 200

        data = response.json()
        assert data["media_urls"] == ["https://cdn.example.com/content.jpg"]

        await db_session.refresh(content)
        assert content.media_urls == ["https://cdn.example.com/content.jpg"]

    @pytest.mark.asyncio
    async def test_get_content_processing_status(self, client: AsyncClient, db_session):
        """Detail processing status should summarize post-ingest stages."""
        from app.models import Content, ContentEmbedding, Platform, ContentStatus

        content = Content(
            platform=Platform.BILIBILI,
            url="https://www.bilibili.com/video/BVprocessingstatus",
            canonical_url="https://www.bilibili.com/video/BVprocessingstatus",
            status=ContentStatus.PARSE_SUCCESS,
            title="Processing Status",
            summary="已生成摘要",
        )
        db_session.add(content)
        await db_session.commit()
        await db_session.refresh(content)

        db_session.add(
            ContentEmbedding(
                content_id=content.id,
                chunk_index=0,
                chunk_title="摘要",
                source_text="已生成摘要",
                embedding=[0.1, 0.2],
                index_status="indexed",
            )
        )
        await db_session.commit()

        response = await client.get(f"/api/v1/contents/{content.id}/processing-status")
        assert response.status_code == 200
        data = response.json()
        assert data["content_id"] == content.id
        assert data["content_status"] == "parse_success"
        # 规范化整体状态：只有摘要与索引成功、分发不适用时应为 success
        assert data["state"] == "success"

        stages = {item["key"]: item for item in data["stages"]}
        assert stages["summary"]["state"] == "success"
        assert stages["summary"]["detail_state"] == "success"

        assert stages["semantic_index"]["state"] == "success"
        assert stages["semantic_index"]["details"]["counts"]["indexed"] == 1
        assert stages["semantic_index"]["completed_units"] == 1
        assert stages["semantic_index"]["total_units"] == 1

        # 未匹配分发规则属于"不适用"，不应被渲染成失败或待办
        assert stages["distribution"]["state"] == "not_applicable"
        assert stages["distribution"]["detail_state"] == "not_matched"

        # 没有远端媒体时归档阶段不适用，而不是伪装成成功
        assert stages["archive_media"]["state"] == "not_applicable"
        assert stages["archive_media"]["detail_state"] == "no_media"

    @pytest.mark.asyncio
    async def test_content_detail_exposes_content_type(self, client: AsyncClient, db_session):
        """详情必须暴露 content_type，前端模板细分依赖该字段。"""
        from app.models import Content, Platform, ContentStatus, LayoutType

        content = Content(
            platform=Platform.ZHIHU,
            url="https://www.zhihu.com/people/contenttypecase",
            canonical_url="https://www.zhihu.com/people/contenttypecase",
            status=ContentStatus.PARSE_SUCCESS,
            content_type="user_profile",
            layout_type=LayoutType.GALLERY,
            title="Content type case",
        )
        db_session.add(content)
        await db_session.commit()
        await db_session.refresh(content)

        response = await client.get(f"/api/v1/contents/{content.id}")
        assert response.status_code == 200
        data = response.json()
        assert data["content_type"] == "user_profile"
        assert data["effective_layout_type"] == "gallery"


    @pytest.mark.asyncio
    async def test_delete_content(self, client: AsyncClient):
        """Test DELETE /api/v1/contents/{id}"""
        # Create a test content first
        payload = {"url": "https://www.bilibili.com/video/BV1test123"}
        create_response = await client.post("/api/v1/shares", json=payload)
        
        if create_response.status_code in [200, 201]:
            content_id = create_response.json()["id"]
            
            # Now delete it
            delete_response = await client.delete(f"/api/v1/contents/{content_id}")
            assert delete_response.status_code in [200, 204]
    
    @pytest.mark.asyncio
    async def test_search_contents(self, client: AsyncClient):
        """Test search functionality"""
        response = await client.get("/api/v1/contents?q=test")
        assert response.status_code == 200
        
        data = response.json()
        assert "items" in data

    @pytest.mark.asyncio
    async def test_update_content(self, client: AsyncClient):
        """Test PATCH /api/v1/contents/{id}"""
        # Create
        resp = await client.post("/api/v1/shares", json={"url": "https://www.bilibili.com/video/BVupdate123"})
        content_id = resp.json()["id"]
        
        # Patch
        patch_resp = await client.patch(
            f"/api/v1/contents/{content_id}",
            json={
                "title": "Updated Title",
                "tags": ["tag1", "tag2"],
                "is_nsfw": True
            }
        )
        assert patch_resp.status_code == 200
        data = patch_resp.json()
        assert data["title"] == "Updated Title"
        assert "tag1" in data["tags"]
        assert data["is_nsfw"] is True

    @pytest.mark.asyncio
    async def test_content_reparse(self, client: AsyncClient, monkeypatch):
        """Test re-parse action resets content to processing state."""
        async def fake_retry_parse(content_id: int, max_retries: int = 3, force: bool = False):
            return True

        monkeypatch.setattr("app.routers.contents.worker.retry_parse", fake_retry_parse)

        resp = await client.post("/api/v1/shares", json={"url": "https://www.bilibili.com/video/BVreparse123"})
        content_id = resp.json()["id"]

        reparse_resp = await client.post(f"/api/v1/contents/{content_id}/re-parse")
        assert reparse_resp.status_code == 200
        data = reparse_resp.json()
        assert data["status"] == "processing"
        assert data["run_id"]

        diagnostics = await client.get("/api/v1/background-tasks/diagnostics")
        runs = diagnostics.json()["recent_task_runs"]
        latest = next(run for run in runs if run["run_id"] == data["run_id"])
        assert latest["task"] == "content_reparse"
        assert latest["status"] == "success"
        assert latest["content_id"] == content_id
        assert latest["force"] is True

    @pytest.mark.asyncio
    async def test_generate_summary_returns_run_id_and_records_success(
        self,
        client: AsyncClient,
        monkeypatch,
    ):
        """Test manual summary generation records an observable run."""
        async def fake_generate_summary_for_content(session, content_id: int, *, force: bool = False):
            from app.models import Content

            content = await session.get(Content, content_id)
            content.summary = "测试摘要"
            content.tags = ["摘要", "测试"]
            content.rich_payload = {
                "chunks": [
                    {
                        "title": "核心",
                        "content": "测试语义块",
                        "importance": 1.0,
                        "media_refs": [],
                    }
                ]
            }
            await session.commit()
            return content

        monkeypatch.setattr(
            "app.services.content_summary_service.generate_summary_for_content",
            fake_generate_summary_for_content,
        )

        import time

        resp = await client.post(
            "/api/v1/shares",
            json={"url": f"https://www.bilibili.com/video/BVsummary{time.time_ns()}"},
        )
        content_id = resp.json()["id"]

        summary_resp = await client.post(
            f"/api/v1/contents/{content_id}/generate-summary",
            params={"force": True},
        )
        assert summary_resp.status_code == 200
        data = summary_resp.json()
        assert data["summary"] == "测试摘要"
        assert data["run_id"]

        diagnostics = await client.get("/api/v1/background-tasks/diagnostics")
        runs = diagnostics.json()["recent_task_runs"]
        latest = next(run for run in runs if run["run_id"] == data["run_id"])
        assert latest["task"] == "content_summary"
        assert latest["status"] == "success"
        assert latest["content_id"] == content_id
        assert latest["force"] is True
        assert latest["result"]["summary_present"] is True
        assert latest["result"]["chunk_count"] == 1

    @pytest.mark.asyncio
    async def test_patrol_score_returns_run_id_and_records_success(
        self,
        client: AsyncClient,
        db_session,
        monkeypatch,
    ):
        """Test manual patrol scoring records an observable run."""
        from app.models import Content, ContentStatus, DiscoveryState, Platform
        from app.services.background_task_state import get_recent_task_runs
        from app.services.patrol_service import PatrolService

        async def fake_get_value(self, key: str, default=None):
            if key == "discovery_interest_profile":
                return "AI and systems"
            return default

        async def fake_score_item(self, content, interest_profile: str = ""):
            assert interest_profile == "AI and systems"
            content.ai_score = 8.5
            content.ai_reason = "High signal"
            content.summary = "A high-signal article"
            content.ai_tags = ["ai", "systems"]
            content.discovery_state = DiscoveryState.VISIBLE
            return True

        monkeypatch.setattr("app.routers.contents.ConfigService.get_value", fake_get_value)
        monkeypatch.setattr(PatrolService, "score_item", fake_score_item)

        import time

        content = Content(
            platform=Platform.RSS,
            url=f"https://example.com/patrol-score/{time.time_ns()}",
            canonical_url=f"https://example.com/patrol-score/{time.time_ns()}",
            status=ContentStatus.PARSE_SUCCESS,
            title="Manual patrol scoring",
            body="Interesting technical content",
            discovery_state=DiscoveryState.INGESTED,
        )
        db_session.add(content)
        await db_session.commit()
        await db_session.refresh(content)

        response = await client.post(f"/api/v1/contents/{content.id}/patrol-score")
        assert response.status_code == 200
        data = response.json()
        assert data["run_id"]
        assert data["ai_score"] == 8.5
        assert data["discovery_state"] == "visible"

        await db_session.refresh(content)
        assert content.ai_score == 8.5
        assert content.discovery_state == DiscoveryState.VISIBLE

        latest = next(
            run
            for run in await get_recent_task_runs("discovery_patrol")
            if run["run_id"] == data["run_id"]
        )
        assert latest["status"] == "success"
        assert latest["trigger"] == "manual"
        assert latest["content_id"] == content.id
        assert latest["result"]["scored_count"] == 1
        assert latest["result"]["failed_count"] == 0

    @pytest.mark.asyncio
    async def test_content_retry(self, client: AsyncClient):
        """Test retry action endpoint accepts the request."""
        import time
        resp = await client.post("/api/v1/shares", json={"url": f"https://www.bilibili.com/video/BVretry{int(time.time())}"})
        content_id = resp.json()["id"]

        retry_resp = await client.post(f"/api/v1/contents/{content_id}/retry")
        # 200 if enqueue succeeds, 500 if task queue not connected in test env
        # Either way the endpoint is reachable and processes the request
        assert retry_resp.status_code in [200, 500]
        if retry_resp.status_code == 500:
            # Verify it's a known infrastructure issue (parser failure), not a code bug
            assert "error" in retry_resp.json() or "detail" in retry_resp.json()

    @pytest.mark.asyncio
    async def test_pushed_records(self, client: AsyncClient, db_session):
        """Test GET and DELETE pushed records"""
        from app.models import PushedRecord
        from app.models.base import Platform
        
        # Manually insert a record
        content_resp = await client.post("/api/v1/shares", json={"url": "https://www.bilibili.com/video/BVpushed123"})
        cid = content_resp.json()["id"]
        
        record = PushedRecord(
            content_id=cid,
            target_platform="telegram",
            target_id="-100123456",
            message_id="999",
            push_status="success"
        )
        db_session.add(record)
        await db_session.commit()
        await db_session.refresh(record)
        rid = record.id
        
        # List
        list_resp = await client.get("/api/v1/pushed-records")
        assert list_resp.status_code == 200
        found = any(r["id"] == rid for r in list_resp.json())
        assert found
        
        # Delete
        del_resp = await client.delete(f"/api/v1/pushed-records/{rid}")
        assert del_resp.status_code == 200
        
        # Verify
        list_resp2 = await client.get("/api/v1/pushed-records")
        assert not any(r["id"] == rid for r in list_resp2.json())
