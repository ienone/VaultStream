"""
Weibo Adapter Tests (Mocked)
"""
import pytest
import json
import os
import responses
from typing import Dict

from app.adapters.weibo import WeiboAdapter
from app.adapters.base import ParsedContent
from tests.test_adapters.base import AdapterTestBase

# Define paths to mock data
MOCK_DATA_DIR = os.path.join(os.path.dirname(__file__), "..", "data", "weibo")

def load_mock_json(filename):
    with open(os.path.join(MOCK_DATA_DIR, filename), "r", encoding="utf-8") as f:
        return json.load(f)

class TestWeiboAdapter(AdapterTestBase):
    """Test suite for Weibo adapter using mocked data"""

    @property
    def platform_name(self) -> str:
        return "weibo"

    @property
    def adapter_class(self):
        return WeiboAdapter

    def get_test_urls(self) -> Dict[str, str]:
        return {
            "status": "https://weibo.com/2377356574/QuvmNhSq5",
        }

    @pytest.mark.asyncio
    async def test_parse_status_mocked(self, adapter):
        """Test parsing weibo status with mocked API response"""
        bid = "QuvmNhSq5"
        url = f"https://weibo.com/2377356574/{bid}"
        mock_data = load_mock_json(f"status_{bid}.json")
        
        # Mock the API request (using responses since weibo_parser uses requests)
        with responses.RequestsMock() as rsps:
            rsps.add(
                responses.GET,
                f"https://weibo.com/ajax/statuses/show?id={bid}",
                json=mock_data,
                status=200
            )

            result = await adapter.parse(url)
            
            assert result.content_type == "status"
            assert result.content_id == bid
            assert result.platform == "weibo"
            assert result.title or result.body is not None
            assert result.author_name is not None

    @pytest.mark.asyncio
    async def test_url_normalization(self, adapter):
        """Test URL cleaning and expansion"""
        # Test basic cleaning
        url = "https://weibo.com/12345/ABCDE?from=feed"
        clean = await adapter.clean_url(url)
        assert "from=" not in clean
