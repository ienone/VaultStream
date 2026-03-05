import pytest
from unittest.mock import AsyncMock, MagicMock, patch
from telegram import Update, CallbackQuery, User, Message
from app.bot.callbacks import button_callback

@pytest.fixture
def mock_context():
    context = MagicMock()
    context.bot_data = {
        "api_base": "http://api:8000",
        "http_client": AsyncMock(),
    }
    return context

@pytest.fixture
def mock_update():
    update = MagicMock(spec=Update)
    query = MagicMock(spec=CallbackQuery)
    user = MagicMock(spec=User)
    user.id = 12345
    user.username = "testuser"
    
    query.data = "delete_123"
    query.answer = AsyncMock()
    query.edit_message_text = AsyncMock()
    
    update.callback_query = query
    update.effective_user = user
    return update

@pytest.mark.asyncio
async def test_button_callback_permission_denied(mock_update, mock_context):
    """Test when user has no permission."""
    perm_manager = MagicMock()
    perm_manager.check_permission.return_value = (False, "无权操作")
    
    with patch("app.bot.callbacks.get_permission_manager", return_value=perm_manager):
        await button_callback(mock_update, mock_context)
        
        mock_update.callback_query.answer.assert_called_once()
        mock_update.callback_query.edit_message_text.assert_called_with("无权操作")

@pytest.mark.asyncio
async def test_button_callback_delete_success(mock_update, mock_context):
    """Test successful delete action."""
    perm_manager = MagicMock()
    perm_manager.check_permission.return_value = (True, "OK")
    
    # Mock HTTP 200 response
    mock_response = MagicMock()
    mock_response.status_code = 200
    mock_context.bot_data["http_client"].delete.return_value = mock_response
    
    # Mock message reply chain for cleanup testing
    reply_to = MagicMock(spec=Message)
    reply_to.delete = AsyncMock()
    mock_update.callback_query.message.reply_to_message = reply_to

    with patch("app.bot.callbacks.get_permission_manager", return_value=perm_manager):
        await button_callback(mock_update, mock_context)
        
        # Verify API call
        mock_context.bot_data["http_client"].delete.assert_called_with(
            "http://api:8000/contents/123", timeout=5.0
        )
        
        # Verify Bot response
        mock_update.callback_query.edit_message_text.assert_any_call(
            "✓ 内容 123 已删除", reply_markup=None
        )
        
        # Verify original message cleanup
        reply_to.delete.assert_called_once()

@pytest.mark.asyncio
async def test_button_callback_delete_failure(mock_update, mock_context):
    """Test backend failure (500)."""
    perm_manager = MagicMock()
    perm_manager.check_permission.return_value = (True, "OK")
    
    # Mock HTTP 500 response
    mock_response = MagicMock()
    mock_response.status_code = 500
    mock_context.bot_data["http_client"].delete.return_value = mock_response

    with patch("app.bot.callbacks.get_permission_manager", return_value=perm_manager):
        await button_callback(mock_update, mock_context)
        
        mock_update.callback_query.edit_message_text.assert_called_with("删除失败: 500")

@pytest.mark.asyncio
async def test_button_callback_invalid_data(mock_update, mock_context):
    """Test malformed callback data."""
    perm_manager = MagicMock()
    perm_manager.check_permission.return_value = (True, "OK")
    mock_update.callback_query.data = "invaliddata"

    with patch("app.bot.callbacks.get_permission_manager", return_value=perm_manager):
        await button_callback(mock_update, mock_context)
        mock_update.callback_query.edit_message_text.assert_called_with("无效的操作")
