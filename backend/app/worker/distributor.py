"""
内容分发 Worker。

处理向不同平台分发内容的逻辑。
"""
from app.models import Content, DistributionRule
from app.schemas import ContentPushPayload
from app.media.extractor import extract_media_urls


class ContentDistributor:
    """内容分发器。"""

    async def _build_content_payload(
        self,
        content: Content,
        rule: DistributionRule | None,
        target_render_config: dict | None = None,
    ) -> dict:
        # 通过 Pydantic schema 自动映射 ORM 字段
        payload = ContentPushPayload.model_validate(content).model_dump()

        # platform 需要转为字符串值（ORM 存储的是 enum）
        if content.platform:
            payload["platform"] = content.platform.value

        # render_config 合并逻辑：rule 级 → target 级覆盖
        if rule and rule.render_config:
            payload["render_config"] = rule.render_config
        if target_render_config:
            base = payload.get("render_config") or {}
            payload["render_config"] = {**base, **target_render_config}

        # 推送链路使用预提取媒体列表，避免把 archive_metadata 透传给外部推送服务。
        payload["media_items"] = extract_media_urls(
            content.archive_metadata or {},
            content.cover_url,
        )

        return payload
