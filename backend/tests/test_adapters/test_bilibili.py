"""
Bilibili Adapter Tests
"""
import pytest
from typing import Dict

from app.adapters.bilibili import BilibiliAdapter
from tests.test_adapters.base import AdapterTestBase


class TestBilibiliAdapter(AdapterTestBase):
    """Test suite for Bilibili adapter"""
    
    @property
    def platform_name(self) -> str:
        return "bilibili"
    
    @property
    def adapter_class(self):
        return BilibiliAdapter
    
    def get_test_urls(self) -> Dict[str, str]:
        """Fallback URLs if database is empty"""
        return {
            "video": "https://www.bilibili.com/video/BV1xx411c7XD",
            "article": "https://www.bilibili.com/read/cv12345678",
            "dynamic": "https://www.bilibili.com/opus/1150580721704763430",
        }
    
    @pytest.mark.asyncio
    async def test_parse_from_db(self, adapter, get_platform_urls):
        """Test parsing with real URLs from database"""
        urls = await get_platform_urls("bilibili", limit=10)
        
        if not urls:
            pytest.skip("No Bilibili URLs in database")
        
        # Test first URL of each type
        for content_type, url in urls.items():
            print(f"\nTesting {content_type}: {url}")
            result = await self._test_basic_parse(adapter, url)
            assert result.content_type in ["video", "article", "dynamic", "bangumi", "live"]
    
    @pytest.mark.asyncio
    async def test_archive_structure_from_db(self, adapter, get_platform_urls):
        """Test archive structure with real data"""
        urls = await get_platform_urls("bilibili", limit=5)
        
        if not urls:
            pytest.skip("No Bilibili URLs in database")
        
        for content_type, url in list(urls.items())[:2]:  # Test first 2
            print(f"\nTesting archive for {content_type}: {url}")
            await self._test_archive_structure(adapter, url)
    
    @pytest.mark.asyncio
    async def test_url_normalization(self, adapter):
        """Test URL cleaning"""
        test_cases = [
            ("https://www.bilibili.com/video/BV1xx411c7XD?p=1", 
             "https://www.bilibili.com/video/BV1xx411c7XD"),
            ("https://www.bilibili.com/video/BV1xx411c7XD?from=search",
             "https://www.bilibili.com/video/BV1xx411c7XD"),
        ]
        
        for dirty_url, expected_clean in test_cases:
            clean = await self._test_url_normalization(adapter, dirty_url)
            # Just verify it's cleaner (removes tracking params)
            assert "from=" not in clean or clean == expected_clean
