"""
内容展示计算服务 - 将业务计算逻辑从 ORM 模型中剥离

原则：ORM 模型只负责数据存储映射，展示/计算逻辑由本模块提供。
"""
from app.media.references import rewrite_media_urls
from app.schemas.content import ContentDetail
from app.schemas.media import MediaPurpose
from app.services.media_manifest import load_content_media_assets, build_media_manifest
from app.services.media_segments import build_media_segment_items
from bs4 import BeautifulSoup
from markdown_it import MarkdownIt

_excerpt_markdown = MarkdownIt()


def compute_content_excerpt(content, max_len: int = 280) -> str | None:
    """Return a bounded, plain-text preview of the stored body without changing it."""
    body = (content.body or "").strip()
    if not body:
        return None
    soup = BeautifulSoup(_excerpt_markdown.render(body[:12000]), "html.parser")
    for node in soup.find_all(["img", "script", "style"]):
        node.decompose()
    text = " ".join(soup.stripped_strings)
    if not text:
        return None
    return text if len(text) <= max_len else text[:max_len].rstrip() + "…"

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


async def build_content_detail(session, content, base_url: str, *, for_edit: bool = False, asset_refs: bool = False) -> ContentDetail:
    """Resolve stored references once, from asset records to response sources."""
    detail = ContentDetail.model_validate(content)
    detail.media_assets = []
    detail.effective_layout_type = compute_effective_layout_type(detail)
    assets = (await load_content_media_assets(
        session, [content.id], purpose=MediaPurpose.DETAIL,
    ))[content.id]
    mapping = {}
    body_mapping = {}
    edit_refs = {}
    for asset in assets:
        manifest = build_media_manifest(asset, purpose=MediaPurpose.DETAIL, base_url=base_url)
        detail.media_assets.append(manifest)
        if asset.media_type.value == "image" and asset.original_url:
            edit_refs[f"asset://image/{asset.id}"] = asset.original_url
        if asset_refs and asset.media_type.value == "image":
            reference = f"asset://image/{asset.id}"
            body_mapping[reference] = reference
            if asset.original_url:
                body_mapping[asset.original_url] = reference
            for variant in asset.variants:
                body_mapping[f"local://{variant.storage_key}"] = reference
            for key in (asset.asset_metadata or {}).get("previous_keys", []):
                body_mapping[f"local://{key}"] = reference
        if manifest.sources:
            preferred = manifest.sources[0].url
            if asset.original_url:
                mapping[asset.original_url] = preferred
            for key in (asset.asset_metadata or {}).get("previous_keys", []):
                mapping[f"local://{key}"] = preferred
            if asset.media_type.value == "image":
                mapping[f"asset://image/{asset.id}"] = preferred
            for variant in asset.variants:
                mapping[f"local://{variant.storage_key}"] = preferred

    if asset_refs:
        mapping.update(body_mapping)

    def bind(value):
        if isinstance(value, str):
            return rewrite_media_urls(value, mapping)
        if isinstance(value, list):
            return [bind(item) for item in value]
        if isinstance(value, dict):
            return {key: bind(item) for key, item in value.items()}
        return value

    for field in ("body", "cover_url", "author_avatar_url", "media_urls", "rich_payload", "context_data"):
        if for_edit and field in {"body", "cover_url"}:
            setattr(detail, field, rewrite_media_urls(getattr(detail, field), edit_refs))
            continue
        setattr(detail, field, bind(getattr(detail, field)))
    detail.media_segments = build_media_segment_items(
        content_id=content.id, rich_payload=content.rich_payload, assets=detail.media_assets,
    )
    return detail
