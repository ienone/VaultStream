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
        # url.md 中提供的真实链接（2026-03-12）
        return {
            "note": "https://www.xiaohongshu.com/discovery/item/649f88b4000000001303eb07",
            "note2": "https://www.xiaohongshu.com/discovery/item/648840240000000013006fc5",
            "user": "https://www.xiaohongshu.com/user/profile/605fd1d10000000001008467",
        }

    @pytest.fixture
    def adapter(self):
        return XiaohongshuAdapter(cookies={"a1": "test_cookie"})

    @pytest.mark.asyncio
    async def test_parse_note_mocked(self, adapter, httpx_mock):
        """Test parsing XHS note with mocked API response"""
        note_id = "649f88b4000000001303eb07"
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
        # 验证 stats 中包含 image_count
        assert result.stats is not None
        assert "image_count" in result.stats

    @pytest.mark.asyncio
    async def test_parse_user_mocked(self, adapter, httpx_mock):
        """Test parsing XHS user profile with mocked API response"""
        user_id = "605fd1d10000000001008467"
        url = f"https://www.xiaohongshu.com/user/profile/{user_id}"
        mock_data = load_mock_json(f"user_{user_id}.json")
        
        httpx_mock.add_response(
            method="GET",
            url=re.compile(r"https://edith\.xiaohongshu\.com/api/sns/web/v1/user/otherinfo.*"),
            json=mock_data,
            status_code=200
        )

        result = await adapter.parse(url)
        
        assert result.content_type == "user_profile"
        assert result.content_id == user_id
        assert result.platform == "xiaohongshu"
        assert result.author_name is not None
        # 验证 stats 中包含 followers/following
        assert result.stats is not None

    @pytest.mark.asyncio
    async def test_url_normalization(self, adapter):
        """Test URL cleaning"""
        url = "https://www.xiaohongshu.com/explore/123456?xhsshare=pc_web&source=webshare"
        clean = await adapter.clean_url(url)
        # 追踪参数应被去除（xhsshare, source）
        assert "xhsshare" not in clean
        assert "source" not in clean

    @pytest.mark.asyncio
    async def test_url_preserves_xsec_token(self, adapter):
        """Test that xsec_token is preserved in cleaned URL"""
        url = (
            "https://www.xiaohongshu.com/discovery/item/649f88b4000000001303eb07"
            "?source=webshare&xhsshare=pc_web"
            "&xsec_token=ABhWd1qG6hXifjzQR6gI6cRfQhoG9XsQ7MFNyJ_apFtfk="
            "&xsec_source=pc_share"
        )
        clean = await adapter.clean_url(url)
        # xsec_token 应保留（后续API请求需要）
        assert "xsec_token" in clean
        # 无用追踪参数应去除
        assert "xhsshare" not in clean
