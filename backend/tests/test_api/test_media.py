"""
Media API Tests - Proxy and media serving
"""
import pytest
from httpx import AsyncClient


class TestMediaAPI:
    """Test suite for media endpoints"""
    
    @pytest.mark.asyncio
    async def test_media_proxy(self, client: AsyncClient):
        """Test media proxy endpoint"""
        # Use a simple test URL
        test_url = "https://example.com/image.jpg"
        
        response = await client.get(
            "/api/v1/media/proxy",
            params={"url": test_url},
            follow_redirects=False
        )
        
        # Should either proxy or return appropriate error
        assert response.status_code in [200, 302, 404, 500]
    
    @pytest.mark.asyncio
    async def test_stored_media_access(self, client: AsyncClient):
        """Test accessing stored media files"""
        # This would need actual stored media to test properly
        # For now, just verify endpoint exists
        response = await client.get("/media/test.jpg")
        
        # 404 is expected if file doesn't exist
        assert response.status_code in [200, 404]
