"""
Xiaohongshu Adapter Tests
"""
import pytest
from typing import Dict

from app.adapters.xiaohongshu import XiaohongshuAdapter
from tests.test_adapters.base import AdapterTestBase


class TestXiaohongshuAdapter(AdapterTestBase):
    """Test suite for Xiaohongshu adapter"""
    
    @property
    def platform_name(self) -> str:
        return "xiaohongshu"
    
    @property
    def adapter_class(self):
        return XiaohongshuAdapter
    
    def get_test_urls(self) -> Dict[str, str]:
        """Fallback URLs if database is empty"""
        return {
            "note": "https://www.xiaohongshu.com/explore/69758150000000000b011944?xsec_token=ABDgfgcEPDW1329W2TkmpnY4-0xMT2Uk2IJRYrxW3PwF8=&xsec_source=",
            "user": "https://www.xiaohongshu.com/user/profile/5e9e828e0000000001009ec8?xsec_token=ABSI6qMGV4mW3Kw2ZvGP7c_wOCZIuQA9jEui40PYZGM9Y=&xsec_source=pc_feed",
        }
    
    @pytest.mark.asyncio
    @pytest.mark.integration
    async def test_parse_from_db(self, adapter, get_platform_urls):
        """Test parsing with real URLs from database"""
        urls = await get_platform_urls("xiaohongshu", limit=5)
        
        if not urls:
            pytest.skip("No Xiaohongshu URLs in database")
        
        for content_type, url in urls.items():
            print(f"\nTesting {content_type}: {url}")
            result = await self._test_basic_parse(adapter, url)
            assert result.content_type in ["note", "video", "user_profile"]
            assert result.layout_type == "gallery"

    @pytest.mark.asyncio
    @pytest.mark.integration
    async def test_archive_media_structure(self, adapter, get_platform_urls):
        """Test that archive contains proper media structure"""
        urls = await get_platform_urls("xiaohongshu", limit=3)
        
        if not urls or "note" not in urls:
            pytest.skip("No Xiaohongshu note URLs in database")
        
        url = urls["note"]
        result = await self._test_archive_structure(adapter, url)
        archive = result.raw_metadata.get("archive")
        
        if archive:
            # Xiaohongshu archive should have version and blocks
            assert "version" in archive
            assert "blocks" in archive
            assert isinstance(archive.get("images", []), list)
            assert isinstance(archive.get("videos", []), list)
