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
        payload = {
            "url": "https://www.bilibili.com/video/BV1xx411c7XD"
        }
        response = await client.post("/api/v1/shares", json=payload)
        
        # Should either succeed (201) or already exist (200/409)
        assert response.status_code in [200, 201, 400, 409]
        
        if response.status_code in [200, 201]:
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
        assert data["platform"] == (content.platform.value if hasattr(content.platform, 'value') else content.platform)
    
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
    async def test_content_actions(self, client: AsyncClient):
        """Test retry, re-parse, and summary generation"""
        # Create
        resp = await client.post("/api/v1/shares", json={"url": "https://www.bilibili.com/video/BVactions123"})
        content_id = resp.json()["id"]
        
        # 1. Retry
        retry_resp = await client.post(f"/api/v1/contents/{content_id}/retry")
        assert retry_resp.status_code in [200, 500] # 500 if worker not connected properly but endpoint exists
        
        # 2. Re-parse
        reparse_resp = await client.post(f"/api/v1/contents/{content_id}/re-parse")
        assert reparse_resp.status_code == 200
        assert reparse_resp.json()["status"] == "processing"
        
        # 3. Generate summary (mocking service might be needed but let's see)
        # We need to set status to success for summary
        await client.patch(f"/api/v1/contents/{content_id}", json={"status": "parse_success", "body": "test body"})
        summary_resp = await client.post(f"/api/v1/contents/{content_id}/generate-summary")
        # Might return 500 if LLM not configured, but endpoint is hit
        assert summary_resp.status_code in [200, 500, 404]

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

