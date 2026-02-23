"""
Twitter/X Adapter Tests
"""
import pytest
from typing import Dict

from app.adapters.twitter import TwitterAdapter
from tests.test_adapters.base import AdapterTestBase


class TestTwitterAdapter(AdapterTestBase):
    """Test suite for Twitter (FxTwitter) adapter"""
    
    @property
    def platform_name(self) -> str:
        return "twitter"
    
    @property
    def adapter_class(self):
        return TwitterAdapter
    
    def get_test_urls(self) -> Dict[str, str]:
        """Fallback URLs if database is empty"""
        return {
            "tweet": "https://x.com/elonmusk/status/2007518880218886635",
        }
    
    @pytest.mark.asyncio
    @pytest.mark.integration  # Requires network
    async def test_parse_from_db(self, adapter, get_platform_urls):
        """Test parsing with real URLs from database"""
        urls = await get_platform_urls("twitter", limit=5)
        
        if not urls:
            pytest.skip("No Twitter URLs in database")
        
        for content_type, url in urls.items():
            print(f"\nTesting {content_type}: {url}")
            result = await self._test_basic_parse(adapter, url)
            assert result.content_type == "tweet"
            assert result.layout_type == "gallery"
            # Twitter should have media or text
            assert result.media_urls or result.body
    
    @pytest.mark.asyncio
    @pytest.mark.integration
    async def test_archive_media_structure(self, adapter, get_platform_urls):
        """Test that archive contains proper media structure"""
        urls = await get_platform_urls("twitter", limit=3)
        
        if not urls:
            pytest.skip("No Twitter URLs in database")
        
        for content_type, url in list(urls.items())[:1]:
            result = await self._test_archive_structure(adapter, url)
            archive = result.archive_metadata.get("archive")
            
            if archive:
                # Twitter archive should have version and images/videos
                assert "version" in archive
                assert isinstance(archive.get("images", []), list)
                assert isinstance(archive.get("videos", []), list)
    
    @pytest.mark.asyncio
    async def test_url_normalization(self, adapter):
        """Test URL cleaning removes tracking parameters"""
        test_cases = [
            "https://x.com/user/status/123456?s=20",
            "https://twitter.com/user/status/123456?ref_src=twsrc",
        ]
        
        for url in test_cases:
            clean = await self._test_url_normalization(adapter, url)
            assert "?" not in clean  # Should remove query params
            assert "/status/" in clean
