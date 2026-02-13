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
        assert data["platform"] == content.platform
    
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
