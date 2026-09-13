"""Bounded source reading without media manifests or unrelated metadata."""
from pydantic import BaseModel, Field, model_validator
from sqlalchemy import select
from app.models import Content
from app.models.media import MediaAsset, MediaType, MediaRole
from app.services.agent.tool_registry import AgentToolContext, AgentToolError, AgentToolRegistry
from app.services.media_segments import extract_media_segments
from app.services.document_text import build_document_text_items, document_assets

class ReadContentArgs(BaseModel):
    content_id: int = Field(gt=0)
    start_seconds: float | None = Field(default=None, ge=0, allow_inf_nan=False)
    end_seconds: float | None = Field(default=None, gt=0, allow_inf_nan=False)
    document_asset_id: int | None = Field(default=None, gt=0)
    page_number: int | None = Field(default=None, gt=0)
    offset: int = Field(default=0, ge=0, description='正文字符或筛选后时间片的分页偏移')
    limit: int = Field(default=10, ge=1, le=30, description='时间片每页数量')

    @model_validator(mode='after')
    def validate_interval(self):
        if self.start_seconds is not None and self.end_seconds is not None and self.end_seconds <= self.start_seconds:
            raise ValueError('end_seconds must be greater than start_seconds')
        if (self.document_asset_id is None) != (self.page_number is None):
            raise ValueError('document_asset_id and page_number must be provided together')
        if self.document_asset_id is not None and (self.start_seconds is not None or self.end_seconds is not None):
            raise ValueError('document pages and media time ranges cannot be read together')
        return self


def register_reading_tool(registry: AgentToolRegistry) -> None:
    registry.register(name='read_content', description=(
        '读取收藏原文或视频字幕。找到视频章节后，用 content_id 与 start_seconds/end_seconds '
        '读取对应时间段的完整字幕，不要反复搜索章节标题。PDF 使用 document_asset_id 与 page_number '
        '读取指定文件的原生文本页；offset 可继续读取超长页。返回可点击 route。'),
        args_model=ReadContentArgs, result_schema={'type': 'object'},
        permission_level='read', permissions=['content:read'], handler=read_content)


async def read_content(args: dict, context: AgentToolContext) -> dict:
    content = await context.db.get(Content, args['content_id'])
    if content is None:
        raise AgentToolError(error_code='content_not_found', message='收藏内容不存在', retryable=False)
    documents = build_document_text_items(content, await document_assets(context.db, content.id))
    if args.get('document_asset_id') is not None:
        document = next((d for d in documents if d.media_asset_id == args['document_asset_id']), None)
        page = next((p for p in document.pages if p.page_number == args.get('page_number')), None) if document else None
        if page is None:
            raise AgentToolError(error_code='document_page_not_found', message='该文件页不存在或尚未提取正文', retryable=False)
        offset = args.get('offset', 0)
        return {'content_id': content.id, 'document_asset_id': document.media_asset_id,
                'page_number': page.page_number, 'filename': document.filename,
                'source_kind': 'pdf_native_text', 'text': page.text[offset:offset + 12000],
                'next_offset': offset + 12000 if offset + 12000 < len(page.text) else None,
                'route': f'/collection/{content.id}?document_asset={document.media_asset_id}&page={page.page_number}'}
    assets = list((await context.db.scalars(select(MediaAsset).where(MediaAsset.content_id == content.id))).all())
    segments = extract_media_segments(content_id=content.id, rich_payload=content.rich_payload, assets=assets)
    start, end = args.get('start_seconds'), args.get('end_seconds')
    selected = [s for s in segments
        if (start is None or (s.end_seconds > start if s.end_seconds is not None else s.start_seconds >= start))
        and (end is None or s.start_seconds < end)]
    offset, limit = args.get('offset', 0), args.get('limit', 10)
    chunks = (content.rich_payload or {}).get('chunks', [])
    page = selected[offset:offset + limit]
    result = {'content_id': content.id, 'title': content.title, 'author': content.author_name,
        'documents': [{'document_asset_id': d.media_asset_id, 'filename': d.filename,
                       'status': d.status, 'page_count': d.page_count, 'text_page_count': d.text_page_count} for d in documents],
        'route': f'/collection/{content.id}', 'source_kind': 'stored_original', 'segments': [
            {'segment_type': s.segment_type, 'media_asset_id': s.media_asset_id,
             'start_seconds': s.start_seconds, 'end_seconds': s.end_seconds,
             'text': str(chunks[s.chunk_index].get('content') or '')[:12000],
             'text_truncated': len(str(chunks[s.chunk_index].get('content') or '')) > 12000,
             'title': s.title, 'generated': bool(chunks[s.chunk_index].get('generated')),
             'route': f'/collection/{content.id}?t={s.start_seconds:g}&media_asset={s.media_asset_id}'} for s in page],
        'next_segment_offset': offset + limit if offset + limit < len(selected) else None}
    if start is None and end is None:
        images = sorted((a for a in assets if a.media_type == MediaType.IMAGE and a.role != MediaRole.AVATAR),
                        key=lambda a: (a.role != MediaRole.COVER, a.position, a.id))
        result['images'] = [{'media_asset_id': a.id, 'role': a.role.value,
                             'position': a.position, 'caption': a.caption, 'alt_text': a.alt_text}
                            for a in images[:100]]
        result['images_truncated'] = len(images) > 100
        body = content.body or ''
        result['body'] = body[offset:offset + 12000]
        result['next_body_offset'] = offset + 12000 if offset + 12000 < len(body) else None
    return result
