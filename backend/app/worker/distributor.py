"""
内容分发 Worker。

处理向不同平台分发内容的逻辑。
"""
from app.models import Content, DistributionRule


class ContentDistributor:
    """内容分发器。"""

    async def _build_content_payload(
        self,
        content: Content,
        rule: DistributionRule | None,
        target_render_config: dict | None = None,
    ) -> dict:
        payload = {
            "id": content.id,
            "title": content.title,
            "platform": content.platform.value if content.platform else None,
            "cover_url": content.cover_url,
            "raw_metadata": content.raw_metadata,
            "canonical_url": content.canonical_url,
            "tags": content.tags,
            "is_nsfw": content.is_nsfw,
            "description": content.description,
            "author_name": content.author_name,
            "author_id": content.author_id,
            "published_at": content.published_at,
            "view_count": content.view_count,
            "like_count": content.like_count,
            "collect_count": content.collect_count,
            "share_count": content.share_count,
            "comment_count": content.comment_count,
            "extra_stats": content.extra_stats or {},
            "content_type": content.content_type,
            "clean_url": content.clean_url,
            "url": content.url,
        }

        if rule and rule.render_config:
            payload["render_config"] = rule.render_config

        if target_render_config:
            base = payload.get("render_config") or {}
            payload["render_config"] = {**base, **target_render_config}

        return payload



