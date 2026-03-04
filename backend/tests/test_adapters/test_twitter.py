"""
Twitter Adapter Tests (Mocked)
"""
import pytest
import json
import os
import re
from typing import Dict

from app.adapters.twitter import TwitterAdapter
from app.adapters.base import ParsedContent
from tests.test_adapters.base import AdapterTestBase

# Define paths to mock data
MOCK_DATA_DIR = os.path.join(os.path.dirname(__file__), "..", "data", "twitter")

def load_mock_json(filename):
    with open(os.path.join(MOCK_DATA_DIR, filename), "r", encoding="utf-8") as f:
        return json.load(f)

class TestTwitterAdapter(AdapterTestBase):
    """Test suite for Twitter adapter using mocked data"""

    @property
    def platform_name(self) -> str:
        return "twitter"

    @property
    def adapter_class(self):
        return TwitterAdapter

    def get_test_urls(self) -> Dict[str, str]:
        return {
            "tweet": "https://x.com/nbuna_staff/status/2029120097969946739",
        }

    @pytest.mark.asyncio
    async def test_parse_tweet_mocked(self, adapter, httpx_mock):
        """Test parsing tweet with mocked API response"""
        tweet_id = "2029120097969946739"
        username = "nbuna_staff"
        url = f"https://x.com/{username}/status/{tweet_id}"
        mock_data = load_mock_json(f"tweet_{tweet_id}.json")
        
        # Mock the FxTwitter API request
        httpx_mock.add_response(
            url=f"https://api.fxtwitter.com/{username}/status/{tweet_id}",
            json=mock_data
        )

        result = await adapter.parse(url)
        
        assert result.content_type == "tweet"
        assert result.content_id == tweet_id
        assert result.platform == "twitter"
        assert result.author_name == "n-buna" or result.author_name is not None
        assert len(result.body) > 0

    @pytest.mark.asyncio
    async def test_url_normalization(self, adapter):
        """Test URL cleaning"""
        test_cases = [
            ("https://x.com/user/status/123?s=20",
             "https://x.com/user/status/123"),
            ("https://twitter.com/user/status/456?from=search",
             "https://twitter.com/user/status/456"),
        ]

        for dirty_url, expected_clean in test_cases:
            clean = await adapter.clean_url(dirty_url)
            assert clean == expected_clean
