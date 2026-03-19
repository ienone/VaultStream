"""
Zhihu adapter integration tests (no local mock files).

This suite reads zhihu cookie from backend/data/vaultstream.db and calls
real Zhihu endpoints through ZhihuAdapter.
"""

from __future__ import annotations

import os
import sqlite3
import warnings
import logging

import pytest
from pydantic import SecretStr

from app.adapters.errors import AuthRequiredAdapterError, RetryableAdapterError
from app.adapters.zhihu import ZhihuAdapter
from app.core.config import settings

logger = logging.getLogger(__name__)


PROD_DB = os.path.abspath(
    os.path.join(os.path.dirname(__file__), "..", "..", "data", "vaultstream.db")
)

ZHIHU_URLS = {
    "question": "https://www.zhihu.com/question/2015217763170399377",
    "answer": "https://www.zhihu.com/question/38699645/answer/2015063270705365482",
    "article": "https://zhuanlan.zhihu.com/p/2015109109989533543",
    "user": "https://www.zhihu.com/people/chris-xia-79",
    "pin": "https://www.zhihu.com/pin/2012347428246930460",
    "collection": "https://www.zhihu.com/collection/454292599",
}


def _read_cookie_from_prod_db(key: str) -> str:
    if not os.path.exists(PROD_DB):
        return ""
    con = None
    try:
        con = sqlite3.connect(PROD_DB)
        cur = con.execute("SELECT value FROM system_settings WHERE key = ?", (key,))
        row = cur.fetchone()
        return row[0] if row and row[0] else ""
    except Exception:
        return ""
    finally:
        if con is not None:
            con.close()


def _has_zhihu_cookie() -> bool:
    try:
        return bool(settings.zhihu_cookie and settings.zhihu_cookie.get_secret_value())
    except Exception:
        return False


def _via_api(result) -> bool:
    meta = result.archive_metadata or {}
    return "raw_api_response" in meta


def _risk_should_fail() -> bool:
    """
    默认将平台风控标记为 xfail（不再误报全绿，也不阻塞整套回归）。
    可通过设置 ZHIHU_RISK_AS_FAILURE=1 升级为硬失败。
    """
    return os.getenv("ZHIHU_RISK_AS_FAILURE", "0") == "1"


def _handle_risk_block(content_type: str, exc: Exception) -> None:
    message = f"知乎 {content_type} 解析触发平台风控: {exc}"
    logger.warning(message)
    warnings.warn(message, UserWarning, stacklevel=2)
    if _risk_should_fail():
        pytest.fail(message)
    pytest.xfail(message)


@pytest.fixture(scope="function", autouse=True)
def inject_zhihu_cookie_from_prod_db():
    cookie = _read_cookie_from_prod_db("zhihu_cookie")
    settings.zhihu_cookie = SecretStr(cookie) if cookie else None


@pytest.fixture
def require_zhihu_cookie():
    if not _has_zhihu_cookie():
        pytest.skip("需要有效 zhihu_cookie（来自 backend/data/vaultstream.db）")


@pytest.fixture
def adapter():
    return ZhihuAdapter()


@pytest.mark.integration
@pytest.mark.asyncio
class TestZhihuAdapter:
    async def test_parse_answer(self, adapter, require_zhihu_cookie):
        result = await adapter.parse(ZHIHU_URLS["answer"])
        assert result.content_type == "answer"
        assert result.content_id == "2015063270705365482"
        assert result.author_name
        assert _via_api(result), "answer 应优先走 API 解析"

    async def test_parse_article(self, adapter, require_zhihu_cookie):
        result = await adapter.parse(ZHIHU_URLS["article"])
        assert result.content_type == "article"
        assert result.content_id == "2015109109989533543"
        assert result.title
        assert result.body

    async def test_parse_user(self, adapter, require_zhihu_cookie):
        try:
            result = await adapter.parse(ZHIHU_URLS["user"])
            assert result.content_type == "user_profile"
            assert result.author_name
            assert result.stats is not None
            assert "answer_count" in result.stats
        except AuthRequiredAdapterError:
            # User page may also be blocked by runtime anti-bot rules.
            return

    async def test_parse_collection(self, adapter, require_zhihu_cookie):
        result = await adapter.parse(ZHIHU_URLS["collection"])
        assert result.content_type == "collection"
        assert result.content_id == "454292599"
        assert result.title

    async def test_parse_question_tolerates_auth_gate(self, adapter, require_zhihu_cookie):
        try:
            result = await adapter.parse(ZHIHU_URLS["question"])
            assert result.content_type == "question"
            assert result.title
        except AuthRequiredAdapterError:
            _handle_risk_block("question", AuthRequiredAdapterError("auth required"))
        except RetryableAdapterError:
            _handle_risk_block("question", RetryableAdapterError("retryable after fingerprint refresh"))

    async def test_parse_pin_tolerates_auth_gate(self, adapter, require_zhihu_cookie):
        try:
            result = await adapter.parse(ZHIHU_URLS["pin"])
            assert result.content_type == "pin"
            assert result.author_name
        except AuthRequiredAdapterError:
            _handle_risk_block("pin", AuthRequiredAdapterError("auth required"))
        except RetryableAdapterError:
            _handle_risk_block("pin", RetryableAdapterError("retryable after fingerprint refresh"))

    async def test_url_normalization(self, adapter):
        test_cases = [
            (
                "https://www.zhihu.com/question/123/answer/456?utm_source=wechat",
                "https://www.zhihu.com/question/123/answer/456",
            ),
            (
                "https://zhuanlan.zhihu.com/p/789?abc=123",
                "https://zhuanlan.zhihu.com/p/789",
            ),
        ]
        for dirty_url, expected_clean in test_cases:
            clean_url = await adapter.clean_url(dirty_url)
            assert clean_url == expected_clean
