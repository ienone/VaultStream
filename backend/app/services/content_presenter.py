"""
内容展示计算服务 - 将业务计算逻辑从 ORM 模型中剥离

原则：ORM 模型只负责数据存储映射，展示/计算逻辑由本模块提供。
"""
import re
from typing import Optional, Dict, Any
from app.models import LayoutType, Platform


def compute_effective_layout_type(content) -> Optional[str]:
    """获取有效布局类型：用户覆盖 > 系统检测。返回字符串值。"""
    if content.layout_type_override:
        return content.layout_type_override.value if hasattr(content.layout_type_override, 'value') else str(content.layout_type_override)
    if content.layout_type:
        return content.layout_type.value if hasattr(content.layout_type, 'value') else str(content.layout_type)
    return None


def compute_display_title(content, max_len: int = 60, fallback: str = "无标题") -> str:
    """获取显示用标题：优先使用 title，否则从 body 生成"""
    from app.adapters.utils import ensure_title
    return ensure_title(content.title, content.body, max_len=max_len, fallback=fallback)


def compute_author_avatar_url(content) -> Optional[str]:
    """获取作者头像 URL。直接返回数据库字段值。"""
    return content.author_avatar_url


def transform_media_url(url: Optional[str], base_url: str) -> Optional[str]:
    """将 local:// 协议的 URL 转换为 HTTP 代理 URL"""
    if url and url.startswith("local://"):
        key = url.replace("local://", "")
        return f"{base_url}/api/v1/media/{key}"
    return url


def transform_content_detail(content, base_url: str):
    """转换内容详情中的所有媒体链接（Pydantic ContentDetail 对象）"""
    content.cover_url = transform_media_url(content.cover_url, base_url)
    content.author_avatar_url = transform_media_url(content.author_avatar_url, base_url)
    if content.media_urls:
        content.media_urls = [transform_media_url(u, base_url) for u in content.media_urls if u]

    # Rich Payload (Blocks)
    if content.rich_payload and "blocks" in content.rich_payload:
        blocks = content.rich_payload["blocks"]
        if isinstance(blocks, list):
            for block in blocks:
                if not isinstance(block, dict): continue
                data = block.get("data")
                if isinstance(data, dict):
                    if data.get("cover_url"):
                        data["cover_url"] = transform_media_url(data["cover_url"], base_url)
                    if data.get("author_avatar_url"):
                        data["author_avatar_url"] = transform_media_url(data["author_avatar_url"], base_url)

    # Context Data
    if content.context_data:
        if content.context_data.get("cover_url"):
            content.context_data["cover_url"] = transform_media_url(
                content.context_data["cover_url"], base_url
            )
        if content.context_data.get("author_avatar_url"):
            content.context_data["author_avatar_url"] = transform_media_url(
                content.context_data["author_avatar_url"], base_url
            )

    if content.body and "local://" in content.body:
        _local_pattern = re.compile(r'local://([a-zA-Z0-9_/.-]+)')
        content.body = _local_pattern.sub(
            lambda m: f"{base_url}/api/v1/media/{m.group(1)}", content.body
        )

    # 摘要回退：如无 LLM 摘要则截取正文
    if not content.summary and content.body:
        from app.services.content_summary_service import fallback_summary
        content.summary = fallback_summary(content.body)

    # 清理 U+FFFD 替换字符，避免客户端 UTF-8 解码报错
    if content.body:
        content.body = content.body.replace('\ufffd', '')
    if content.title:
        content.title = content.title.replace('\ufffd', '')

    return content
