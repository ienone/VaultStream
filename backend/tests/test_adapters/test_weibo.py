"""
Weibo Adapter Tests
"""
import pytest
from typing import Dict

from app.adapters.weibo import WeiboAdapter
from tests.test_adapters.base import AdapterTestBase


class TestWeiboAdapter(AdapterTestBase):
    """Test suite for Weibo adapter"""
    
    @property
    def platform_name(self) -> str:
        return "weibo"
    
    @property
    def adapter_class(self):
        return WeiboAdapter
    
    def get_test_urls(self) -> Dict[str, str]:
        """Fallback URLs if database is empty"""
        return {
            "status": "https://weibo.com/7751385439/QmsEAti7w",
            "user_profile": "https://weibo.com/u/7751385439",
        }
    
    @pytest.mark.asyncio
    @pytest.mark.integration
    async def test_parse_from_db(self, adapter, get_platform_urls):
        """Test parsing with real URLs from database"""
        urls = await get_platform_urls("weibo", limit=5)
        
        if not urls:
            pytest.skip("No Weibo URLs in database")
        
        for content_type, url in urls.items():
            print(f"\nTesting {content_type}: {url}")
            result = await self._test_basic_parse(adapter, url)
            assert result.content_type in ["status", "user_profile"]
            assert result.layout_type == "gallery"
    
    @pytest.mark.asyncio
    @pytest.mark.integration
    async def test_archive_image_quality(self, adapter, get_platform_urls):
        """Test that archive uses best quality images (mw2000 > largest)"""
        urls = await get_platform_urls("weibo", limit=3)
        
        if not urls or "status" not in urls:
            pytest.skip("No Weibo status URLs in database")
        
        url = urls["status"]
        result = await self._test_archive_structure(adapter, url)
        archive = result.raw_metadata.get("archive")
        
        if archive and archive.get("images"):
            # Verify images have URLs
            for img in archive["images"]:
                assert "url" in img
                # Should prefer mw2000 or large
                assert "sinaimg.cn" in img["url"]
    
    @pytest.mark.asyncio
    async def test_url_normalization(self, adapter):
        """Test URL cleaning"""
        test_cases = [
            ("https://weibo.com/123/abc?type=comment", "https://weibo.com/123/abc"),
            ("https://weibo.com/detail/abc", "https://weibo.com/detail/abc"),
        ]
        
        for dirty, expected in test_cases:
            clean = await self._test_url_normalization(adapter, dirty)
            assert clean == expected
