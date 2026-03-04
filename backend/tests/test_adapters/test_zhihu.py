"""
Zhihu Adapter Tests (Mocked)
"""
import pytest
import json
import os
import re
from typing import Dict

from app.adapters.zhihu import ZhihuAdapter
from app.adapters.base import ParsedContent
from app.adapters.errors import RetryableAdapterError, NonRetryableAdapterError, AuthRequiredAdapterError
from tests.test_adapters.base import AdapterTestBase

# Define paths to mock data
MOCK_DATA_DIR = os.path.join(os.path.dirname(__file__), "..", "data", "zhihu")

def load_mock_json(filename):
    with open(os.path.join(MOCK_DATA_DIR, filename), "r", encoding="utf-8") as f:
        return json.load(f)

def load_mock_html(filename):
    with open(os.path.join(MOCK_DATA_DIR, filename), "r", encoding="utf-8") as f:
        return f.read()

class TestZhihuAdapter(AdapterTestBase):
    """Test suite for Zhihu adapter using mocked data"""

    @property
    def platform_name(self) -> str:
        return "zhihu"

    @property
    def adapter_class(self):
        return ZhihuAdapter

    def get_test_urls(self) -> Dict[str, str]:
        return {
            "answer": "https://www.zhihu.com/question/2011804582406267252/answer/2012482281965631134",
            "question": "https://www.zhihu.com/question/2011804582406267252",
            "article": "https://zhuanlan.zhihu.com/p/2012270020915389042",
            "pin": "https://www.zhihu.com/pin/2005983535018820072",
            "people": "https://www.zhihu.com/people/deephub",
            "collection": "https://www.zhihu.com/collection/454292599",
        }

    @pytest.mark.asyncio
    async def test_parse_answer_mocked_api(self, adapter, httpx_mock):
        """Test parsing answer via API (mocked)"""
        url = self.get_test_urls()["answer"]
        answer_id = "2012482281965631134"
        mock_data = load_mock_json(f"answer_api_{answer_id}.json")
        
        httpx_mock.add_response(
            url=re.compile(rf".*zhihu\.com/api/v4/answers/{answer_id}.*"),
            json=mock_data
        )

        result = await adapter.parse(url)
        
        assert result.content_type == "answer"
        assert result.content_id == answer_id
        assert result.author_name is not None

    @pytest.mark.asyncio
    async def test_parse_question_mocked_html(self, adapter, httpx_mock):
        """Test parsing question via HTML (mocked)"""
        url = self.get_test_urls()["question"]
        question_id = "2011804582406267252"
        mock_html = load_mock_html(f"question_{question_id}.html")
        
        httpx_mock.add_response(
            url=url,
            text=mock_html
        )

        result = await adapter.parse(url)
        
        assert result.content_type == "question"
        assert result.content_id == question_id
        assert "Rubbish" in result.title

    @pytest.mark.asyncio
    async def test_parse_article_mocked_html(self, adapter, httpx_mock):
        """Test parsing article via HTML (mocked)"""
        url = self.get_test_urls()["article"]
        article_id = "2012270020915389042"
        mock_html = load_mock_html(f"article_{article_id}.html")
        
        httpx_mock.add_response(
            url=url,
            text=mock_html
        )

        result = await adapter.parse(url)
        
        assert result.content_type == "article"
        assert result.content_id == article_id

    @pytest.mark.asyncio
    async def test_parse_pin_mocked(self, adapter, httpx_mock):
        """Test parsing pin via HTML (mocked)"""
        url = self.get_test_urls()["pin"]
        pin_id = "2005983535018820072"
        mock_html = load_mock_html(f"pin_{pin_id}.html")
        
        httpx_mock.add_response(
            url=url,
            text=mock_html
        )

        result = await adapter.parse(url)
        
        assert result.content_type == "pin"
        assert result.content_id == pin_id
        assert result.author_name is not None

    @pytest.mark.asyncio
    async def test_parse_people_mocked(self, adapter, httpx_mock):
        """Test parsing user profile via API (mocked)"""
        url = self.get_test_urls()["people"]
        user_id = "deephub"
        mock_data = load_mock_json(f"people_{user_id}.json")
        
        httpx_mock.add_response(
            url=re.compile(rf".*zhihu\.com/api/v4/members/{user_id}.*"),
            json=mock_data
        )

        result = await adapter.parse(url)
        
        assert result.content_type == "user_profile"
        assert result.content_id == "f7e39864b396951a9ea654a88af161cb"
        assert "deephub" in result.author_name

    @pytest.mark.asyncio
    async def test_parse_collection_mocked(self, adapter, httpx_mock):
        """Test parsing collection via API (mocked)"""
        url = self.get_test_urls()["collection"]
        col_id = "454292599"
        mock_data = load_mock_json(f"collection_{col_id}.json")
        
        httpx_mock.add_response(
            url=re.compile(rf".*zhihu\.com/collections/{col_id}.*"),
            json=mock_data
        )

        result = await adapter.parse(url)
        
        assert result.content_type == "collection"
        assert result.content_id == col_id
        assert result.title is not None

    @pytest.mark.asyncio
    async def test_parse_error_api_fail_html_fallback(self, adapter, httpx_mock):
        """Test API failure leads to HTML fallback (if possible)"""
        url = self.get_test_urls()["answer"]
        answer_id = "2012482281965631134"
        mock_html = load_mock_html(f"answer_{answer_id}.html")
        
        # API returns error - adapter will try twice (with and without cookies)
        api_matcher = re.compile(rf".*zhihu\.com/api/v4/answers/{answer_id}.*")
        httpx_mock.add_response(url=api_matcher, status_code=403)
        httpx_mock.add_response(url=api_matcher, status_code=403)
        
        # HTML returns success
        httpx_mock.add_response(
            url=url,
            text=mock_html
        )

        result = await adapter.parse(url)
        assert result.content_type == "answer"
        assert result.content_id == answer_id

    @pytest.mark.asyncio
    async def test_url_normalization(self, adapter):
        """Test URL cleaning"""
        test_cases = [
            ("https://www.zhihu.com/question/123/answer/456?utm_source=wechat",
             "https://www.zhihu.com/question/123/answer/456"),
            ("https://zhuanlan.zhihu.com/p/789?abc=123",
             "https://zhuanlan.zhihu.com/p/789"),
        ]

        for dirty_url, expected_clean in test_cases:
            clean = await adapter.clean_url(dirty_url)
            assert clean == expected_clean
