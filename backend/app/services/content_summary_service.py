import re
import json
import asyncio
import hashlib
from typing import Optional, List
from pydantic import BaseModel, Field
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm.attributes import flag_modified
from sqlalchemy import delete, update
from sqlalchemy.orm.exc import StaleDataError

from app.core.logging import logger
from app.models import Content
from app.models.search import ContentEmbedding
from app.services.config_service import ConfigService


class SemanticChunk(BaseModel):
    """语义切片模型"""
    title: str = Field(..., description="该片段的小标题或核心论点")
    content: str = Field(..., description="片段的正文内容（纯文本）")
    importance: float = Field(default=1.0, description="片段的重要性评分 0.0-1.0")
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


def strip_markdown(text: str) -> str:
    """移除 Markdown 标记，返回纯文本"""
    if not text:
        return ""
    # Remove images
    text = re.sub(r'!\[[^\]]*\]\([^)]*\)', '', text)
    # Remove links, keep text
    text = re.sub(r'\[([^\]]*)\]\([^)]*\)', r'\1', text)
    # Remove headers
    text = re.sub(r'^#{1,6}\s+', '', text, flags=re.MULTILINE)
    # Remove bold/italic/strikethrough
    text = re.sub(r'[*_~`]+', '', text)
    # Remove blockquote markers
    text = re.sub(r'^>\s+', '', text, flags=re.MULTILINE)
    # Remove horizontal rules
    text = re.sub(r'^---+\s*$', '', text, flags=re.MULTILINE)
    # Collapse whitespace
    text = re.sub(r'\n{2,}', '\n', text)
    return text.strip()


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

    from app.services.document_text import build_document_text_items, document_assets
    documents = build_document_text_items(content, await document_assets(session, content_id))
    source_text = content.body or ""
    coverage_notice = ""
    if documents:
        if any(document.status == "pending" for document in documents):
            raise SummaryGenerationError("PDF 正文尚未提取，请先提取正文再生成摘要", status_code=409)
        if not any(page.text.strip() for document in documents for page in document.pages):
            raise SummaryGenerationError("PDF 没有可读取的正文，无法生成文档摘要", status_code=409)
        sections = [f"用户保存说明（不代表文档正文）：\n{source_text}"]
        incomplete = False
        for document in documents:
            sections.append(f"文档：{document.filename}；共 {document.page_count} 页，"
                            f"可读取 {document.text_page_count} 页；状态 {document.status}")
            incomplete |= document.status != "ready" or document.text_page_count != document.page_count
            for page in document.pages:
                sections.append(f"第 {page.page_number} 页：\n{page.text if page.text.strip() else '[未读取到原生文本]'}")
        source_text = "\n\n".join(sections)
        if incomplete:
            coverage_notice = "【仅概括已提取的 PDF 文本，部分页面或附件未读取】"

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
        "仅依据下列来源材料概括，不把保存说明当作文档原文，不能推断未读取页面。\n"
        f"正文内容：\n{source_text}"
    )
    source_hash = hashlib.sha256(json.dumps(
        [summary_model, summary_api_version, prompt, ContentIntelligence.model_json_schema()],
        ensure_ascii=False, sort_keys=True,
    ).encode()).hexdigest()
    if (not force and content.summary and
            (content.rich_payload or {}).get("summary_source_hash") == source_hash):
        return content

    try:
        # 使用原生 Gemini SDK (2026 最新版本写法)
        from google import genai
        from google.genai import types
        
        # 显式初始化 Client 并指定 api_version；模型名来自 summary_model 设置。
        client = genai.Client(
            api_key=gemini_key,
            http_options={'api_version': summary_api_version}
        )
        
        def _call():
            return client.models.generate_content(
                model=summary_model,
                contents=prompt,
                config=types.GenerateContentConfig(
                    response_mime_type="application/json",
                    # 显式传入 Schema 以确保 100% 结构化成功率
                    response_json_schema=ContentIntelligence.model_json_schema()
                )
            )

        response = await asyncio.to_thread(_call)
        
        # 处理 Gemini 3 返回的结构化响应
        if response.parsed:
            # 如果是 Pydantic 模型，尝试转换为字典
            try:
                intelligence_dict = response.parsed.model_dump()
            except AttributeError:
                try:
                    intelligence_dict = response.parsed.dict()
                except AttributeError:
                    intelligence_dict = response.parsed
        else:
            intelligence_dict = json.loads(response.text)



        intelligence_dict = ContentIntelligence.model_validate(intelligence_dict).model_dump()
        if not intelligence_dict["summary"].strip():
            raise ValueError("Model returned an empty summary")
        # Source-derived document pages and media segments must survive a new
        # AI summary. Also reject responses generated against an older revision.
        with session.no_autoflush:
            guard = await session.execute(update(Content).where(
                Content.id == content_id, Content.updated_at == source_revision,
            ).values(updated_at=Content.updated_at).execution_options(synchronize_session=False))
        if guard.rowcount != 1:
            raise StaleDataError("原文已变化，请重新生成摘要")

        # 更新内容字段
        content.summary = coverage_notice + intelligence_dict.get("summary", "")
        # 合并标签
        existing_tags = set(content.tags or [])
        new_tags = set(intelligence_dict.get("tags", []))
        content.tags = list(existing_tags.union(new_tags))
        
        # 存储语义切片到 rich_payload
        if not content.rich_payload:
            content.rich_payload = {}
        
        source_chunks = [chunk for chunk in content.rich_payload.get("chunks", [])
                         if isinstance(chunk, dict) and (chunk.get("source_kind") == "pdf_native_text"
                         or chunk.get("segment_type") in {"chapter", "transcript"})]
        content.rich_payload["chunks"] = source_chunks + [
            {**chunk, "generated": True} for chunk in intelligence_dict["rag_chunks"]
        ]
        content.rich_payload["summary_source_hash"] = source_hash
        
        # 标记 JSON 字段已修改
        flag_modified(content, "rich_payload")
        flag_modified(content, "tags")

        # Chunk positions and the global summary have changed. Retire old
        # vectors atomically so search cannot cite the previous interpretation.
        await session.execute(delete(ContentEmbedding).where(ContentEmbedding.content_id == content_id))
        
        await session.commit()
        logger.info(f"AI 深度理解完成: content_id={content_id}, 生成切片数={len(content.rich_payload['chunks'])}")

    except StaleDataError:
        await session.rollback()
        raise
    except Exception as e:
        await session.rollback()
        logger.error("摘要生成失败: content_id={}, error_type={}", content_id, type(e).__name__)
        raise SummaryGenerationError("摘要生成失败，请检查模型服务后重试") from e
        
    return content
