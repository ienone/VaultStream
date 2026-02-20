"""
内容展示计算服务 - 将业务计算逻辑从 ORM 模型中剥离

原则：ORM 模型只负责数据存储映射，展示/计算逻辑由本模块提供。
"""
import re
from typing import Optional
from app.models import LayoutType, Platform


def compute_effective_layout_type(content) -> Optional[str]:
    """获取有效布局类型：用户覆盖 > 系统检测。返回字符串值。"""
    if content.layout_type_override:
        return content.layout_type_override.value if hasattr(content.layout_type_override, 'value') else str(content.layout_type_override)
    if content.layout_type:
        return content.layout_type.value if hasattr(content.layout_type, 'value') else str(content.layout_type)
    return None


def compute_display_title(content, max_len: int = 60, fallback: str = "无标题") -> str:
    """获取显示用标题：优先使用 title，否则从 description 生成"""
    from app.adapters.utils import ensure_title
    return ensure_title(content.title, content.description, max_len=max_len, fallback=fallback)


def compute_author_avatar_url(content) -> Optional[str]:
    """获取作者头像 URL，如果数据库字段为空则尝试从元数据中动态提取"""
    # 优先使用数据库中已存储的值
    db_value = content.author_avatar_url
    if db_value:
        return db_value

    try:
        if not content.raw_metadata:
            return None

        # 从 raw_metadata 动态提取头像信息（各平台逻辑不同）
        if content.platform == Platform.WEIBO:
            if content.content_type == "user_profile":
                return content.raw_metadata.get("avatar_hd")
            return (content.raw_metadata.get("user", {}).get("avatar_hd") or
                    content.raw_metadata.get("user", {}).get("profile_image_url"))

        if content.platform == Platform.BILIBILI:
            return (content.raw_metadata.get("author", {}).get("face") or
                    content.raw_metadata.get("owner", {}).get("face"))

        if content.platform == Platform.TWITTER:
            return content.raw_metadata.get("user", {}).get("profile_image_url_https")

        if content.platform == Platform.ZHIHU:
            return (content.raw_metadata.get("author", {}).get("avatarUrl") or
                    content.raw_metadata.get("author", {}).get("avatar_url"))
    except Exception:
        pass
    return None


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

    if content.top_answers:
        for ans in content.top_answers:
            if ans.get("author_avatar_url"):
                ans["author_avatar_url"] = transform_media_url(ans["author_avatar_url"], base_url)
            if ans.get("cover_url"):
                ans["cover_url"] = transform_media_url(ans["cover_url"], base_url)

    if content.associated_question:
        if content.associated_question.get("cover_url"):
            content.associated_question["cover_url"] = transform_media_url(
                content.associated_question["cover_url"], base_url
            )

    if content.description and "local://" in content.description:
        _local_pattern = re.compile(r'local://([a-zA-Z0-9_/.-]+)')
        content.description = _local_pattern.sub(
            lambda m: f"{base_url}/api/v1/media/{m.group(1)}", content.description
        )

    return content

