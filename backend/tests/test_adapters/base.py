"""
Base class for platform adapter tests

Provides common test methods and fixtures for all adapters.
"""
import pytest
from typing import Dict, List, Optional, Type
from abc import ABC, abstractmethod

from app.adapters.base import PlatformAdapter, ParsedContent


class AdapterTestBase(ABC):
    """Base class for all adapter tests"""
    
    @property
    @abstractmethod
    def platform_name(self) -> str:
        """Platform identifier (e.g., 'bilibili', 'twitter')"""
        pass
    
    @property
    @abstractmethod
    def adapter_class(self) -> Type[PlatformAdapter]:
        """Adapter class to test"""
        pass
    
    @abstractmethod
    def get_test_urls(self) -> Dict[str, str]:
        """
        Return test URLs for different content types
        
        Returns:
            Dict mapping content_type to URL
            Example: {"video": "https://...", "article": "https://..."}
        """
        pass
    
    @pytest.fixture
    def adapter(self) -> PlatformAdapter:
        """Create adapter instance"""
        return self.adapter_class()
    
    async def _test_basic_parse(self, adapter: PlatformAdapter, url: str):
        """Generic parsing test - validates basic fields"""
        result = await adapter.parse(url)
        
        # Validate required fields
        assert isinstance(result, ParsedContent)
        assert result.platform == self.platform_name
        assert result.content_type is not None
        assert result.content_id is not None
        assert result.clean_url is not None
        assert result.layout_type is not None, "ParsedContent.layout_type should not be None"
        
        # Validate optional but expected fields
        assert result.title or result.body, "Should have title or body"
        
        return result
    
    async def _test_archive_structure(self, adapter: PlatformAdapter, url: str):
        """Validate archive structure in archive_metadata"""
        result = await adapter.parse(url)
        archive = result.archive_metadata.get("archive")
        
        if archive:
            # Validate common archive fields
            assert "type" in archive, "Archive should have 'type'"
            assert isinstance(archive.get("images", []), list), "images should be list"
            assert isinstance(archive.get("videos", []), list), "videos should be list"
            
            # Validate image structure if present
            for img in archive.get("images", []):
                assert "url" in img, "Each image should have 'url'"
        
        return result
    
    async def _test_url_normalization(self, adapter: PlatformAdapter, url: str):
        """Test URL cleaning and normalization"""
        clean_url = await adapter.clean_url(url)
        
        assert clean_url is not None
        assert isinstance(clean_url, str)
        assert len(clean_url) > 0
        
        # Should be a valid URL
        assert clean_url.startswith(("http://", "https://"))
        
        return clean_url
