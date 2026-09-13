"""Extract owned archived PDFs, keeping notes and source-derived pages separate."""

import asyncio
from copy import deepcopy
from dataclasses import dataclass
from pathlib import Path
import sys

from sqlalchemy import delete, select, update
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import selectinload
from sqlalchemy.orm.exc import StaleDataError

from app.adapters.storage import get_storage_backend
from app.core.db_adapter import AsyncSessionLocal
from app.core.events import event_bus
from app.core.time_utils import utcnow
from app.models import Content
from app.models.media import MediaAsset, MediaType, MediaVariant, MediaVariantKind, MediaVariantStatus
from app.models.search import ContentEmbedding
from app.schemas.document import DocumentPageItem, DocumentTextItem
from app.services.background_task_state import record_task_run_started, record_task_run_success, record_task_run_error

_SUCCESS = {"ready", "partial", "no_text"}
_STATUSES = _SUCCESS | {"encrypted", "invalid_pdf", "limit_exceeded", "timeout", "missing", "source_changed", "failed"}
_tasks: set[asyncio.Task] = set()
_extraction_slots = asyncio.Semaphore(2)


def original_pdf(asset: MediaAsset) -> MediaVariant | None:
    if asset.media_type != MediaType.DOCUMENT:
        return None
    return next((v for v in sorted(asset.variants, key=lambda v: v.id, reverse=True)
                 if v.variant_kind == MediaVariantKind.ORIGINAL_ARCHIVE
                 and v.status == MediaVariantStatus.READY
                 and v.mime_type == "application/pdf"), None)


async def document_assets(db: AsyncSession, content_id: int) -> list[MediaAsset]:
    return list((await db.scalars(select(MediaAsset).where(
        MediaAsset.content_id == content_id, MediaAsset.media_type == MediaType.DOCUMENT,
    ).options(selectinload(MediaAsset.variants)).order_by(MediaAsset.position, MediaAsset.id))).all())


def build_document_text_items(content: Content, assets: list[MediaAsset]) -> list[DocumentTextItem]:
    chunks = (content.rich_payload or {}).get("chunks", [])
    if not isinstance(chunks, list):
        chunks = []
    items = []
    for asset in assets:
        if asset.content_id != content.id or (variant := original_pdf(asset)) is None:
            continue
        metadata = asset.asset_metadata or {}
        extraction = metadata.get("document_text", {})
        current = (extraction.get("variant_id") == variant.id
                   and extraction.get("storage_key") == variant.storage_key
                   and extraction.get("variant_checksum") == variant.checksum)
        status = extraction.get("status") if current else "pending"
        if status not in _STATUSES:
            status = "pending"
        page_count = extraction.get("page_count", 0) if current else 0
        if isinstance(page_count, bool) or not isinstance(page_count, int) or not 0 <= page_count <= 500:
            page_count = 0
        pages = []
        seen = set()
        if status in _SUCCESS:
            for index, chunk in enumerate(chunks):
                if not isinstance(chunk, dict):
                    continue
                number = chunk.get("page_number")
                if (chunk.get("source_kind") != "pdf_native_text"
                    or chunk.get("media_asset_id") != asset.id
                    or isinstance(chunk.get("media_asset_id"), bool)
                    or chunk.get("source_variant_id") != variant.id
                    or chunk.get("source_checksum") != extraction.get("checksum")
                    or isinstance(number, bool) or not isinstance(number, int)
                    or not 1 <= number <= page_count or number in seen
                    or not isinstance(chunk.get("content"), str)):
                    continue
                seen.add(number)
                pages.append(DocumentPageItem(chunk_index=index, page_number=number, text=chunk["content"]))
        items.append(DocumentTextItem(
            media_asset_id=asset.id, filename=str(metadata.get("filename") or f"PDF {asset.position + 1}"),
            status=status, page_count=page_count,
            text_page_count=sum(bool(page.text.strip()) for page in pages),
            pages=sorted(pages, key=lambda p: p.page_number),
        ))
    return items


@dataclass(frozen=True)
class PdfSource:
    asset_id: int
    variant_id: int
    storage_key: str
    checksum: str | None
    filename: str


async def extract_source(source: PdfSource) -> dict:
    storage = get_storage_backend()
    local = storage.get_local_path(key=source.storage_key)
    if not local:
        return {"status": "missing"}
    path = Path(local).resolve()
    if not path.is_relative_to(Path(storage.root_dir).resolve()) or not path.is_file():
        return {"status": "missing"}
    async with _extraction_slots:
        process = await asyncio.create_subprocess_exec(
            sys.executable, str(Path(__file__).with_name("pdf_text_worker.py")),
            str(path), source.checksum or "", stdout=asyncio.subprocess.PIPE,
            stderr=asyncio.subprocess.DEVNULL,
        )
        try:
            stdout, _ = await asyncio.wait_for(process.communicate(), timeout=60)
        except (TimeoutError, asyncio.CancelledError) as exc:
            if process.returncode is None:
                process.kill()
            await process.communicate()
            if isinstance(exc, asyncio.CancelledError):
                raise
            return {"status": "timeout"}
    if process.returncode != 0:
        return {"status": "failed"}
    import json
    return json.loads(stdout)


async def extract_content_documents(content_id: int) -> dict:
    # No database transaction is held during CPU/file processing.
    async with AsyncSessionLocal() as db:
        content = await db.get(Content, content_id)
        if content is None:
            raise ValueError("收藏内容不存在")
        revision = content.updated_at
        payload = deepcopy(content.rich_payload or {})
        sources = [PdfSource(a.id, v.id, v.storage_key, v.checksum,
                             str((a.asset_metadata or {}).get("filename") or f"PDF {a.position + 1}"))
                   for a in await document_assets(db, content_id) if (v := original_pdf(a)) is not None]
    if not sources:
        raise ValueError("没有已归档的 PDF 原文件")
    results = [(source, await extract_source(source)) for source in sources]
    async with AsyncSessionLocal() as db:
        guard = await db.execute(update(Content).where(
            Content.id == content_id, Content.updated_at == revision,
        ).values(updated_at=utcnow()).execution_options(synchronize_session=False))
        if guard.rowcount != 1:
            raise StaleDataError("提取期间内容已改变，请重新提取")
        assets = {a.id: a for a in await document_assets(db, content_id)}
        chunks = payload.get("chunks", [])
        chunks = [c for c in chunks if not isinstance(c, dict) or c.get("source_kind") != "pdf_native_text"] if isinstance(chunks, list) else []
        for source, result in results:
            asset = assets.get(source.asset_id)
            current = original_pdf(asset) if asset else None
            if current is None or (current.id, current.storage_key, current.checksum) != (source.variant_id, source.storage_key, source.checksum):
                raise StaleDataError("提取期间原文件已改变，请重新提取")
            metadata = dict(asset.asset_metadata or {})
            metadata["document_text"] = {
                "variant_id": source.variant_id, "storage_key": source.storage_key,
                "variant_checksum": source.checksum, "checksum": result.get("checksum"),
                "status": result["status"], "page_count": result.get("page_count", 0),
            }
            asset.asset_metadata = metadata
            for page in result.get("pages", []):
                chunks.append({
                    "source_kind": "pdf_native_text", "segment_type": "document_page",
                    "media_asset_id": source.asset_id, "source_variant_id": source.variant_id,
                    "source_checksum": result["checksum"], "page_number": page["page_number"],
                    "title": f"{source.filename} · 第 {page['page_number']} 页", "content": page["text"],
                })
        payload["chunks"] = chunks
        await db.execute(update(Content).where(Content.id == content_id).values(rich_payload=payload))
        # Indices from the previous page set must not survive extraction/replacement.
        await db.execute(delete(ContentEmbedding).where(ContentEmbedding.content_id == content_id))
        await db.commit()
    return {
        "content_id": content_id, "document_count": len(results),
        "page_count": sum(r.get("page_count", 0) for _, r in results),
        "text_page_count": sum(r.get("text_page_count", 0) for _, r in results),
        "documents": [{"media_asset_id": s.asset_id, "status": r["status"]} for s, r in results],
    }


async def run_document_extraction(content_id: int, run_id: str, *, source: str) -> None:
    try:
        result = await extract_content_documents(content_id)
        failed = [r for r in result["documents"] if r["status"] not in _SUCCESS]
        if failed:
            await record_task_run_error("document_extract", run_id, "部分 PDF 未能提取正文，请查看文件状态", **result)
        else:
            await record_task_run_success("document_extract", run_id, **result)
        from app.services.post_ingest import PostIngestService
        if result["text_page_count"]:
            async with AsyncSessionLocal() as db:
                content = await db.get(Content, content_id)
                if content is not None:
                    await PostIngestService().generate_summary(db, content)
        await event_bus.publish("content_updated", {"id": content_id})
        PostIngestService().schedule_embedding_index(content_id, source=source)
    except Exception as exc:
        message = str(exc) if isinstance(exc, (ValueError, StaleDataError)) else "PDF 正文提取失败"
        await record_task_run_error("document_extract", run_id, message, content_id=content_id)


async def schedule_document_extraction(content_id: int, *, source: str, trigger: str) -> str:
    run = await record_task_run_started("document_extract", content_id=content_id, source=source, trigger=trigger)
    task = asyncio.create_task(run_document_extraction(content_id, run["run_id"], source=source))
    _tasks.add(task)
    task.add_done_callback(_tasks.discard)
    return run["run_id"]
