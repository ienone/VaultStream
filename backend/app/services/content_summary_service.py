import json
import hashlib
from typing import List
from pydantic import BaseModel, Field
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import update
from sqlalchemy.orm.exc import StaleDataError

from app.core.logging import logger
from app.models import Content
from app.services.config_service import ConfigService


class SemanticChunk(BaseModel):
    """语义切片模型"""
    title: str = Field(..., description="该片段的小标题或核心论点")
    content: str = Field(..., description="片段的正文内容（纯文本）")
    media_refs: List[str] = Field(default_factory=list, description="该片段关联的图片或媒体 URL (local:// 协议)")


class ContentIntelligence(BaseModel):
    """AI 内容理解结果模型"""
    summary: str = Field(..., description="120字以内的极简总结")
    tags: List[str] = Field(default_factory=list, description="提取的 3-5 个核心标签")
    rag_chunks: List[SemanticChunk] = Field(..., description="将全文拆解为若干个语义逻辑块，用于精准检索")


class SummaryGenerationError(RuntimeError):
    """A safe user-facing failure, without provider request details."""

    def __init__(self, message: str, *, status_code: int = 502):
        super().__init__(message)
        self.status_code = status_code


async def _get_summary_llm_config() -> tuple[str | None, str, str]:
    """Return summary-specific Gemini config without falling back to embedding settings."""
    summary_config = await ConfigService().get_summary_ai_config()
    return (
        summary_config.api_key,
        summary_config.model,
        summary_config.api_version,
    )


async def generate_summary_for_content(
    session: AsyncSession,
    content_id: int,
    *,
    force: bool = False,
) -> Content:
    """
    使用 AI 对内容进行深度理解：
    1. 生成摘要
    2. 提取标签
    3. 智能语义切片 (用于 RAG)
    """
    content = await session.get(Content, content_id)
    if content is None:
        raise ValueError(f"内容不存在: {content_id}")

    source_revision = content.updated_at

    source_text = content.body or ""

    gemini_key, summary_model, summary_api_version = await _get_summary_llm_config()

    if not gemini_key:
        raise SummaryGenerationError("摘要模型访问密钥未配置", status_code=503)

    # 准备 Prompt
    prompt = (
        "你是一个专业的信息分析专家。请对以下文章进行深度拆解。\n"
        "任务要求：\n"
        "1. 生成一段 120 字以内的精炼摘要，直击核心。\n"
        "2. 提取 3-5 个最具代表性的标签。\n"
        "3. 将文章划分为若干个逻辑独立的语义块（Chunks）。每个块应包含一个小标题和对应的正文。\n"
        "4. **重要**：如果正文中有 local://sha256:... 格式的图片引用，请将其归入对应的语义块中。\n"
        "5. 严格以 JSON 格式输出，结构如下：\n"
        "{\"summary\": \"...\", \"tags\": [\"tag1\", \"tag2\"], \"rag_chunks\": [{\"title\": \"...\", \"content\": \"...\", \"media_refs\": [\"local://...\"]}]}"
        "\n\n"
        f"标题：{content.title or '无标题'}\n"
        f"正文内容：\n{source_text}"
    )
    source_hash = hashlib.sha256(json.dumps(
        [summary_model, summary_api_version, prompt, ContentIntelligence.model_json_schema()],
        ensure_ascii=False, sort_keys=True,
    ).encode()).hexdigest()
    if (not force and content.summary and
            (content.rich_payload or {}).get("summary_source_hash") == source_hash):
        return content

    from google import genai
    from google.genai import types

    try:
        async with genai.Client(api_key=gemini_key, http_options={"api_version": summary_api_version}).aio as client:
            response = await client.models.generate_content(
                model=summary_model, contents=prompt,
                config=types.GenerateContentConfig(
                    response_mime_type="application/json", response_json_schema=ContentIntelligence.model_json_schema(),
                ),
            )
        intelligence = ContentIntelligence.model_validate(
            response.parsed if response.parsed is not None else json.loads(response.text)
        )
        if not intelligence.summary.strip():
            raise ValueError("模型返回的摘要为空")
    except Exception as exc:
        logger.error("摘要模型请求失败: content_id={}, error_type={}", content_id, type(exc).__name__)
        raise SummaryGenerationError("摘要生成失败，请检查模型服务后重试") from exc

    guard = await session.execute(update(Content).where(
        Content.id == content_id, Content.updated_at == source_revision,
    ).values(updated_at=Content.updated_at).execution_options(synchronize_session=False))
    if guard.rowcount != 1:
        await session.rollback()
        raise StaleDataError("原文已变化，请重新生成摘要")

    from app.services.embedding_service import EmbeddingService
    from app.services.post_ingest import PostIngestService

    content.summary = intelligence.summary
    content.tags = list(dict.fromkeys([*(content.tags or []), *intelligence.tags]))
    payload = content.rich_payload or {}
    source_chunks = [
        chunk for chunk in payload.get("chunks", [])
        if isinstance(chunk, dict) and chunk.get("segment_type") in {"chapter", "transcript"}
    ]
    content.rich_payload = {
        **payload, "summary_source_hash": source_hash,
        "chunks": [*source_chunks, *({**chunk.model_dump(), "generated": True} for chunk in intelligence.rag_chunks)],
    }
    await EmbeddingService().invalidate_changed_units(content, session)
    await PostIngestService().run_for_content(
        session, content, source="summary", summary=False, distribution=False, commit=False,
    )
    await session.commit()
    return content
