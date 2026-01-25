"""
B站动态解析器

负责解析B站动态/图文内容（Opus格式）
包含复杂的存档构建逻辑，用于完整保存动态内容
"""
import httpx
from datetime import datetime
from typing import Dict, Any, List, Set
from app.core.logging import logger
from app.adapters.base import ParsedContent
from app.adapters.errors import (
    AuthRequiredAdapterError,
    NonRetryableAdapterError,
    RetryableAdapterError,
)
from app.models import BilibiliContentType
from .base import clean_text, safe_url, render_markdown, parse_opus_text_nodes, format_request_error
import re


# API端点
API_DYNAMIC_INFO = "https://api.bilibili.com/x/polymer/web-dynamic/v1/opus/detail"
API_DYNAMIC_DETAIL = "https://api.bilibili.com/x/polymer/web-dynamic/v1/detail"


def build_opus_archive(item: Dict[str, Any]) -> Dict[str, Any]:
    """
    从Polymer动态详情中提取可存档的完整图文内容
    
    目标：用于个人浏览记录存档（raw_metadata内），不影响对外分享字段
    
    Args:
        item: 动态详情数据
        
    Returns:
        Dict[str, Any]: 可JSON序列化的存档结构
    """
    archive: Dict[str, Any] = {
        "version": 2,
        "type": "bilibili_opus",
        # 归档（私有）字段：不对外输出
        "title": "",
        "plain_text": "",
        "markdown": "",
        "blocks": [],
        "images": [],
        "links": [],
        "mentions": [],
        "topics": [],
    }

    # 提取modules结构
    modules = (item or {}).get("modules")
    modules_map: Dict[str, Any] = {}
    if isinstance(modules, list):
        for m in modules:
            m_type = (m.get("module_type") or "").lower().replace("_type_", "_")
            if m_type:
                modules_map[m_type] = m.get(m_type, {})
    elif isinstance(modules, dict):
        modules_map = modules

    module_dynamic = modules_map.get("module_dynamic", {})
    module_content = modules_map.get("module_content", {})
    module_title = modules_map.get("module_title", {})

    major = (module_dynamic or {}).get("major", {})
    opus = (major or {}).get("opus", {})

    # 1) 标题
    title_val = opus.get("title") or module_title.get("text") or item.get("basic", {}).get("title") or ""
    archive["title"] = clean_text(title_val)

    # 2) 结构化正文paragraphs
    # opus/detail对于"文章式Opus"常见结构为module_content.paragraphs
    paragraphs = (
        (module_content.get("paragraphs") if isinstance(module_content, dict) else None)
        or ((opus.get("content") or {}).get("paragraphs") or [])
        or []
    )
    
    blocks: List[Dict[str, Any]] = []
    text_chunks: List[str] = []
    images: List[Dict[str, Any]] = []
    links: List[Dict[str, Any]] = []
    
    for p in paragraphs:
        if not isinstance(p, dict):
            continue

        # 常见结构：{"para_type": 1, "text": {"nodes": [...]}}
        para_type = p.get("para_type")

        # Heading标题
        heading = p.get("heading")
        if isinstance(heading, dict):
            level = heading.get("level")
            nodes = heading.get("nodes")
            plain, md_inline = parse_opus_text_nodes(nodes, links, archive["mentions"], archive["topics"])
            cleaned = clean_text(plain)
            if cleaned:
                blocks.append({"type": "heading", "level": level, "text": cleaned, "para_type": para_type})
                text_chunks.append(cleaned)
            continue

        # Separator分隔线
        if para_type == 3 and isinstance(p.get("line"), dict):
            blocks.append({"type": "separator", "para_type": para_type})
            continue

        # Text paragraph / quote文本段落/引用
        text_obj = p.get("text") or {}
        nodes = text_obj.get("nodes")
        p_text = text_obj.get("content")
        if nodes is not None:
            plain, md_inline = parse_opus_text_nodes(nodes, links, archive["mentions"], archive["topics"])
            cleaned_plain = clean_text(plain)
            if cleaned_plain:
                block_type = "quote" if para_type == 4 else "text"
                blocks.append({"type": block_type, "text": cleaned_plain, "para_type": para_type})
                text_chunks.append(cleaned_plain)
        elif p_text:
            cleaned = clean_text(p_text)
            if cleaned:
                block_type = "quote" if para_type == 4 else "text"
                blocks.append({"type": block_type, "text": cleaned, "para_type": para_type})
                text_chunks.append(cleaned)

        # 图片：para_type=2常见为pic.pics列表；也可能是pic.url
        pic = p.get("pic") or {}
        if isinstance(pic, dict):
            pic_list = pic.get("pics")
            if isinstance(pic_list, list):
                for one in pic_list:
                    if not isinstance(one, dict):
                        continue
                    url = safe_url(one.get("url"))
                    if not url:
                        continue
                    img = {
                        "url": url,
                        "width": one.get("width"),
                        "height": one.get("height"),
                        "size": one.get("size"),
                    }
                    blocks.append({"type": "image", **img, "para_type": para_type})
                    images.append(img)
            else:
                url = safe_url(pic.get("url") or pic.get("src"))
                if url:
                    img = {
                        "url": url,
                        "width": pic.get("width"),
                        "height": pic.get("height"),
                        "size": pic.get("size"),
                        "image_type": pic.get("image_type") or pic.get("type"),
                    }
                    blocks.append({"type": "image", **img, "para_type": para_type})
                    images.append(img)

        # link链接信息（若存在）
        link = p.get("link")
        if isinstance(link, dict):
            href = safe_url(link.get("url") or link.get("href"))
            if href:
                links.append({"url": href, "text": clean_text(link.get("text") or "")})

    # 3) 顶层pics
    pics = opus.get("pics") or []
    for pic in pics:
        if not isinstance(pic, dict):
            continue
        url = safe_url(pic.get("url"))
        if not url:
            continue
        img = {
            "url": url,
            "width": pic.get("width"),
            "height": pic.get("height"),
            "size": pic.get("size"),
            "image_type": pic.get("image_type"),
        }
        images.append(img)
        blocks.append({"type": "image", **img})

    # 4) 兜底：如果没有paragraphs，也尽量从可能存在的字段拿到文本
    if not text_chunks:
        fallback_text = opus.get("summary") or opus.get("text") or opus.get("content")
        if isinstance(fallback_text, str) and fallback_text.strip():
            cleaned = clean_text(fallback_text)
            if cleaned:
                blocks.append({"type": "text", "text": cleaned})
                text_chunks.append(cleaned)

    # 5) 额外附件/外链（如果存在，旧结构兼容）
    rich_text_nodes = (opus.get("rich_text") or {}).get("nodes")
    if isinstance(rich_text_nodes, list):
        for n in rich_text_nodes:
            if not isinstance(n, dict):
                continue
            n_type = (n.get("type") or "").lower()
            if n_type in ("link", "url"):
                href = safe_url(n.get("href") or n.get("url"))
                if href:
                    links.append({"url": href, "text": clean_text(n.get("text") or "")})
                    blocks.append({"type": "link", "url": href, "text": clean_text(n.get("text") or "")})
            elif n_type in ("at", "mention"):
                mid = n.get("rid") or n.get("mid") or n.get("id")
                name = n.get("text") or n.get("uname") or ""
                archive["mentions"].append({"mid": str(mid) if mid is not None else None, "name": clean_text(name)})
            elif n_type in ("topic", "tag"):
                topic = n.get("text") or n.get("topic") or ""
                topic = clean_text(topic)
                if topic:
                    archive["topics"].append(topic)

    # 标题作为首block（便于markdown/搜索）
    if archive.get("title"):
        blocks = [{"type": "title", "text": archive["title"]}] + blocks

    # 去重links/images
    seen_urls: Set[str] = set()
    uniq_links: List[Dict[str, Any]] = []
    for l in links:
        u = safe_url(l.get("url"))
        if not u or u in seen_urls:
            continue
        seen_urls.add(u)
        uniq_links.append({"url": u, "text": clean_text(l.get("text") or "")})

    seen_img: Set[str] = set()
    uniq_images: List[Dict[str, Any]] = []
    for img in images:
        u = safe_url(img.get("url"))
        if not u or u in seen_img:
            continue
        seen_img.add(u)
        uniq_images.append({**img, "url": u})

    archive["blocks"] = blocks
    archive["images"] = uniq_images
    archive["links"] = uniq_links
    archive["plain_text"] = clean_text("\n\n".join([t for t in text_chunks if t]))
    archive["markdown"] = render_markdown(blocks)

    # 日志：用于确认存档内容是否构建成功（避免打印全文）
    logger.debug(
        "Opus archive built: title_len={}, text_len={}, blocks={}, images={}, links={}, mentions={}, topics={}",
        len(str(archive.get("title") or "")),
        len(str(archive.get("plain_text") or "")),
        len(archive.get("blocks") or []),
        len(archive.get("images") or []),
        len(archive.get("links") or []),
        len(archive.get("mentions") or []),
        len(archive.get("topics") or []),
    )

    return archive


async def parse_dynamic(
    url: str,
    headers: Dict[str, str],
    cookies: Dict[str, str]
) -> ParsedContent:
    """
    解析B站动态/图文（Opus）
    
    Args:
        url: 动态URL（已净化）
        headers: HTTP请求头
        cookies: 登录Cookie
        
    Returns:
        ParsedContent: 解析后的标准化内容
        
    Raises:
        AuthRequiredAdapterError: 需要登录
        NonRetryableAdapterError: 资源不可用
        RetryableAdapterError: 网络错误或API错误
    """
    # 提取动态ID
    match = re.search(r'bilibili\.com/opus/(\d+)', url)
    if not match:
        match = re.search(r't\.bilibili\.com/(\d+)', url)
    if not match:
        raise NonRetryableAdapterError(f"无法从URL提取动态ID: {url}")
    
    dynamic_id = match.group(1)
    
    # 动态解析需要特定的features参数和buvid3 cookie才能稳定返回
    params = {
        'id': dynamic_id,
        'features': 'itemOpusStyle,opusBigCover,onlyfansVote,endFooterHidden,decorationCard,onlyfansAssetsV2,ugcDelete,onlyfansQaCard,commentsNewVersion'
    }
    
    # 确保有buvid3 cookie
    cookies_copy = cookies.copy()
    if 'buvid3' not in cookies_copy:
        cookies_copy['buvid3'] = 'awa'
    
    # 发起API请求
    async with httpx.AsyncClient(headers=headers, cookies=cookies_copy, timeout=15.0) as client:
        try:
            response = await client.get(API_DYNAMIC_INFO, params=params)
            data = response.json()
        except httpx.RequestError as e:
            raise RetryableAdapterError(f"B站请求失败: {format_request_error(e)}")
        
        # 检查API响应状态
        if data.get('code') != 0:
            # opus/detail偶发不稳定：兜底尝试标准detail接口
            try:
                response2 = await client.get(
                    API_DYNAMIC_DETAIL,
                    params={
                        "id": dynamic_id,
                        "features": params.get("features"),
                        "platform": "web",
                        "gaia_source": "main_web",
                    },
                )
                data2 = response2.json()
                if data2.get("code") == 0:
                    data = data2
                else:
                    raise Exception(data2.get("message"))
            except Exception as e:
                code = data.get('code')
                msg = data.get('message')
                
                # 风控/校验失败
                if code in (-352,):
                    raise RetryableAdapterError(f"B站风控/校验失败: {msg}", details={"code": code})
                
                # 权限不足
                if code in (-403,):
                    raise AuthRequiredAdapterError(f"B站权限不足: {msg}", details={"code": code})
                
                # 其他错误
                raise RetryableAdapterError(
                    f"B站API错误: {msg}", 
                    details={"code": code, "fallback_error": str(e)}
                )
        
        item = data['data']['item']

        # 构建存档数据（完整图文），放进raw_metadata里
        try:
            archive = build_opus_archive(item)
            logger.info(
                "Opus archive ready: dynamic_id={}, text_len={}, images={}",
                dynamic_id,
                len(str(archive.get("plain_text") or "")),
                len(archive.get("images") or []),
            )
        except Exception as e:
            logger.warning(f"构建Opus存档失败: {e}")
            archive = {"version": 2, "type": "bilibili_opus", "error": str(e)}

        modules = item.get('modules', [])

        # 兼容列表结构的modules（Polymer API特点）
        modules_map = {}
        if isinstance(modules, list):
            for m in modules:
                # 修正映射逻辑：MODULE_TYPE_AUTHOR -> module_author
                m_type = m.get('module_type', '').lower().replace('_type_', '_')
                if m_type:
                    modules_map[m_type] = m.get(m_type, {})
        else:
            modules_map = modules

        module_author = modules_map.get('module_author', {})
        module_dynamic = modules_map.get('module_dynamic', {})
        module_stat = modules_map.get('module_stat', {})
        module_title = modules_map.get('module_title', {})

        # 处理Opus图文内容
        major = module_dynamic.get('major', {})
        opus = major.get('opus', {})

        # 标题回退机制（分享用：保持现状）
        title = opus.get('title') or module_title.get('text') or item.get('basic', {}).get('title') or "动态"

        # 提取正文（分享用：优先使用archive中的完整纯文本）
        summary = archive.get("plain_text") or ""
        if not summary and opus.get('content', {}).get('paragraphs'):
            summary = "\n".join([p.get('text', {}).get('content', '') 
                               for p in opus['content']['paragraphs'] 
                               if p.get('text', {}).get('content')])

        summary = clean_text(summary)

        # 提取图片（分享用：优先使用archive中的图片列表）
        pics = [img.get("url") for img in archive.get("images", []) if img.get("url")]
        if not pics:
            pics = [safe_url(p.get('url')) for p in opus.get('pics', []) if safe_url(p.get('url'))]

        # 提取互动数据
        stats = {
            'view': 0,
            'like': module_stat.get('like', {}).get('count', 0) if isinstance(module_stat.get('like'), dict) else 0,
            'reply': module_stat.get('comment', {}).get('count', 0) if isinstance(module_stat.get('comment'), dict) else 0,
            'share': module_stat.get('forward', {}).get('count', 0) if isinstance(module_stat.get('forward'), dict) else 0,
        }

        # 作者信息
        author_mid = module_author.get('mid') or item.get('basic', {}).get('uid')
        author_id = str(author_mid) if author_mid else None
        author_face = module_author.get('face')
        author_url = f"https://space.bilibili.com/{author_mid}" if author_mid else None

        # raw_metadata：保留原始item，并附加archive（便于后续浏览功能开发）
        raw_metadata = dict(item) if isinstance(item, dict) else {"item": item}
        raw_metadata.setdefault("archive", {})
        raw_metadata["archive"] = archive

        logger.info(
            "Dynamic parsed with archive attached: dynamic_id={}, has_archive={}, archive_keys={}",
            dynamic_id,
            bool(raw_metadata.get("archive")),
            list((raw_metadata.get("archive") or {}).keys()),
        )

        # 构建ParsedContent
        return ParsedContent(
            platform='bilibili',
            content_type=BilibiliContentType.DYNAMIC.value,
            content_id=dynamic_id,
            clean_url=url,
            title=title,
            description=summary,
            author_name=module_author.get('name') or "未知用户",
            author_id=author_id,
            author_avatar_url=author_face,
            author_url=author_url,
            cover_url=pics[0] if pics else None,
            media_urls=pics,
            published_at=datetime.fromtimestamp(module_author.get('pub_ts')) if module_author.get('pub_ts') else None,
            raw_metadata=raw_metadata,
            stats=stats
        )
