"""Grounded QQ materials, kept out of model-generated network requests."""
from __future__ import annotations

import hashlib
import json
import re
from urllib.parse import urlsplit

import httpx
from sqlalchemy import select

from app.models import AgentToolCall, ContentSource

from app.core.config import settings
from app.core.safe_fetch import create_safe_async_transport, safe_client_get
from app.schemas.qq_agent import QQAgentRequest, QQMessageMaterial
from app.services.agent.tool_registry import AgentToolError
from app.services.content_service import CaptureFileInput


def material_sources(material: QQMessageMaterial, *, scope: str) -> dict[str, dict]:
    prefix = hashlib.sha256(f"{scope}:{material.message_id}".encode()).hexdigest()[:16]
    common = {"message_id": material.message_id, "scope": scope}
    sources = {}
    if material.text.strip():
        sources[f"{prefix}:text"] = {**common, "kind": "text", "text": material.text}
    for index, url in enumerate(material.links, 1):
        sources[f"{prefix}:link:{index}"] = {**common, "kind": "link", "index": index, "url": url}
    for index, attachment in enumerate(material.attachments, 1):
        sources[f"{prefix}:file:{index}"] = {**common, "kind": "file", "index": index, **attachment.model_dump()}
    return sources


def request_sources(request: QQAgentRequest) -> dict[str, dict]:
    sources = material_sources(request, scope="current")
    if request.quote:
        sources.update(material_sources(request.quote, scope="quote"))
    for index, material in enumerate(request.forwarded, 1):
        sources.update(material_sources(material, scope=f"forward:{index}"))
    return sources


def model_materials(sources: dict[str, dict]) -> list[dict]:
    # Download URLs may carry temporary QQ credentials; the model only needs refs.
    return [
        {"source_ref": ref, **{key: value for key, value in source.items()
         if key not in {"mime_type"} and not (source["kind"] == "file" and key == "url")}}
        for ref, source in sources.items()
    ]


def resolve_capture_source(args: dict, sources: dict[str, dict]) -> dict:
    source = sources.get(args.get("source_ref"))
    if not source or args.get("url") or args.get("text"):
        raise AgentToolError(error_code="qq_capture_source_required", message="只能保存当前 QQ 会话中存在的材料引用，不能自行构造链接或正文。", retryable=True)
    resolved = dict(source)
    selection = args.get("text_selection")
    if selection is not None:
        if source["kind"] != "text" or not selection.strip() or selection not in source["text"]:
            raise AgentToolError(error_code="qq_capture_selection_invalid", message="选取的文字必须是对应消息原文中连续的一段。", retryable=True)
        resolved["text"] = selection
    if source["kind"] != "text" and args.get("title"):
        raise AgentToolError(error_code="qq_capture_title_invalid", message="链接或附件的标题来自原内容，不能指定文字标题。", retryable=True)
    return resolved


async def fetch_attachment(source: dict) -> CaptureFileInput:
    parsed = urlsplit(source["url"])
    host = (parsed.hostname or "").lower()
    # NapCat's real QQ downloads use these CDN domains. No arbitrary URLs, local
    # NapCat files, redirects, or credentials are accepted as attachment sources.
    allowed = ("qq.com", "qq.com.cn", "qpic.cn", "gtimg.cn", "gtimg.com")
    if (parsed.scheme not in {"http", "https"} or parsed.username or parsed.password
            or parsed.port not in {None, 80, 443}
            or not any(host == domain or host.endswith("." + domain) for domain in allowed)):
        raise AgentToolError(error_code="qq_attachment_url_rejected", message="附件地址不是支持的 QQ 下载地址，请重新发送原文件。")
    try:
        async with httpx.AsyncClient(transport=create_safe_async_transport(), timeout=45, trust_env=False) as client:
            response = await safe_client_get(client, source["url"], max_redirects=0,
                                             max_bytes=max(1, min(settings.capture_upload_max_bytes, 32 * 1024 * 1024)))
        if response.status_code != 200:
            raise AgentToolError(error_code="qq_attachment_download_failed", message=f"QQ 附件下载失败（HTTP {response.status_code}），请重新发送原文件。")
    except AgentToolError:
        raise
    except Exception as exc:
        raise AgentToolError(error_code="qq_attachment_download_failed", message="QQ 附件下载失败或文件超过上传限制，请重新发送原文件。") from exc

    async def chunks():
        yield response.content

    return CaptureFileInput(chunks=chunks(), filename=source["filename"],
                            mime_type=source.get("mime_type") or response.headers.get("content-type"))


# Validate a claimed result, never infer whether the user's input requests a save.
_CAPTURE_COMPLETION = re.compile(r"^\s*(?:已(?:经)?(?:帮你)?(?:保存|收藏|收录)|(?:保存|收藏|收录)(?:成功|完成|好了))")
_COLLECTION_ROUTE = re.compile(r"/collection/[0-9]+")


async def unverified_completion(db, run_id: str, message: str) -> str | None:
    saved = (await db.execute(select(ContentSource.content_id).where(
        ContentSource.source == "qq_bot",
        ContentSource.client_context["run_id"].as_string() == run_id,
    ))).scalars().all()
    results = (await db.execute(select(AgentToolCall.result).where(
        AgentToolCall.run_id == run_id, AgentToolCall.status == "completed",
    ))).scalars().all()
    # Only a direct affirmative opening with no execution evidence. Negated
    # outcomes, quoted source text and a fresh read of historical captures must
    # remain valid answers; this is not a classifier for the user's intent.
    if _CAPTURE_COMPLETION.search(message) and not saved and not results:
        return "本轮没有收藏或读取结果，但回答直接声称已保存；需真实保存或核实历史事实。"
    claimed_routes = set(_COLLECTION_ROUTE.findall(message))
    if not claimed_routes:
        return None
    observed_routes = {f"/collection/{content_id}" for content_id in saved}
    for result in results:
        observed_routes.update(_COLLECTION_ROUTE.findall(json.dumps(result, ensure_ascii=False)))
    if claimed_routes - observed_routes:
        return "回答引用了本轮工具结果中不存在的收藏链接，不能猜测或递增收藏 ID。"
    return None
