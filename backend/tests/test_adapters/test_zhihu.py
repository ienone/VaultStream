"""
Zhihu Adapter Tests
"""
import pytest
from typing import Dict

from app.adapters.zhihu import ZhihuAdapter
from tests.test_adapters.base import AdapterTestBase


class TestZhihuAdapter(AdapterTestBase):
    """Test suite for Zhihu adapter"""
    
    @property
    def platform_name(self) -> str:
        return "zhihu"
    
    @property
    def adapter_class(self):
        return ZhihuAdapter
    
    def get_test_urls(self) -> Dict[str, str]:
        """Fallback URLs if database is empty"""
        return {
            "answer": "https://www.zhihu.com/question/123/answer/456",
            "article": "https://zhuanlan.zhihu.com/p/123456",
        }
    
    @pytest.mark.asyncio
    @pytest.mark.integration
    async def test_parse_from_db(self, adapter, get_platform_urls):
        """Test parsing with real URLs from database"""
        urls = await get_platform_urls("zhihu", limit=10)
        
        if not urls:
            pytest.skip("No Zhihu URLs in database")
        
        for content_type, url in urls.items():
            print(f"\nTesting {content_type}: {url}")
            result = await self._test_basic_parse(adapter, url)
            assert result.content_type in ["answer", "article", "question", "pin", "user_profile"]
            
            # 校验布局类型
            if result.content_type in ["answer", "article"]:
                assert result.layout_type == "article"
            elif result.content_type in ["question", "pin", "user_profile"]:
                assert result.layout_type == "gallery"
    
    @pytest.mark.asyncio
    @pytest.mark.integration
    async def test_api_vs_html_parsing(self, adapter, get_platform_urls):
        """Test that API-first types use API, HTML-only types use HTML"""
        urls = await get_platform_urls("zhihu", limit=5)
        
        if not urls:
            pytest.skip("No Zhihu URLs in database")
        
        for content_type, url in urls.items():
            result = await adapter.parse(url)
            
            # Verify parsing succeeded
            assert result.content_id is not None
            
            # Check if archive exists and has expected structure
            if result.archive_metadata.get("archive"):
                archive = result.archive_metadata["archive"]
                assert "type" in archive
                assert archive["type"].startswith("zhihu_")
    
    @pytest.mark.asyncio
    async def test_url_normalization(self, adapter):
        """Test URL cleaning"""
        test_cases = [
            "https://www.zhihu.com/question/123/answer/456?utm_source=wechat",
            "https://zhuanlan.zhihu.com/p/123456?from=timeline",
        ]
        
        for url in test_cases:
            clean = await self._test_url_normalization(adapter, url)
            assert "utm_source" not in clean
            assert "from=" not in clean
