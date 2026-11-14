"""Bounded source reading without media manifests or unrelated metadata."""
from pydantic import BaseModel, Field, model_validator
from sqlalchemy import select
from app.models import Content
from app.models.media import MediaAsset, MediaType, MediaRole
from app.services.agent.content_evidence import PARSE_ERROR_SCHEMA, content_parse_error
from app.services.agent.tool_registry import AgentToolContext, AgentToolError, AgentToolRegistry
from app.services.media_segments import extract_media_segments

class ReadContentArgs(BaseModel):
    content_id: int = Field(gt=0)
    start_seconds: float | None = Field(default=None, ge=0, allow_inf_nan=False)
    end_seconds: float | None = Field(default=None, gt=0, allow_inf_nan=False)
    offset: int = Field(default=0, ge=0, description='正文字符或筛选后时间片的分页偏移')
    limit: int = Field(default=10, ge=1, le=30, description='时间片每页数量')

    @model_validator(mode='after')
    def validate_interval(self):
        if self.start_seconds is not None and self.end_seconds is not None and self.end_seconds <= self.start_seconds:
            raise ValueError('end_seconds must be greater than start_seconds')
        return self


def register_reading_tool(registry: AgentToolRegistry) -> None:
    registry.register(name='read_content', description=(
        '读取收藏原文或视频字幕。找到视频章节后，用 content_id 与 start_seconds/end_seconds '
        '读取对应时间段的完整字幕。'
        'offset 可继续读取超长正文。返回可点击 route、内容 status，'
        '解析失败时返回原始 parse_error（message/type/at），用于核对实际失败原因。'),
        args_model=ReadContentArgs, result_schema={'type': 'object', 'properties': {
            'status': {'type': ['string', 'null']}, 'parse_error': PARSE_ERROR_SCHEMA}},
        permission_level='read', permissions=['content:read'], handler=read_content)


async def read_content(args: dict, context: AgentToolContext) -> dict:
    content = await context.db.get(Content, args['content_id'])
    if content is None:
        raise AgentToolError(error_code='content_not_found', message='收藏内容不存在', retryable=False)
    evidence = {'status': content.status.value if content.status else None,
                'parse_error': content_parse_error(content)}
    assets = list((await context.db.scalars(select(MediaAsset).where(MediaAsset.content_id == content.id))).all())
    segments = extract_media_segments(content_id=content.id, rich_payload=content.rich_payload, assets=assets)
    start, end = args.get('start_seconds'), args.get('end_seconds')
    selected = [s for s in segments
        if (start is None or (s.end_seconds > start if s.end_seconds is not None else s.start_seconds >= start))
        and (end is None or s.start_seconds < end)]
    offset, limit = args.get('offset', 0), args.get('limit', 10)
    chunks = (content.rich_payload or {}).get('chunks', [])
    page = selected[offset:offset + limit]
    result = {**evidence, 'content_id': content.id, 'title': content.title, 'author': content.author_name,
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
