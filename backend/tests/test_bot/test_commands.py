import pytest
from unittest.mock import AsyncMock, MagicMock, patch
from app.bot.commands import start_command, help_command, status_command, ai_command
import httpx

@pytest.mark.asyncio
async def test_start_command_allowed():
    update = MagicMock()
    update.effective_user.id = 12345
    update.effective_user.username = "testuser"
    update.message = AsyncMock()
    
    context = MagicMock()
    
    mock_perm = MagicMock()
    mock_perm.check_permission.return_value = (True, None)
    
    with patch("app.bot.commands.get_permission_manager", return_value=mock_perm):
        await start_command(update, context)
        update.message.reply_text.assert_called_once()
        assert "VaultStream" in update.message.reply_text.call_args[0][0]

@pytest.mark.asyncio
async def test_status_command_success():
    update = MagicMock()
    update.effective_user.id = 12345
    update.message = AsyncMock()
    
    context = MagicMock()
    mock_client = AsyncMock()
    mock_client.get.return_value = MagicMock(
        status_code=200, 
        json=lambda: {"status": "ok", "queue_size": 5, "version": "1.0"}
    )
    context.bot_data = {
        "http_client": mock_client,
        "api_base": "http://localhost:8000"
    }
    
    mock_perm = MagicMock()
    mock_perm.check_permission.return_value = (True, None)
    
    with patch("app.bot.commands.get_permission_manager", return_value=mock_perm):
        await status_command(update, context)
        update.message.reply_text.assert_called_once()
        sent_text = update.message.reply_text.call_args[0][0]
        assert "状态" in sent_text
        assert "ok" in sent_text
        assert "5" in sent_text

@pytest.mark.asyncio
async def test_command_denied():
    update = MagicMock()
    update.effective_user.id = 999
    update.message = AsyncMock()
    
    context = MagicMock()
    
    mock_perm = MagicMock()
    mock_perm.check_permission.return_value = (False, "无权访问")
    
    with patch("app.bot.commands.get_permission_manager", return_value=mock_perm):
        await start_command(update, context)
        update.message.reply_text.assert_called_once_with("无权访问")


@pytest.mark.asyncio
async def test_ai_command_success():
    update = MagicMock()
    update.effective_user.id = 12345
    update.message = AsyncMock()

    context = MagicMock()
    context.args = ["请", "同步", "知乎收藏"]
    mock_client = AsyncMock()
    mock_client.post.return_value = MagicMock(
        status_code=200,
        json=lambda: {
            "tool": "import_favorites",
            "result": {"result": {"status": "success", "fetched": 3, "imported": 2}},
        },
    )
    context.bot_data = {
        "http_client": mock_client,
        "api_base": "http://localhost:8000/api/v1",
        "api_token": "abc-token",
    }

    mock_perm = MagicMock()
    mock_perm.check_permission.return_value = (True, None)

    with patch("app.bot.commands.get_permission_manager", return_value=mock_perm):
        await ai_command(update, context)

    update.message.reply_text.assert_called_once()
    reply = update.message.reply_text.call_args[0][0]
    assert "import_favorites" in reply

    kwargs = mock_client.post.call_args.kwargs
    assert kwargs["headers"]["X-API-Token"] == "abc-token"


@pytest.mark.asyncio
async def test_ai_command_without_prompt():
    update = MagicMock()
    update.effective_user.id = 12345
    update.message = AsyncMock()

    context = MagicMock()
    context.args = []
    context.bot_data = {"http_client": AsyncMock(), "api_base": "http://localhost:8000/api/v1"}

    mock_perm = MagicMock()
    mock_perm.check_permission.return_value = (True, None)

    with patch("app.bot.commands.get_permission_manager", return_value=mock_perm):
        await ai_command(update, context)

    update.message.reply_text.assert_called_once()
    assert "用法" in update.message.reply_text.call_args[0][0]
