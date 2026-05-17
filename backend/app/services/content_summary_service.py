import re
import json
import asyncio
import os
from typing import Optional, List
from pydantic import BaseModel, Field
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm.attributes import flag_modified

from app.core.config import settings
from app.core.logging import logger
from app.models import Content
from app.services.settings_service import get_setting_value
from app.utils.sensitive_display import extract_secret_value


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


def _as_nonempty_string(value: object) -> str | None:
    if isinstance(value, str) and value.strip():
        return value.strip()
    return None


async def _get_summary_llm_config() -> tuple[str | None, str, str]:
    """Return summary-specific Gemini config without falling back to embedding settings."""
    key = _as_nonempty_string(await get_setting_value("summary_api_key"))
    if not key:
        key = extract_secret_value(settings.summary_api_key)
    if not key:
        # Backward-compatible env alias; still intentionally separate from embedding_api_key.
        key = os.environ.get("GEMINI_API_KEY")

    model = _as_nonempty_string(
        await get_setting_value("summary_model", settings.summary_model)
    ) or settings.summary_model
    api_version = _as_nonempty_string(
        await get_setting_value("summary_api_version", settings.summary_api_version)
    ) or settings.summary_api_version
    return key, model, api_version


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

    if not force and content.summary and content.rich_payload and content.rich_payload.get("chunks"):
        logger.debug(f"AI 理解数据已存在，跳过: content_id={content_id}")
        return content

    gemini_key, summary_model, summary_api_version = await _get_summary_llm_config()

    if not gemini_key:
        logger.warning("Summary API Key 未配置，跳过智能分析")
        return content

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
        f"正文内容：\n{content.body or ''}"
    )

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



        # 更新内容字段
        content.summary = intelligence_dict.get("summary", "")
        # 合并标签
        existing_tags = set(content.tags or [])
        new_tags = set(intelligence_dict.get("tags", []))
        content.tags = list(existing_tags.union(new_tags))
        
        # 存储语义切片到 rich_payload
        if not content.rich_payload:
            content.rich_payload = {}
        
        content.rich_payload["chunks"] = intelligence_dict.get("rag_chunks", [])
        
        # 标记 JSON 字段已修改
        flag_modified(content, "rich_payload")
        flag_modified(content, "tags")
        
        await session.commit()
        logger.info(f"AI 深度理解完成: content_id={content_id}, 生成切片数={len(content.rich_payload['chunks'])}")

    except Exception as e:
        logger.error(f"AI 深度理解最终失败: content_id={content_id}, error={e}")
        
    return content
