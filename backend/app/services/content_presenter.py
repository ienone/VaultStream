"""
内容展示计算服务 - 将业务计算逻辑从 ORM 模型中剥离

原则：ORM 模型只负责数据存储映射，展示/计算逻辑由本模块提供。
"""
from app.media.references import rewrite_media_urls
from app.schemas.content import ContentDetail
from app.schemas.media import MediaPurpose
from app.services.media_manifest import load_content_media_assets, build_media_manifest
from app.services.media_segments import build_media_segment_items

# 平台/内容类型 → gallery 的推断规则（DB 中 layout_type 为 NULL 时的运行时兜底）
_GALLERY_PLATFORMS = frozenset({'twitter', 'weibo', 'xiaohongshu', 'douyin'})
_GALLERY_CONTENT_TYPES = frozenset({'video', 'dynamic', 'bangumi', 'live', 'tweet', 'note', 'status'})


def compute_effective_layout_type(content) -> str:
    """获取有效布局类型：用户覆盖 > 系统检测 > 按平台/内容类型推断，默认 'article'。"""
    if content.layout_type_override:
        return content.layout_type_override.value
    if content.layout_type:
        return content.layout_type.value
    # 运行时兜底：m25 迁移后正常情况下不会走到此处
    platform = content.platform.lower() if content.platform else None
    content_type = getattr(content, 'content_type', None)
    content_type = content_type.lower() if content_type else None
    if platform in _GALLERY_PLATFORMS:
        return 'gallery'
    if content_type in _GALLERY_CONTENT_TYPES:
        return 'gallery'
    return 'article'


def compute_display_title(content, max_len: int = 60, fallback: str = "无标题") -> str:
    """获取显示用标题：优先使用 title，否则从 body 生成"""
    from app.adapters.utils import ensure_title
    return ensure_title(content.title, content.body, max_len=max_len, fallback=fallback)


async def build_content_detail(session, content, base_url: str) -> ContentDetail:
    """Resolve stored references once, from asset records to response sources."""
    detail = ContentDetail.model_validate(content)
    detail.media_assets = []
    detail.effective_layout_type = compute_effective_layout_type(detail)
    assets = (await load_content_media_assets(
        session, [content.id], purpose=MediaPurpose.DETAIL,
    ))[content.id]
    mapping = {}
    for asset in assets:
        manifest = build_media_manifest(asset, purpose=MediaPurpose.DETAIL, base_url=base_url)
        detail.media_assets.append(manifest)
        if manifest.sources:
            preferred = manifest.sources[0].url
            if asset.original_url:
                mapping[asset.original_url] = preferred
            for variant in asset.variants:
                mapping[f"local://{variant.storage_key}"] = preferred

    def bind(value):
        if isinstance(value, str):
            return rewrite_media_urls(value, mapping)
        if isinstance(value, list):
            return [bind(item) for item in value]
        if isinstance(value, dict):
            return {key: bind(item) for key, item in value.items()}
        return value

    for field in ("body", "cover_url", "author_avatar_url", "media_urls", "rich_payload", "context_data"):
        setattr(detail, field, bind(getattr(detail, field)))
    detail.media_segments = build_media_segment_items(
        content_id=content.id, rich_payload=content.rich_payload, assets=detail.media_assets,
    )
    return detail
