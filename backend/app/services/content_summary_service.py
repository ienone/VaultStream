"""
内容摘要生成服务

支持模式：
1. LLM 生成：调用大模型生成智能摘要
"""
import re
from typing import Optional
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.logging import logger
from app.models import Content
from app.core.llm_factory import LLMFactory


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





    
async def _get_visual_description(images: list[str]) -> str:
    """使用 Vision LLM 提取图片的视觉描述"""
    from langchain_core.messages import HumanMessage
    
    llm = await LLMFactory.get_vision_llm()
    if not llm:
        return ""
        
    prompt = "请简洁描述这些图片中的关键信息（如文字、主要人物、核心场景），用于辅助生成内容摘要。直接输出描述内容，不要加任何前置解释。"
    message_content = [{"type": "text", "text": prompt}]
    
    # 仅取前 3 张图片
    for img_url in images[:3]:
        if img_url and img_url.startswith("http"):
             message_content.append({
                "type": "image_url",
                "image_url": {"url": img_url}
            })
            
    try:
        response = await llm.ainvoke([HumanMessage(content=message_content)])
        desc = response.content.strip()
        logger.debug(f"视觉描述提取成功: {desc[:50]}...")
        return f"\n[视觉信息描述：{desc}]\n"
    except Exception as e:
        logger.warning(f"视觉描述提取失败: {e}")
        return ""


async def generate_summary_llm(
    body: str,
    *,
    title: Optional[str] = None,
    images: Optional[list[str]] = None,
    max_summary_len: int = 120,
) -> str:
    """调用 LLM 生成摘要 (采用 视觉描述 -> 文本总结 管道)"""
    from langchain_core.messages import HumanMessage
    
    # 1. 如果有图片，先获取视觉描述 (Vision LLM)
    visual_desc = ""
    if images and len(images) > 0:
        visual_desc = await _get_visual_description(images)

    # 2. 加载文本模型进行最终总结 (Text LLM)
    llm = await LLMFactory.get_text_llm()
    if llm is None:
        # 如果没配置纯文本模型，尝试用视觉模型代劳
        llm = await LLMFactory.get_vision_llm()
        
    if llm is None:
        raise RuntimeError("LLM 未配置，无法生成摘要")

    # 3. 整合输入
    plain = strip_markdown(body)
    # 将视觉信息注入正文尾部
    combined_text = f"{plain}\n{visual_desc}" if visual_desc else plain
    
    max_text_len = 8000
    input_text = combined_text[:max_text_len] if len(combined_text) > max_text_len else combined_text

    prompt_text = (
        f"请对以下内容进行极简总结（{max_summary_len}字以内）。"
        "要求：一针见血，直击核心，拒绝废话，不要以'本文介绍了'或'这篇推文'等词起头。"
        "只输出摘要本身，不要加任何前缀、标签或解释。\n\n"
    )
    if title:
        prompt_text += f"标题：{title}\n\n"
    prompt_text += f"内容：\n{input_text}"

    try:
        response = await llm.ainvoke([HumanMessage(content=prompt_text)])
    except Exception as e:
        logger.error(f"摘要最终生成失败: {e}")
        raise e
        
    summary = response.content.strip()

    # 确保不超过限制
    if len(summary) > max_summary_len:
        summary = summary[:max_summary_len] + "…"

    return summary


async def generate_summary_for_content(
    session: AsyncSession,
    content_id: int,
    *,
    force: bool = False,
) -> Content:
    """为指定内容生成摘要并持久化"""
    content = await session.get(Content, content_id)
    if content is None:
        raise ValueError(f"内容不存在: {content_id}")

    if not force and content.summary:
        logger.debug(f"摘要已存在，跳过生成: content_id={content_id}")
        return content

    if not content.body and not content.media_urls:
        # 无正文且无图片，使用标题作为摘要
        content.summary = content.title
        await session.commit()
        return content

    # 获取图片列表
    images = []
    # 优先从 archive_metadata 获取原始图片 URL
    if content.archive_metadata and isinstance(content.archive_metadata, dict):
        archive = content.archive_metadata.get("archive", {})
        if isinstance(archive, dict):
            imgs = archive.get("images", [])
            for img in imgs:
                if isinstance(img, dict) and img.get("url"):
                    if img.get("type") != "avatar" and not img.get("is_avatar"):
                        images.append(img["url"])
    
    if not images and content.media_urls:
        images = [u for u in content.media_urls if u and not u.startswith("local://")]

    # 如果只有短文本，且没有图片，则完全跳过生成
    plain_text = strip_markdown(content.body) if content.body else ""
    if len(plain_text) < 150 and not images:
        logger.debug(f"内容太短且无图片，跳过生成摘要: content_id={content_id}")
        content.summary = None
        await session.commit()
        return content

    try:
        content.summary = await generate_summary_llm(
            content.body or "",
            title=content.title,
            images=images if images else None
        )
        logger.info(f"LLM 摘要生成成功: content_id={content_id}, len={len(content.summary)}")
    except Exception as e:
        logger.warning(f"LLM 摘要生成失败，或者模型未配置: {e}")
        content.summary = None

    await session.commit()
    
    # 发布更新事件
    try:
        from app.core.events import event_bus
        await event_bus.publish("content_updated", {
            "id": content.id,
            "title": content.title,
            "status": content.status.value,
            "summary": content.summary,
            "platform": content.platform.value if content.platform else None,
        })
    except Exception as e:
        logger.warning(f"摘要更新事件发布失败: {e}")

    return content
