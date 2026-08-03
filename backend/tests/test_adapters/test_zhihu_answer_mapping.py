from unittest.mock import AsyncMock

import pytest

from app.adapters.zhihu import ZhihuAdapter


def test_answer_api_requests_and_maps_question_stats():
    adapter = ZhihuAdapter()

    assert "question_answers_meta" in adapter.API_ENDPOINTS
    assert "question_followers_meta" in adapter.API_ENDPOINTS

    parsed = adapter._build_answer_from_api(
        {
            "id": 456,
            "question": {
                "id": 123,
                "title": "为什么这样设计？",
                "answer_count": 42,
                "follower_count": 7,
                "visit_count": 9000,
            },
            "author": {
                "id": "author-id",
                "url_token": "author-token",
                "name": "测试作者",
                "avatar_url": "https://example.test/avatar.jpg",
            },
            "content": "<p>回答正文</p>",
            "voteup_count": 8,
            "comment_count": 3,
        },
        "https://www.zhihu.com/question/123/answer/456",
    )

    assert parsed.context_data == {
        "type": "question",
        "title": "为什么这样设计？",
        "url": "https://www.zhihu.com/question/123",
        "id": "123",
        "stats": {
            "answer_count": 42,
            "follower_count": 7,
            "visit_count": 9000,
        },
    }


@pytest.mark.asyncio
async def test_answer_question_stats_use_paging_totals():
    adapter = ZhihuAdapter()
    adapter._api_request = AsyncMock(
        side_effect=[
            {"paging": {"totals": 42}, "data": [{}]},
            {"paging": {"totals": 7}, "data": [{}]},
        ]
    )
    data = {"question": {"id": 123, "title": "为什么这样设计？"}}

    await adapter._enrich_answer_question_stats(data)

    assert data["question"]["answer_count"] == 42
    assert data["question"]["follower_count"] == 7
