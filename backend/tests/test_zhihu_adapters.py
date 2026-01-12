import pytest
import os
from app.adapters.zhihu import ZhihuAdapter
from app.config import settings

# Skip if no cookie provided (optional, or just try running it)
# In a real CI env, we would mock the response.
# Here we provide a way to run it if the user has configured the env.

@pytest.mark.asyncio
async def test_detect_content_type():
    adapter = ZhihuAdapter()
    assert await adapter.detect_content_type("https://zhuanlan.zhihu.com/p/123456") == "article"
    assert await adapter.detect_content_type("https://www.zhihu.com/question/123456") == "question"
    assert await adapter.detect_content_type("https://www.zhihu.com/question/123456/answer/7890") == "answer"
    assert await adapter.detect_content_type("https://www.zhihu.com/pin/123456") == "pin"
    assert await adapter.detect_content_type("https://www.zhihu.com/people/someuser") == "user_profile"

@pytest.mark.asyncio
@pytest.mark.skipif(not os.getenv("ZHIHU_COOKIE") and not settings.zhihu_cookie, reason="Need Zhihu Cookie")
async def test_parse_article():
    adapter = ZhihuAdapter()
    url = "https://zhuanlan.zhihu.com/p/1993458822560363213"
    result = await adapter.parse(url)
    assert result.platform == "zhihu"
    assert result.content_type == "article"
    assert result.title is not None
    assert result.content_id in url

@pytest.mark.asyncio
@pytest.mark.skipif(not os.getenv("ZHIHU_COOKIE") and not settings.zhihu_cookie, reason="Need Zhihu Cookie")
async def test_parse_answer():
    adapter = ZhihuAdapter()
    url = "https://www.zhihu.com/answer/1993098398442726640"
    # Note: URL might redirect to /question/.../answer/...
    try:
        result = await adapter.parse(url)
        assert result.platform == "zhihu"
        assert result.content_type == "answer"
        assert result.author_name is not None
    except Exception as e:
        pytest.fail(f"Failed to parse answer: {e}")

@pytest.mark.asyncio
@pytest.mark.skipif(not os.getenv("ZHIHU_COOKIE") and not settings.zhihu_cookie, reason="Need Zhihu Cookie")
async def test_parse_question():
    adapter = ZhihuAdapter()
    url = "https://www.zhihu.com/question/20917550"
    result = await adapter.parse(url)
    assert result.platform == "zhihu"
    assert result.content_type == "question"
    assert result.stats["answer_count"] >= 0

@pytest.mark.asyncio
@pytest.mark.skipif(not os.getenv("ZHIHU_COOKIE") and not settings.zhihu_cookie, reason="Need Zhihu Cookie")
async def test_parse_pin():
    adapter = ZhihuAdapter()
    url = "https://www.zhihu.com/pin/1882078427231803012"
    result = await adapter.parse(url)
    assert result.platform == "zhihu"
    assert result.content_type == "pin"

@pytest.mark.asyncio
@pytest.mark.skipif(not os.getenv("ZHIHU_COOKIE") and not settings.zhihu_cookie, reason="Need Zhihu Cookie")
async def test_parse_people():
    adapter = ZhihuAdapter()
    url = "https://www.zhihu.com/people/tian-yuan-dong"
    result = await adapter.parse(url)
    assert result.platform == "zhihu"
    assert result.content_type == "user_profile"
    assert result.author_name == "田渊栋"
