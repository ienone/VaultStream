"""
Xiaohongshu Adapter Tests (Mocked)
"""
import pytest
import json
import os
import re
from typing import Dict

from app.adapters.xiaohongshu import XiaohongshuAdapter
from app.adapters.base import ParsedContent
from tests.test_adapters.base import AdapterTestBase

# Define paths to mock data
MOCK_DATA_DIR = os.path.join(os.path.dirname(__file__), "..", "data", "xiaohongshu")

def load_mock_json(filename):
    with open(os.path.join(MOCK_DATA_DIR, filename), "r", encoding="utf-8") as f:
        return json.load(f)

class TestXiaohongshuAdapter(AdapterTestBase):
    """Test suite for Xiaohongshu adapter using mocked data"""

    @property
    def platform_name(self) -> str:
        return "xiaohongshu"

    @property
    def adapter_class(self):
        return XiaohongshuAdapter

    def get_test_urls(self) -> Dict[str, str]:
        return {
            "note": "https://www.xiaohongshu.com/discovery/item/69a7a9ff000000002802080d",
        }

    @pytest.fixture
    def adapter(self):
        return XiaohongshuAdapter(cookies={"a1": "test_cookie"})

    @pytest.mark.asyncio
    async def test_parse_note_mocked(self, adapter, httpx_mock):
        """Test parsing XHS note with mocked API response"""
        note_id = "69a7a9ff000000002802080d"
        url = f"https://www.xiaohongshu.com/discovery/item/{note_id}"
        mock_data = load_mock_json(f"note_{note_id}.json")
        
        # Mock the API request (POST to edith.xiaohongshu.com/api/sns/web/v1/feed)
        httpx_mock.add_response(
            method="POST",
            url=re.compile(r"https://edith\.xiaohongshu\.com/api/sns/web/v1/feed.*"),
            json=mock_data,
            status_code=200
        )

        result = await adapter.parse(url)
        
        assert result.content_type == "note"
        assert result.content_id == note_id
        assert result.platform == "xiaohongshu"
        assert result.title is not None or result.body is not None
        assert result.author_name is not None

    @pytest.mark.asyncio
    async def test_url_normalization(self, adapter):
        """Test URL cleaning"""
        url = "https://www.xiaohongshu.com/explore/123456?xhsshare=pc_web&source=webshare"
        clean = await adapter.clean_url(url)
        # Note: XiaohongshuAdapter.clean_url might behave differently depending on implementation
        # usually it removes common tracking params
        assert "xhsshare" not in clean
