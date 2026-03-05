import pytest
from unittest.mock import AsyncMock, MagicMock, patch
from app.bot.commands import (
    help_command,
    list_tags_command,
    get_command,
    get_tag_command,
    get_twitter_command,
    get_bilibili_command,
    _check_perm,
)
from app.bot.messages import HELP_TEXT_FULL


# --- Helpers ---

def _make_update(user_id=12345, username="testuser"):
    update = MagicMock()
    update.effective_user.id = user_id
    update.effective_user.username = username
    update.message = AsyncMock()
    return update


def _make_context_with_bot_data(http_client=None, api_base="http://localhost:8000", channel_id=None):
    context = MagicMock()
    context.bot_data = {
        "http_client": http_client or AsyncMock(),
        "api_base": api_base,
    }
    if channel_id is not None:
        context.bot_data["channel_id"] = channel_id
    return context


def _perm_patch(allowed=True, reason=None):
    mock_perm = MagicMock()
    mock_perm.check_permission.return_value = (allowed, reason)
    return patch("app.bot.commands.get_permission_manager", return_value=mock_perm)


# --- _check_perm edge cases ---

@pytest.mark.asyncio
async def test_check_perm_no_user():
    update = MagicMock()
    update.effective_user = None
    context = MagicMock()

    result = await _check_perm(update, context)
    assert result is False


@pytest.mark.asyncio
async def test_check_perm_no_perm_manager():
    update = _make_update()
    context = MagicMock()
    context.bot_data = {}

    with patch("app.bot.commands.get_permission_manager", return_value=None):
        result = await _check_perm(update, context)
        assert result is False
        update.message.reply_text.assert_called_once_with("系统错误：权限配置缺失")


# --- help_command ---

@pytest.mark.asyncio
async def test_help_command():
    update = _make_update()
    context = MagicMock()

    with _perm_patch():
        await help_command(update, context)
        update.message.reply_text.assert_called_once()
        assert HELP_TEXT_FULL in update.message.reply_text.call_args[0][0]


# --- list_tags_command ---

@pytest.mark.asyncio
async def test_list_tags_command_success():
    update = _make_update()
    mock_client = AsyncMock()
    mock_client.get.return_value = MagicMock(
        status_code=200,
        json=lambda: [
            {"name": "技术", "count": 10},
            {"name": "生活", "count": 5},
        ],
    )
    context = _make_context_with_bot_data(http_client=mock_client)

    with _perm_patch():
        await list_tags_command(update, context)
        update.message.reply_text.assert_called_once()
        sent_text = update.message.reply_text.call_args[0][0]
        assert "技术" in sent_text
        assert "10" in sent_text
        assert "生活" in sent_text


@pytest.mark.asyncio
async def test_list_tags_command_empty():
    update = _make_update()
    mock_client = AsyncMock()
    mock_client.get.return_value = MagicMock(
        status_code=200,
        json=lambda: [],
    )
    context = _make_context_with_bot_data(http_client=mock_client)

    with _perm_patch():
        await list_tags_command(update, context)
        update.message.reply_text.assert_called_once_with("暂无任何标签")


@pytest.mark.asyncio
async def test_list_tags_command_api_error():
    update = _make_update()
    mock_client = AsyncMock()
    mock_client.get.return_value = MagicMock(status_code=500)
    context = _make_context_with_bot_data(http_client=mock_client)

    with _perm_patch():
        await list_tags_command(update, context)
        update.message.reply_text.assert_called_once_with("无法获取标签列表")


# --- get_tag_command ---

@pytest.mark.asyncio
async def test_get_tag_command_no_args():
    update = _make_update()
    context = MagicMock()
    context.args = None

    await get_tag_command(update, context)
    update.message.reply_text.assert_called_once()
    sent_text = update.message.reply_text.call_args[0][0]
    assert "/get_tag" in sent_text


@pytest.mark.asyncio
async def test_get_tag_command_with_tag():
    update = _make_update()

    mock_client = AsyncMock()
    # GET /bot/chats/{channel_id}
    chat_resp = MagicMock(status_code=200, json=lambda: {"id": "chat-1"})
    # GET /distribution-queue/items
    queue_resp = MagicMock(
        status_code=200,
        json=lambda: {"items": [{"id": "item-1", "content_id": "content-1"}]},
    )
    # GET /contents/{content_id}
    content_resp = MagicMock(
        status_code=200,
        json=lambda: {
            "title": "测试文章",
            "tags": ["技术"],
            "platform": "twitter",
            "url": "https://example.com",
        },
    )
    # POST /distribution-queue/items/{item_id}/push-now
    push_resp = MagicMock(status_code=200)

    mock_client.get.side_effect = [chat_resp, queue_resp, content_resp]
    mock_client.post.return_value = push_resp

    context = _make_context_with_bot_data(http_client=mock_client, channel_id="chan-1")
    context.args = ["技术"]

    with _perm_patch():
        await get_tag_command(update, context)
        update.message.reply_text.assert_called_once()
        sent_text = update.message.reply_text.call_args[0][0]
        assert "测试文章" in sent_text
        assert "已触发推送" in sent_text


@pytest.mark.asyncio
async def test_get_tag_command_no_channel_id():
    update = _make_update()
    mock_client = AsyncMock()
    context = _make_context_with_bot_data(http_client=mock_client)  # no channel_id
    context.args = ["技术"]

    with _perm_patch():
        await get_tag_command(update, context)
        update.message.reply_text.assert_called_once()
        assert "未绑定" in update.message.reply_text.call_args[0][0]


# --- get_command ---

@pytest.mark.asyncio
async def test_get_command_no_args():
    """get_command with no args passes tag=None to _get_content_by_filter"""
    update = _make_update()
    context = MagicMock()
    context.args = []

    with patch("app.bot.commands._get_content_by_filter", new_callable=AsyncMock) as mock_filter:
        await get_command(update, context)
        mock_filter.assert_called_once_with(update, context, tag=None)


@pytest.mark.asyncio
async def test_get_command_with_tag_arg():
    update = _make_update()
    context = MagicMock()
    context.args = ["科技"]

    with patch("app.bot.commands._get_content_by_filter", new_callable=AsyncMock) as mock_filter:
        await get_command(update, context)
        mock_filter.assert_called_once_with(update, context, tag="科技")


# --- get_twitter_command / get_bilibili_command ---

@pytest.mark.asyncio
async def test_get_twitter_command():
    update = _make_update()
    context = MagicMock()

    with patch("app.bot.commands._get_content_by_filter", new_callable=AsyncMock) as mock_filter:
        await get_twitter_command(update, context)
        mock_filter.assert_called_once_with(update, context, platform="twitter")


@pytest.mark.asyncio
async def test_get_bilibili_command():
    update = _make_update()
    context = MagicMock()

    with patch("app.bot.commands._get_content_by_filter", new_callable=AsyncMock) as mock_filter:
        await get_bilibili_command(update, context)
        mock_filter.assert_called_once_with(update, context, platform="bilibili")


# --- _get_content_by_filter: no matching content ---

@pytest.mark.asyncio
async def test_get_content_by_filter_tag_mismatch():
    """All queue items exist but none match the tag filter"""
    update = _make_update()

    mock_client = AsyncMock()
    chat_resp = MagicMock(status_code=200, json=lambda: {"id": "chat-1"})
    queue_resp = MagicMock(
        status_code=200,
        json=lambda: {"items": [{"id": "item-1", "content_id": "content-1"}]},
    )
    content_resp = MagicMock(
        status_code=200,
        json=lambda: {"title": "无关内容", "tags": ["其他"], "platform": "twitter"},
    )
    mock_client.get.side_effect = [chat_resp, queue_resp, content_resp]

    context = _make_context_with_bot_data(http_client=mock_client, channel_id="chan-1")
    context.args = ["不存在的标签"]

    with _perm_patch():
        await get_tag_command(update, context)
        update.message.reply_text.assert_called_once_with("暂无符合条件的内容")


# --- _get_content_by_filter: push failure ---

@pytest.mark.asyncio
async def test_get_content_push_failure():
    update = _make_update()

    mock_client = AsyncMock()
    chat_resp = MagicMock(status_code=200, json=lambda: {"id": "chat-1"})
    queue_resp = MagicMock(
        status_code=200,
        json=lambda: {"items": [{"id": "item-1", "content_id": "content-1"}]},
    )
    content_resp = MagicMock(
        status_code=200,
        json=lambda: {"title": "文章", "tags": ["技术"], "platform": "twitter"},
    )
    push_resp = MagicMock(status_code=500, json=lambda: {"detail": "推送服务异常"})

    mock_client.get.side_effect = [chat_resp, queue_resp, content_resp]
    mock_client.post.return_value = push_resp

    context = _make_context_with_bot_data(http_client=mock_client, channel_id="chan-1")
    context.args = ["技术"]

    with _perm_patch():
        await get_tag_command(update, context)
        sent_text = update.message.reply_text.call_args[0][0]
        assert "触发推送失败" in sent_text
