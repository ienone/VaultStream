"""
Bilibili Adapter Tests (Mocked)
"""
import pytest
import json
import os
import re
import httpx
from unittest.mock import MagicMock
from typing import Dict

from app.adapters.bilibili import BilibiliAdapter
from app.adapters.base import ParsedContent
from app.adapters.errors import RetryableAdapterError, NonRetryableAdapterError, AuthRequiredAdapterError
from tests.test_adapters.base import AdapterTestBase

# Define paths to mock data
MOCK_DATA_DIR = os.path.join(os.path.dirname(__file__), "..", "data", "bilibili")

def load_mock_json(filename):
    with open(os.path.join(MOCK_DATA_DIR, filename), "r", encoding="utf-8") as f:
        return json.load(f)

class TestBilibiliAdapter(AdapterTestBase):
    """Test suite for Bilibili adapter using mocked data"""

    @property
    def platform_name(self) -> str:
        return "bilibili"

    @property
    def adapter_class(self):
        return BilibiliAdapter

    def get_test_urls(self) -> Dict[str, str]:
        return {
            "video": "https://www.bilibili.com/video/BV1GJ411x7h7",
            "article": "https://www.bilibili.com/read/cv12345678",
            "dynamic": "https://www.bilibili.com/opus/1150580721704763430",
            "bangumi": "https://www.bilibili.com/bangumi/play/ss1293",
            "live": "https://live.bilibili.com/923833",
        }

    @pytest.mark.asyncio
    async def test_parse_video_mocked(self, adapter, httpx_mock):
        """Test parsing video with mocked API response"""
        url = self.get_test_urls()["video"]
        mock_data = load_mock_json("video_BV1GJ411x7h7.json")
        
        httpx_mock.add_response(
            url=re.compile(r"https://api\.bilibili\.com/x/web-interface/view\?bvid=BV1GJ411x7h7"),
            json=mock_data
        )

        result = await adapter.parse(url)
        
        assert result.content_type == "video"
        assert result.content_id == "BV1GJ411x7h7"
        assert result.title == "【官方 MV】Never Gonna Give You Up - Rick Astley"
        assert result.author_name == "索尼音乐中国"

    @pytest.mark.asyncio
    async def test_parse_article_mocked(self, adapter, httpx_mock):
        """Test parsing article with mocked API response"""
        cv_id = "44798841"
        url = f"https://www.bilibili.com/read/cv{cv_id}"
        mock_data = load_mock_json(f"article_{cv_id}.json")
        
        httpx_mock.add_response(
            url=re.compile(f"https://api\\.bilibili\\.com/x/article/view\\?id={cv_id}"),
            json=mock_data
        )

        result = await adapter.parse(url)
        
        assert result.content_type == "article"
        assert result.content_id == f"cv{cv_id}"
        assert "分词" in result.title or "Transformers" in result.title
        
    @pytest.mark.asyncio
    async def test_parse_dynamic_mocked(self, adapter, httpx_mock):
        """Test parsing dynamic with mocked API response"""
        dynamic_id = "1176204921796558864"
        url = f"https://www.bilibili.com/opus/{dynamic_id}"
        mock_data = load_mock_json(f"dynamic_{dynamic_id}.json")
        
        # Match either detail or opus/detail
        httpx_mock.add_response(
            url=re.compile(rf"https://api\.bilibili\.com/x/polymer/web-dynamic/v1/(opus/)?detail\?.*id={dynamic_id}.*"),
            json=mock_data
        )

        result = await adapter.parse(url)
        
        assert result.content_type == "dynamic"
        assert result.content_id == dynamic_id

    @pytest.mark.asyncio
    async def test_parse_bangumi_mocked(self, adapter, httpx_mock):
        """Test parsing bangumi with mocked API response"""
        url = self.get_test_urls()["bangumi"]
        mock_data = load_mock_json("bangumi_ss1293.json")
        
        httpx_mock.add_response(
            url=re.compile(r"https://api\.bilibili\.com/pgc/view/web/season\?season_id=1293"),
            json=mock_data
        )

        result = await adapter.parse(url)
        
        assert result.content_type == "bangumi"
        assert result.content_id == "ss1293"
        # The mock data was '幸运星'
        assert "幸运星" in result.title

    @pytest.mark.asyncio
    async def test_parse_live_mocked(self, adapter, httpx_mock):
        """Test parsing live with mocked API response"""
        url = self.get_test_urls()["live"]
        mock_data = load_mock_json("live_923833.json")
        
        httpx_mock.add_response(
            url=re.compile(r"https://api\.live\.bilibili\.com/xlive/web-room/v1/index/getRoomBaseInfo.*"),
            json=mock_data
        )

        result = await adapter.parse(url)
        
        assert result.content_type == "live"
        assert result.content_id == "923833"
        assert result.author_name is not None

    @pytest.mark.asyncio
    async def test_parse_error_404(self, adapter, httpx_mock):
        """Test handling of 404 error from API"""
        url = self.get_test_urls()["video"]
        
        httpx_mock.add_response(
            url=re.compile(r"https://api\.bilibili\.com/x/web-interface/view.*"),
            json={"code": -404, "message": "啥都木有"},
            status_code=200 
        )

        with pytest.raises(NonRetryableAdapterError):
            await adapter.parse(url)

    @pytest.mark.asyncio
    async def test_parse_error_403(self, adapter, httpx_mock):
        """Test handling of 403 error from API"""
        url = self.get_test_urls()["video"]
        
        httpx_mock.add_response(
            url=re.compile(r"https://api\.bilibili\.com/x/web-interface/view.*"),
            json={"code": -403, "message": "权限不足"},
            status_code=200
        )

        with pytest.raises(AuthRequiredAdapterError):
            await adapter.parse(url)

    @pytest.mark.asyncio
    async def test_parse_network_error(self, adapter, httpx_mock):
        """Test handling of network error"""
        url = self.get_test_urls()["video"]
        
        # Use httpx.ConnectError which is a subclass of RequestError
        httpx_mock.add_exception(httpx.ConnectError("Connection timeout", request=MagicMock()))

        with pytest.raises(RetryableAdapterError):
            await adapter.parse(url)

    @pytest.mark.asyncio
    async def test_url_normalization(self, adapter):
        """Test URL cleaning"""
        test_cases = [
            ("https://www.bilibili.com/video/BV1xx411c7XD?p=1",
             "https://www.bilibili.com/video/BV1xx411c7XD?p=1"),
            ("https://www.bilibili.com/video/BV1xx411c7XD?from=search",
             "https://www.bilibili.com/video/BV1xx411c7XD"),
        ]

        for dirty_url, expected_clean in test_cases:
            clean = await adapter.clean_url(dirty_url)
            assert clean == expected_clean
