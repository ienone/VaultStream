"""
Bot 命令处理模块
"""
import json
import time
import httpx
import logging
from dataclasses import dataclass
from typing import Optional
from telegram import (
    Animation,
    Audio,
    Document,
    InlineKeyboardButton,
    InlineKeyboardMarkup,
    PhotoSize,
    Update,
    Video,
    VideoNote,
    Voice,
)
from telegram.error import TelegramError
from telegram.ext import ContextTypes

from app.core.logging import logger
from app.utils.url_utils import extract_urls_from_text
from .messages import HELP_TEXT_START, HELP_TEXT_FULL, MSG_API_ERROR, MSG_TIMEOUT
from .permissions import get_permission_manager

# --- 辅助函数 ---

async def _get_client(context: ContextTypes.DEFAULT_TYPE) -> httpx.AsyncClient:
    """从 context 获取 httpx client"""
    return context.bot_data.get("http_client")

def _get_api_base(context: ContextTypes.DEFAULT_TYPE) -> str:
    """从 context 获取 API base URL"""
    return context.bot_data.get("api_base")

def _get_target_platform(context: ContextTypes.DEFAULT_TYPE) -> str:
    return context.bot_data.get("target_platform")

def _get_api_headers(context: ContextTypes.DEFAULT_TYPE) -> dict:
    token = context.bot_data.get("api_token")
    if token:
        return {"X-API-Token": token}
    return {}

async def _check_perm(update: Update, context: ContextTypes.DEFAULT_TYPE, require_admin: bool = False) -> bool:
    """统一权限检查 helper"""
    user = update.effective_user
    if not user:
        return False
        
    perm_manager = get_permission_manager(context.bot_data)
    if not perm_manager:
        # 如果未配置权限管理器，默认允许？或者拒绝？为了安全默认拒绝
        logger.error("Permission manager not found in bot_data")
        await update.message.reply_text("系统错误：权限配置缺失")
        return False
        
    allowed, reason = perm_manager.check_permission(user.id, require_admin=require_admin)
    if not allowed:
        await update.message.reply_text(reason)
        return False
    return True

# --- 命令处理器 ---

async def start_command(update: Update, context: ContextTypes.DEFAULT_TYPE):
    """处理 /start 命令"""
    user = update.effective_user
    logger.info(f"Bot /start 命令: user={user.username}(ID:{user.id})")
    
    if not await _check_perm(update, context):
        return
    
    await update.message.reply_text(HELP_TEXT_START, parse_mode='HTML')

async def help_command(update: Update, context: ContextTypes.DEFAULT_TYPE):
    """处理 /help 命令"""
    user = update.effective_user
    logger.info(f"Bot /help 命令: user={user.username}(ID:{user.id})")
    
    if not await _check_perm(update, context):
        return
    
    await update.message.reply_text(HELP_TEXT_FULL, parse_mode='HTML')

async def status_command(update: Update, context: ContextTypes.DEFAULT_TYPE):
    """处理 /status 命令"""
    start_time = time.time()
    user = update.effective_user
    logger.info(f"Bot /status 命令: user={user.username}(ID:{user.id})")
    
    if not await _check_perm(update, context):
        return
        
    try:
        client = await _get_client(context)
        api_base = _get_api_base(context)
        
        try:
            api_start = time.time()
            response = await client.get(f"{api_base}/health", timeout=5.0)
            api_time = time.time() - api_start
        except httpx.TimeoutException:
            await update.message.reply_text(MSG_TIMEOUT)
            return
        except httpx.RequestError:
            await update.message.reply_text(MSG_API_ERROR)
            return
        
        if response.status_code != 200:
            await update.message.reply_text(f"服务异常 (状态码: {response.status_code})")
            return
            
        data = response.json()
        status = data.get('status', 'unknown')
        queue_size = data.get('queue_size', '?')
        
        status_icon = "✓" if status == "ok" else "✗"
        
        await update.message.reply_text(
            f"<b>系统状态</b>\n\n"
            f"{status_icon} 状态: {status}\n"
            f"队列任务数: {queue_size}",
            parse_mode='HTML'
        )
        logger.info(f"Bot /status 完成, 耗时={time.time() - start_time:.3f}s")
    except Exception as e:
        logger.exception("处理 /status 命令失败")
        await update.message.reply_text("获取状态失败")

async def list_tags_command(update: Update, context: ContextTypes.DEFAULT_TYPE):
    """处理 /list_tags 命令"""
    user = update.effective_user
    logger.info(f"Bot /list_tags 命令: user={user.username}(ID:{user.id})")
    
    if not await _check_perm(update, context):
        return
        
    try:
        client = await _get_client(context)
        api_base = _get_api_base(context)
        
        response = await client.get(
            f"{api_base}/tags",
            timeout=5.0,
            headers=_get_api_headers(context),
        )
        
        if response.status_code != 200:
            await update.message.reply_text("无法获取标签列表")
            return
        
        tags_data = response.json()
        
        if not tags_data:
            await update.message.reply_text("暂无任何标签")
            return
        
        tag_lines = []
        for tag_item in tags_data[:20]:
            tag_lines.append(f"• {tag_item['name']}: {tag_item['count']}")
        
        message = "<b>可用标签</b>\n\n" + "\n".join(tag_lines)
        if len(tags_data) > 20:
            message += f"\n\n还有 {len(tags_data) - 20} 个标签"
        
        await update.message.reply_text(message, parse_mode='HTML')
        
    except Exception:
        logger.exception("/list_tags 命令失败")
        await update.message.reply_text("获取标签列表失败")

# --- 内容获取相关命令 ---

async def get_command(update: Update, context: ContextTypes.DEFAULT_TYPE):
    """处理 /get 命令"""
    tag = None
    if context.args and len(context.args) > 0:
        tag = context.args[0].strip()
    await _get_content_by_filter(update, context, tag=tag)

async def get_tag_command(update: Update, context: ContextTypes.DEFAULT_TYPE):
    """处理 /get_tag 命令"""
    if not context.args:
        await update.message.reply_text(
            "请指定标签\n\n用法: <code>/get_tag 标签名</code>",
            parse_mode='HTML'
        )
        return
    tag = context.args[0].strip()
    await _get_content_by_filter(update, context, tag=tag)


def _capture_context(update: Update, source_message) -> dict:
    chat = update.effective_chat
    payload = {
        "channel": "telegram_bot",
        "chat_id": str(chat.id) if chat is not None else None,
        "message_id": getattr(source_message, "message_id", None),
        "replied_message": source_message is not update.message,
        "forwarded": getattr(source_message, "forward_origin", None) is not None,
    }
    media_group_id = getattr(source_message, "media_group_id", None)
    if media_group_id is not None:
        payload["media_group_id"] = str(media_group_id)
    return payload


@dataclass(frozen=True)
class _TelegramCaptureAttachment:
    media: object
    filename: str
    mime_type: str
    kind: str


@dataclass
class _BufferedMediaGroup:
    updated_at: float
    messages: dict[int, object]


_MEDIA_GROUP_BUFFER_KEY = "telegram_capture_media_groups"
_MEDIA_GROUP_TTL_SECONDS = 10 * 60
_MEDIA_GROUP_LIMIT = 64


def _capture_attachment(message) -> Optional[_TelegramCaptureAttachment]:
    """Return one file-like Telegram attachment from a command or replied message."""
    message_id = getattr(message, "message_id", None) or "unknown"
    candidates = (
        ("document", Document, "application/octet-stream", ".bin"),
        ("audio", Audio, "audio/mpeg", ".mp3"),
        ("video", Video, "video/mp4", ".mp4"),
        ("voice", Voice, "audio/ogg", ".ogg"),
        ("animation", Animation, "video/mp4", ".mp4"),
        ("video_note", VideoNote, "video/mp4", ".mp4"),
    )
    for attribute, expected_type, default_mime, suffix in candidates:
        media = getattr(message, attribute, None)
        if not isinstance(media, expected_type):
            continue
        filename = (getattr(media, "file_name", None) or "").strip()
        return _TelegramCaptureAttachment(
            media=media,
            filename=filename or f"telegram-{attribute}-{message_id}{suffix}",
            mime_type=getattr(media, "mime_type", None) or default_mime,
            kind=attribute,
        )

    photos = getattr(message, "photo", None)
    if isinstance(photos, (list, tuple)) and photos:
        media = photos[-1]
        if isinstance(media, PhotoSize):
            return _TelegramCaptureAttachment(
                media=media,
                filename=f"telegram-photo-{message_id}.jpg",
                mime_type="image/jpeg",
                kind="photo",
            )
    return None


def _media_group_key(update: Update, message) -> tuple[str, str] | None:
    media_group_id = getattr(message, "media_group_id", None)
    chat = update.effective_chat
    if media_group_id is None or chat is None:
        return None
    return str(chat.id), str(media_group_id)


def _media_group_buffer(context: ContextTypes.DEFAULT_TYPE) -> dict[
    tuple[str, str], _BufferedMediaGroup
]:
    buffer = context.bot_data.setdefault(_MEDIA_GROUP_BUFFER_KEY, {})
    if not isinstance(buffer, dict):
        buffer = {}
        context.bot_data[_MEDIA_GROUP_BUFFER_KEY] = buffer
    return buffer


def _prune_media_group_buffer(
    buffer: dict[tuple[str, str], _BufferedMediaGroup],
    *,
    now: float,
) -> None:
    expired = [
        key
        for key, group in buffer.items()
        if now - group.updated_at > _MEDIA_GROUP_TTL_SECONDS
    ]
    for key in expired:
        buffer.pop(key, None)
    while len(buffer) > _MEDIA_GROUP_LIMIT:
        oldest = min(buffer, key=lambda key: buffer[key].updated_at)
        buffer.pop(oldest, None)


async def remember_media_group_message(
    update: Update,
    context: ContextTypes.DEFAULT_TYPE,
) -> None:
    """Keep recent album message objects without downloading or persisting media."""
    message = update.effective_message
    key = _media_group_key(update, message)
    if key is None or _capture_attachment(message) is None:
        return
    message_id = getattr(message, "message_id", None)
    if not isinstance(message_id, int):
        return

    now = time.monotonic()
    buffer = _media_group_buffer(context)
    _prune_media_group_buffer(buffer, now=now)
    group = buffer.get(key)
    if group is None:
        group = _BufferedMediaGroup(updated_at=now, messages={})
        buffer[key] = group
    group.updated_at = now
    group.messages[message_id] = message
    _prune_media_group_buffer(buffer, now=now)


def _capture_group_attachments(
    update: Update,
    context: ContextTypes.DEFAULT_TYPE,
    source_message,
) -> tuple[
    tuple[str, str] | None,
    list[tuple[object, _TelegramCaptureAttachment]],
]:
    key = _media_group_key(update, source_message)
    messages: dict[int, object] = {}
    source_message_id = getattr(source_message, "message_id", None)
    if isinstance(source_message_id, int):
        messages[source_message_id] = source_message
    if key is not None:
        buffer = _media_group_buffer(context)
        _prune_media_group_buffer(buffer, now=time.monotonic())
        group = buffer.get(key)
        if group is not None:
            messages.update(group.messages)

    attachments = []
    for _, message in sorted(messages.items()):
        attachment = _capture_attachment(message)
        if attachment is not None:
            attachments.append((message, attachment))
    return key, attachments


async def _download_capture_attachment(
    attachment: _TelegramCaptureAttachment,
) -> bytes:
    remote_file = await attachment.media.get_file(
        connect_timeout=10,
        read_timeout=30,
        write_timeout=30,
        pool_timeout=10,
    )
    data = await remote_file.download_as_bytearray(
        connect_timeout=10,
        read_timeout=60,
        write_timeout=60,
        pool_timeout=10,
    )
    return bytes(data)


def _capture_error_message(response) -> str:
    try:
        payload = response.json()
    except Exception:
        return f"HTTP {response.status_code}"
    if not isinstance(payload, dict):
        return f"HTTP {response.status_code}"
    detail = payload.get("detail")
    if isinstance(detail, dict):
        return str(detail.get("detail") or detail.get("error_message") or detail)
    return str(
        payload.get("error_message")
        or detail
        or f"HTTP {response.status_code}"
    )


async def save_command(update: Update, context: ContextTypes.DEFAULT_TYPE):
    """明确保存命令；回复转发消息时保留最小来源上下文。"""
    if not await _check_perm(update, context):
        return

    message = update.message
    if message is None:
        return
    explicit_text = " ".join(context.args or []).strip()
    replied = getattr(message, "reply_to_message", None)
    replied_attachment = _capture_attachment(replied) if replied is not None else None
    if replied_attachment is not None:
        source_message = replied
        attachment = replied_attachment
    else:
        source_message = replied if not explicit_text and replied is not None else message
        attachment = _capture_attachment(source_message)
    text = explicit_text or str(
        getattr(source_message, "text", None)
        or getattr(source_message, "caption", None)
        or ""
    ).strip()
    if not text and attachment is None:
        await message.reply_text(
            "请在 /save 后提供链接或文字，或回复一条带文字、链接或附件的消息。"
        )
        return

    client = await _get_client(context)
    api_base = _get_api_base(context)
    headers = _get_api_headers(context)
    source_context = _capture_context(update, source_message)
    urls = extract_urls_from_text(text)

    try:
        if attachment is not None:
            group_key, grouped_attachments = _capture_group_attachments(
                update,
                context,
                source_message,
            )
            if not grouped_attachments:
                grouped_attachments = [(source_message, attachment)]
            downloaded: list[tuple[_TelegramCaptureAttachment, bytes]] = []
            try:
                for _, grouped_attachment in grouped_attachments:
                    downloaded.append(
                        (
                            grouped_attachment,
                            await _download_capture_attachment(grouped_attachment),
                        )
                    )
            except TelegramError:
                await message.reply_text("附件下载失败，请稍后重试。")
                return
            except Exception:
                logger.exception("Telegram /save 附件下载失败")
                await message.reply_text("附件下载失败，请稍后重试。")
                return

            caption = text
            if source_message is message and not explicit_text and caption.startswith("/save"):
                caption = caption.partition(" ")[2].strip()
            form_data = {
                "source": "telegram_bot",
                "client_context_json": json.dumps(
                    {
                        **source_context,
                        "attachment_type": (
                            "media_group"
                            if len(downloaded) > 1
                            else downloaded[0][0].kind
                        ),
                        **(
                            {
                                "attachment_types": [
                                    item.kind for item, _ in downloaded
                                ],
                                "media_group_message_ids": [
                                    getattr(grouped_message, "message_id", None)
                                    for grouped_message, _ in grouped_attachments
                                ],
                            }
                            if len(downloaded) > 1
                            else {}
                        ),
                    },
                    ensure_ascii=False,
                    separators=(",", ":"),
                ),
            }
            if caption:
                form_data["note"] = caption[:2000]
            response = await client.post(
                f"{api_base}/captures/files",
                files=[
                    (
                        "uploads",
                        (
                            grouped_attachment.filename,
                            file_bytes,
                            grouped_attachment.mime_type,
                        ),
                    )
                    for grouped_attachment, file_bytes in downloaded
                ],
                data=form_data,
                timeout=90.0,
                headers=headers,
            )
            if response.status_code != 200:
                await message.reply_text(
                    f"附件保存失败：{_capture_error_message(response)}"
                )
                return
            payload = response.json()
            if group_key is not None:
                _media_group_buffer(context).pop(group_key, None)
            saved_message = (
                f"✓ 已保存 {len(downloaded)} 个附件：内容 {payload['id']}"
                if len(downloaded) > 1
                else f"✓ 已保存附件：内容 {payload['id']}"
            )
            await message.reply_text(saved_message)
            return

        if urls:
            lines: list[str] = []
            note = text[:2000] if text not in urls else None
            for url in urls:
                response = await client.post(
                    f"{api_base}/shares",
                    json={
                        "url": url,
                        "source": "telegram_bot",
                        "note": note,
                        "client_context": source_context,
                    },
                    timeout=20.0,
                    headers=headers,
                )
                if response.status_code == 200:
                    payload = response.json()
                    lines.append(f"✓ 已保存链接：内容 {payload['id']}")
                    continue
                if response.status_code == 503:
                    detail = response.json().get("detail") or {}
                    content_id = detail.get("content_id") if isinstance(detail, dict) else None
                    lines.append(f"△ 内容 {content_id or '?'} 已保存，解析任务待恢复")
                    continue
                lines.append(f"✗ 保存失败：{_capture_error_message(response)}")
            await message.reply_text("\n".join(lines))
            return

        response = await client.post(
            f"{api_base}/captures/text",
            json={
                "text": text,
                "source": "telegram_bot",
                "client_context": source_context,
            },
            timeout=20.0,
            headers=headers,
        )
        if response.status_code != 200:
            await message.reply_text(f"保存失败：{_capture_error_message(response)}")
            return
        payload = response.json()
        await message.reply_text(f"✓ 已保存文字：内容 {payload['id']}")
    except httpx.TimeoutException:
        await message.reply_text(MSG_TIMEOUT)
    except httpx.RequestError:
        await message.reply_text(MSG_API_ERROR)
    except Exception:
        logger.exception("/save 命令失败")
        await message.reply_text("保存失败，请稍后再试。")


_NATURAL_CAPTURE_PREFIXES = (
    "请帮我保存",
    "请帮我收藏",
    "请帮我存一下",
    "帮我保存",
    "帮我收藏",
    "帮我存一下",
    "保存",
    "收藏",
    "存一下",
)


def _parse_natural_capture_intent(text: str) -> tuple[bool, str]:
    """Recognize an explicit direct-chat save request without guessing intent."""
    normalized = (text or "").strip()
    for prefix in _NATURAL_CAPTURE_PREFIXES:
        if normalized == prefix:
            return True, ""
        remainder = normalized[len(prefix):] if normalized.startswith(prefix) else ""
        if remainder.startswith((" ", "\t", "\n", ":", "：")):
            return True, remainder.lstrip(" \t\n:：").strip()
    return False, ""


async def handle_natural_capture_message(
    update: Update,
    context: ContextTypes.DEFAULT_TYPE,
) -> bool:
    """Route explicit natural-language save intent through the existing command."""
    message = update.message
    chat = update.effective_chat
    if (
        message is None
        or chat is None
        or str(getattr(chat, "type", "")) != "private"
    ):
        return False

    matched, payload = _parse_natural_capture_intent(
        str(getattr(message, "text", None) or "")
    )
    if not matched:
        return False
    if not payload and getattr(message, "reply_to_message", None) is None:
        await message.reply_text(
            "请在保存请求后提供链接或文字，或回复要保存的消息。"
        )
        return True

    original_args = context.args
    context.args = [payload] if payload else []
    try:
        await save_command(update, context)
    finally:
        context.args = original_args
    return True

async def get_twitter_command(update: Update, context: ContextTypes.DEFAULT_TYPE):
    """处理 /get_twitter 命令"""
    await _get_content_by_filter(update, context, platform="twitter")

async def get_bilibili_command(update: Update, context: ContextTypes.DEFAULT_TYPE):
    """处理 /get_bilibili 命令"""
    await _get_content_by_filter(update, context, platform="bilibili")

async def _get_content_by_filter(
    update: Update, 
    context: ContextTypes.DEFAULT_TYPE,
    tag: Optional[str] = None,
    platform: Optional[str] = None
):
    """通用内容获取逻辑"""
    user = update.effective_user
    if not user: return
    
    if not await _check_perm(update, context):
        return

    filter_desc = []
    if tag: filter_desc.append(f"标签={tag}")
    if platform: filter_desc.append(f"平台={platform}")
    
    logger.info(f"Bot 获取内容: user={user.username}(ID:{user.id}) {filter_desc}")
    
    try:
        client = await _get_client(context)
        api_base = _get_api_base(context)
        channel_id = context.bot_data.get("channel_id")

        if not channel_id:
            await update.message.reply_text("当前 BotConfig 未绑定默认频道，请先在 Bot 配置里同步并绑定 BotChat")
            return

        chat_resp = await client.get(
            f"{api_base}/bot/chats",
            params={"chat_id": channel_id},
            timeout=10.0,
            headers=_get_api_headers(context),
        )
        if chat_resp.status_code != 200:
            await update.message.reply_text("未找到当前频道对应的 Bot Chat 配置")
            return
        chat_data = chat_resp.json() or []
        if isinstance(chat_data, dict):
            bot_chat_id = chat_data.get("id")
        else:
            bot_chat_id = chat_data[0].get("id") if chat_data else None
        if not bot_chat_id:
            await update.message.reply_text("Bot Chat 配置缺少 ID")
            return

        queue_resp = await client.get(
            f"{api_base}/distribution-queue/items",
            params={
                "status": "scheduled",
                "bot_chat_id": bot_chat_id,
                "page": 1,
                "size": 50,
            },
            timeout=10.0,
            headers=_get_api_headers(context),
        )
        if queue_resp.status_code != 200:
            await update.message.reply_text("获取队列失败")
            return

        items = (queue_resp.json() or {}).get("items", [])
        if not items:
            await update.message.reply_text("暂无符合条件的内容")
            return

        selected_item = None
        selected_content = None
        for item in items:
            content_id = item.get("content_id")
            if not content_id:
                continue
            detail_resp = await client.get(
                f"{api_base}/contents/{content_id}",
                timeout=10.0,
                headers=_get_api_headers(context),
            )
            if detail_resp.status_code != 200:
                continue
            content = detail_resp.json()
            if tag and tag not in (content.get("tags") or []):
                continue
            if platform and str(content.get("platform", "")).lower() != platform.lower():
                continue
            selected_item = item
            selected_content = content
            break

        if not selected_item or not selected_content:
            await update.message.reply_text("暂无符合条件的内容")
            return

        item_id = selected_item.get("id")
        push_resp = await client.post(
            f"{api_base}/distribution-queue/items/{item_id}/push-now",
            timeout=20.0,
            headers=_get_api_headers(context),
        )
        if push_resp.status_code != 200:
            error_msg = "未知错误"
            try:
                error_msg = push_resp.json().get("detail", "未知错误")
            except Exception:
                pass
            await update.message.reply_text(f"触发推送失败: {error_msg}")
            return

        title = selected_content.get('title') or selected_content.get('url', '未知内容')
        title_short = title[:50] + "..." if len(title) > 50 else title
        platform_name = selected_content.get('platform', '')
        await update.message.reply_text(f"已触发推送: {title_short}\n平台: {platform_name}")
        
    except Exception as e:
        logger.exception("获取内容失败")
        await update.message.reply_text(f"发送失败: {str(e)[:100]}")


def _format_agent_result(tool: str, result: dict) -> str:
    if tool == "search_content":
        items = result.get("items") or []
        if not items:
            return "未找到相关内容。"
        lines = [f"共找到 {len(items)} 条结果："]
        for item in items[:5]:
            cid = item.get("content_id")
            title = item.get("title") or item.get("url") or "无标题"
            score = item.get("score")
            score_text = f" (score={float(score):.3f})" if isinstance(score, (int, float)) else ""
            lines.append(f"- [{cid}] {title}{score_text}")
        return "\n".join(lines)

    if tool == "list_groups":
        groups = result.get("groups") or []
        if not groups:
            return "当前没有可用群组。"
        lines = [f"可用群组 {len(groups)} 个："]
        for group in groups[:8]:
            lines.append(f"- {group.get('title') or group.get('chat_id')} ({group.get('chat_id')})")
        return "\n".join(lines)

    if tool == "import_favorites":
        sync_result = result.get("result") or {}
        status = sync_result.get("status") or "unknown"
        imported = sync_result.get("imported") or 0
        fetched = sync_result.get("fetched") or 0
        return f"收藏同步完成: status={status}, fetched={fetched}, imported={imported}"

    return str(result)


async def ai_command(update: Update, context: ContextTypes.DEFAULT_TYPE):
    """处理 /ai 命令，转发到 Agent Tool 链路。"""
    user = update.effective_user
    if not user:
        return

    if not await _check_perm(update, context):
        return

    prompt = " ".join(context.args or []).strip()
    if not prompt:
        await update.message.reply_text("用法: /ai 你的自然语言指令")
        return

    try:
        client = await _get_client(context)
        api_base = _get_api_base(context)
        payload = {"message": prompt, "session_id": f"tg-{user.id}"}

        response = await client.post(
            f"{api_base}/agent/run",
            json=payload,
            timeout=25.0,
            headers=_get_api_headers(context),
        )
        if response.status_code != 200:
            await update.message.reply_text(f"Agent 调用失败: HTTP {response.status_code}")
            return

        data = response.json()
        confirmation = data.get("confirmation")
        if data.get("confirmation_required") is True and isinstance(
            confirmation, dict
        ):
            confirmation_id = str(confirmation.get("id") or "").strip()
            if not confirmation_id:
                await update.message.reply_text("Agent 返回了无效的确认请求。")
                return
            summary = str(
                confirmation.get("summary") or "Agent 请求执行一项受控操作。"
            ).strip()
            keyboard = InlineKeyboardMarkup(
                [
                    [
                        InlineKeyboardButton(
                            "批准",
                            callback_data=f"agent-confirm:approve:{confirmation_id}",
                        ),
                        InlineKeyboardButton(
                            "拒绝",
                            callback_data=f"agent-confirm:reject:{confirmation_id}",
                        ),
                    ]
                ]
            )
            await update.message.reply_text(
                f"Agent 等待确认\n\n{summary}\n\n该请求也已保存到 VaultStream 消息盒子。",
                reply_markup=keyboard,
            )
            return

        tool = str(data.get("tool") or "").strip()
        message = str(data.get("message") or "").strip()
        if message:
            text = message
        elif tool:
            text = _format_agent_result(tool, data.get("result") or {})
        else:
            text = "Agent 已完成处理，但没有返回可展示的内容。"
        prefix = f"[{tool}]\n" if tool else ""
        await update.message.reply_text(f"{prefix}{text}")
    except Exception as e:
        logger.exception("/ai 命令失败: {}", e)
        await update.message.reply_text("Agent 处理失败，请稍后再试。")
