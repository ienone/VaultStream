"""
Weibo Adapter Tests (Mocked)
"""
import pytest
import json
import os
import responses
from copy import deepcopy
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
            assert result.layout_type == "gallery"

    @pytest.mark.asyncio
    async def test_video_status_uses_video_layout(self, adapter):
        bid = "Video123"
        url = f"https://weibo.com/3203137375/{bid}"
        mock_data = {
            "ok": 1,
            "id": 1,
            "text": "#视频测试# 正文",
            "created_at": "Mon Jul 27 15:42:11 +0800 2026",
            "user": {
                "id": 3203137375,
                "screen_name": "视频作者",
                "avatar_hd": "https://example.com/avatar.jpg",
            },
            "page_info": {
                "type": "11",
                "object_type": "video",
                "page_pic": "https://example.com/cover.jpg",
                "media_info": {"stream_url": "https://example.com/video.mp4"},
            },
            "reposts_count": 1,
            "comments_count": 2,
            "attitudes_count": 3,
            "topic_struct": [{"topic_title": "视频测试"}],
        }

        with responses.RequestsMock() as rsps:
            rsps.add(
                responses.GET,
                f"https://weibo.com/ajax/statuses/show?id={bid}",
                json=deepcopy(mock_data),
                status=200,
            )
            result = await adapter.parse(url)

        assert result.layout_type == "video"
        assert result.cover_url == "https://example.com/cover.jpg"
        assert "https://example.com/video.mp4" in result.media_urls
        assert result.source_tags == ["视频测试"]

    @pytest.mark.asyncio
    async def test_url_normalization(self, adapter):
        """Test URL cleaning and expansion"""
        # Test basic cleaning
        url = "https://weibo.com/12345/ABCDE?from=feed"
        clean = await adapter.clean_url(url)
        assert "from=" not in clean
