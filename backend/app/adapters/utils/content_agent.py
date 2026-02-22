"""
Content Agent — 2-Layer Architecture with Tool Functions

Pipeline:
  URL → tiered_fetch → raw content
    [Markdown path] — content already in Markdown
      → layer1_scan → layer2_extract → apply → result   (2 LLM)
    [HTML path] — content is HTML
      → tool_analyze_dom → (auto_selector | llm_target) → tool_convert_html
      → layer1_scan → layer2_extract → apply → result   (2-3 LLM)
"""

import re
import json
from typing import Optional, Tuple, Dict, List
from dataclasses import dataclass, field
from urllib.parse import urljoin, urlsplit, urlunsplit, quote
from loguru import logger

from bs4 import BeautifulSoup
from crawl4ai.markdown_generation_strategy import DefaultMarkdownGenerator
from app.utils.html_preprocess import preprocess_code_blocks


# ============================================================
# Result Type
# ============================================================

@dataclass
class ProcessResult:
    """Content Agent 处理结果"""
    cleaned_markdown: str
    original_markdown: str
    common_fields: dict
    extension_fields: dict
    ops_log: list
    # Pipeline metadata
    fetch_source: str = ""
    selector: str = ""
    cover_url: str = ""
    llm_calls: int = 0


# ============================================================
# Constants
# ============================================================

_CONTENT_SELECTOR_CANDIDATES = [
    # Platform-specific (高优先级)
    "article.tl_article_content",   # Telegraph
    ".Post-RichTextContainer",      # Zhihu
    ".rich_media_content",          # WeChat
    # Common patterns
    ".post-content",
    ".article-content",
    ".entry-content",
    "#article-content",
    ".article-body",
    ".post-body",
    ".story-body",
    # Generic fallback
    "main article",
    "article",
]


# ============================================================
# Tool: DOM Analysis (rule-based, no LLM)
# ============================================================

def tool_analyze_dom(html: str, url: str, verbose: bool = True) -> dict:
    """
    Rule-based DOM analysis.
    Returns OG metadata, auto-detected CSS selector, DOM/image summaries (for LLM fallback).
    """
    soup = BeautifulSoup(html, "html.parser")

    # 1. OG / meta 元数据
    og = {}
    for meta in soup.find_all("meta"):
        prop = meta.get("property", "") or meta.get("name", "")
        content = meta.get("content", "")
        if content and (prop.startswith("og:") or prop.startswith("article:")):
            og[prop] = content

    # 2. 页面标题 & H1
    title_tag = soup.find("title")
    page_title = title_tag.get_text(strip=True) if title_tag else ""
    h1 = soup.find("h1")
    h1_text = ""
    if h1:
        t = h1.get_text(strip=True)
        if 3 < len(t) < 200:
            h1_text = t

    # 3. 自动检测内容选择器
    auto_selector = None
    for sel in _CONTENT_SELECTOR_CANDIDATES:
        try:
            elems = soup.select(sel)
            if len(elems) == 1 and len(elems[0].get_text(strip=True)) > 200:
                auto_selector = sel
                break
        except Exception:
            continue

    # 4. DOM + 图片摘要 (LLM targeting 备用)
    dom_summary = _build_dom_summary(soup)
    image_summary = _build_image_summary(soup, url)

    # 5. OG 封面图
    cover_url = og.get("og:image", "")
    if cover_url and not cover_url.startswith("http"):
        cover_url = urljoin(url, cover_url)

    if verbose:
        if auto_selector:
            logger.debug(f"  ✅ 自动识别选择器: {auto_selector}")
        else:
            logger.debug(f"  ⏭️  未匹配已知选择器, 需要 LLM 定标")

    return {
        "og_metadata": og,
        "page_title": page_title,
        "h1_text": h1_text,
        "auto_selector": auto_selector,
        "dom_summary": dom_summary,
        "image_summary": image_summary,
        "cover_url": cover_url,
    }


def _build_dom_summary(soup, limit: int = 200) -> str:
    """
    Smart DOM summary: prioritizes nodes with text content or structural significance.
    """
    candidates = []
    
    # 1. Identify potential content containers (block-level tags)
    for tag in soup.find_all(["article", "main", "section", "div", "header", "footer"]):
        # Skip obviously irrelevant or empty
        if tag.name == "div" and not tag.attrs:
            continue
        
        # Calculate text density/length
        text = tag.get_text(separator=" ", strip=True)
        text_len = len(text)
        
        # Heuristic scoring
        score = 0
        if tag.name in ["article", "main"]:
            score += 50
        if tag.name == "header":
            score += 20  # Often contains title/author
        if "content" in str(tag.get("class", "")) or "article" in str(tag.get("class", "")):
            score += 30
        if text_len > 500:
            score += 20
        elif text_len > 100:
            score += 10
            
        # Keep candidates with some value
        if text_len > 50 or score > 0:
            candidates.append({
                "tag": tag,
                "score": score,
                "text_len": text_len,
                "preview": text[:50].replace("\n", " ")
            })

    # 2. Sort by score and length
    candidates.sort(key=lambda x: (x["score"], x["text_len"]), reverse=True)
    
    # 3. Build summary from top candidates + specific metadata tags
    summary_lines = []
    
    # Always include Title/H1
    title = soup.find("title")
    if title:
        summary_lines.append(f"<title> → {title.get_text(strip=True)}")
    h1 = soup.find("h1")
    if h1:
        summary_lines.append(f"<h1> class='{' '.join(h1.get('class', []))}' → {h1.get_text(strip=True)[:50]}...")

    # Include explicit metadata tags if found (time, address, span, div)
    for meta_tag in soup.find_all(["time", "address", "span", "div"], limit=50):
        cls = str(meta_tag.get("class", "")).lower()
        if any(k in cls for k in ["author", "date", "time", "pub", "byline"]):
             summary_lines.append(f"<{meta_tag.name} class='{cls}'> → {meta_tag.get_text(strip=True)[:50]}")

    # Add top structural candidates
    for c in candidates[:limit]:
        t = c["tag"]
        tid = t.get("id", "")
        tcls = " ".join(t.get("class", []))
        summary_lines.append(
            f"<{t.name} id='{tid}' class='{tcls}'> (len={c['text_len']}) → \"{c['preview']}...\""
        )
        
    return "\n".join(summary_lines[:limit])


def _build_image_summary(soup, base_url: str, limit: int = 20) -> str:
    images = []
    for img in soup.find_all("img", limit=limit):
        src = img.get("src") or img.get("data-src") or img.get("data-original") or ""
        if not src or src.startswith("data:"):
            continue
        full_url = urljoin(base_url, src)
        alt = img.get("alt", "")[:30]
        classes = " ".join(img.get("class", []))
        parent = img.parent
        parent_info = ""
        if parent:
            pid = parent.get("id", "")
            pcls = " ".join(parent.get("class", []))[:40]
            parent_info = f"parent: <{parent.name} id='{pid}' class='{pcls}'>"
        w, h = img.get("width", ""), img.get("height", "")
        size = f"({w}x{h})" if w or h else ""
        images.append(
            f"- src: {full_url[:100]}... | alt: '{alt}' | class: '{classes}' | {size} | {parent_info}"
        )
    return "\n".join(images) if images else "(no images found)"


# ============================================================
# Tool: HTML → Markdown Conversion (rule-based, no LLM)
# ============================================================

def tool_convert_html(html: str, url: str, selector: str = "body", verbose: bool = True) -> str:
    """BS4 + DefaultMarkdownGenerator, with link fixing and cleanup."""
    soup = BeautifulSoup(html, "html.parser")
    try:
        target = soup.select_one(selector) if selector != "body" else None
        if not target:
            target = soup.body
        clean_html = preprocess_code_blocks(str(target))
        md_gen = DefaultMarkdownGenerator(
            options={
                "ignore_images": False,
                "escape_html": True,
                "skip_internal_links": True,
                "body_width": 0,
            }
        )
        result = md_gen.generate_markdown(clean_html)
        md = result.raw_markdown if hasattr(result, "raw_markdown") else str(result)
    except Exception as e:
        if verbose:
            logger.warning(f"  ⚠️  转换失败 ({e}), 回退 body text")
        md = soup.body.get_text() if soup.body else ""

    md = _cleanup_markdown(_fix_links(md, url))
    return md


def _fix_links(md_text: str, base_url: str) -> str:
    if not md_text:
        return ""

    def encode_url(raw_url: str) -> str:
        url = raw_url.strip().replace("\\(", "(").replace("\\)", ")")
        full_url = urljoin(base_url, url)
        try:
            parts = urlsplit(full_url)
            encoded_path = quote(parts.path, safe="/")
            encoded_query = quote(parts.query, safe="=&") if parts.query else ""
            return urlunsplit(
                (parts.scheme, parts.netloc, encoded_path, encoded_query, parts.fragment)
            )
        except Exception:
            return full_url

    url_pattern = r"(?:[^)\\]|\\.)+"
    md_text = re.sub(
        rf"!\[([^\]]*)\]\(({url_pattern})\)",
        lambda m: f"![{m.group(1)}]({encode_url(m.group(2))})",
        md_text,
    )
    md_text = re.sub(
        rf"(?<!!)\[([^\]]*)\]\(({url_pattern})\)",
        lambda m: f"[{m.group(1)}]({encode_url(m.group(2))})",
        md_text,
    )
    return md_text


def _cleanup_markdown(md_text: str) -> str:
    if not md_text:
        return ""
    md_text = re.sub(r"^(#+ .*?)#\s*$", r"\1", md_text, flags=re.MULTILINE)
    md_text = re.sub(r"^>\s*\*\s+", "- ", md_text, flags=re.MULTILINE)
    md_text = re.sub(r"^>\s*$", "", md_text, flags=re.MULTILINE)
    md_text = re.sub(r"^>\s+(\d+\.\s+)", r"\1", md_text, flags=re.MULTILINE)
    md_text = re.sub(r"^>\s+(-\s+)", r"\1", md_text, flags=re.MULTILINE)
    md_text = re.sub(r"^>\s*```", "```", md_text, flags=re.MULTILINE)
    md_text = re.sub(r"^>+\s*>", "> ", md_text, flags=re.MULTILINE)
    md_text = (
        md_text.replace("&nbsp;", " ")
        .replace("&amp;", "&")
        .replace("&lt;", "<")
        .replace("&gt;", ">")
        .replace("\ufffd", "")
    )
    md_text = re.sub(r"\n{3,}", "\n\n", md_text)
    md_text = re.sub(r"(\n- [^\n]+)\n{2,}(- )", r"\1\n\2", md_text)
    md_text = re.sub(r"(\n\d+\. [^\n]+)\n{2,}(\d+\. )", r"\1\n\2", md_text)
    return md_text.strip()


# ============================================================
# LLM: Selector Targeting (fallback when auto-detect fails)
# ============================================================

_TARGETING_PROMPT = """You are an expert at analyzing web page structure for content extraction.
Find CSS selectors for the MAIN article content. Return valid JSON only.

URL: {url}

HTML Structure:
{dom_summary}

Images:
{image_summary}

Return:
{{
  "content_selector": "CSS selector for main article body",
  "cover_image_url": "URL of cover/hero image or null",
  "reasoning": "Brief explanation"
}}

Rules:
- Choose tightest container around article text
- Exclude nav/sidebar/ads/comments
- Prefer id/class selectors over tag-only
- Cover image: large hero/banner/featured image at top

JSON:"""


async def llm_target_selector(
    url: str, dom_info: dict, llm_config: dict, verbose: bool = True
) -> dict:
    """Lightweight LLM call for CSS selector. Only used when auto-detect fails."""
    from openai import OpenAI

    model = llm_config["provider"].split("/")[-1]
    client = OpenAI(api_key=llm_config["api_token"], base_url=llm_config["base_url"])

    prompt = _TARGETING_PROMPT.format(
        url=url,
        dom_summary=dom_info["dom_summary"],
        image_summary=dom_info["image_summary"],
    )

    if verbose:
        logger.debug(f"  🎯 LLM 定标 ({model})...")

    try:
        resp = client.chat.completions.create(
            model=model,
            messages=[{"role": "user", "content": prompt}],
        )
        content = resp.choices[0].message.content or ""
        match = re.search(r"\{.*\}", content, re.DOTALL)
        if match:
            result = json.loads(match.group())
            if verbose:
                logger.info(f"  ✅ 选择器: {result.get('content_selector', 'body')}")
            return result
    except Exception as e:
        if verbose:
            logger.warning(f"  ⚠️  定标失败: {e}")

    return {"content_selector": "body"}


# ============================================================
# Layer 1: Structural Scan
# ============================================================

_LAYER1_SYSTEM = """You are a document structure analyzer. Given the first and last lines of a markdown article (with line numbers), identify where the article body starts and ends, and locate metadata blocks.

## Header region (before body) — lines to remove:
- Platform banners, breadcrumbs, navigation
- Author/editor bylines: "作者|xxx", "By xxx", "编辑|xxx"
- Date/time stamps, publication info
- Stats blocks: view/like/share counts
- Source citations, archive cards

## Footer region (after body) — lines to remove:
- Related articles, "Read more", "推荐阅读"
- Comment sections
- Social sharing widgets, subscription prompts
- Site navigation, copyright notices
- "Load more" buttons

## Metadata blocks — extractable info within header/footer:
- Byline blocks (author, editor names)
- Stats blocks (view/like/share/comment counts)
- Tag/category blocks
- Copyright/source blocks

## What IS article body (keep these):
- The main # title heading
- All paragraphs, quotes, lists
- Images ![](url) and captions (◎, ▲, △, Photo:, 图源:)
- Sub-headings ## ###
- Code blocks

## Rules:
- CONSERVATIVE: when unsure, include lines in the body
- If no clear header/footer, body starts at line 1 / ends at last line
- Tag lists at the very end: mark them as a metadata_block (type=tags) so we can extract the tags, but set body_end_line BEFORE them

Return JSON ONLY:"""

_LAYER1_USER = """Total: {total_lines} lines

{preview}

Return:
{{
  "body_start_line": <first line of article body>,
  "body_end_line": <last line of article body>,
  "metadata_blocks": [
    {{
      "start_line": <int>,
      "end_line": <int>,
      "location": "header|footer",
      "type": "byline|stats|tags|navigation|related|copyright|other",
      "hint": "brief content description"
    }}
  ]
}}
JSON:"""


def _build_scan_preview(lines: list[str], window: int = 40) -> str:
    """Build first/last N lines preview for Layer 1."""
    total = len(lines)

    def fmt(idx: int, line: str) -> str:
        s = line.strip()
        if len(s) > 120:
            return f"{idx + 1}: {s[:100]}..."
        return f"{idx + 1}: {line}"

    if total <= window * 2 + 10:
        return "\n".join(fmt(i, l) for i, l in enumerate(lines))

    head = "\n".join(fmt(i, l) for i, l in enumerate(lines[:window]))
    tail = "\n".join(
        fmt(i, l) for i, l in enumerate(lines[-window:], total - window)
    )
    omitted = total - window * 2
    return (
        f"{head}\n\n"
        f"... ({omitted} lines of article body omitted, lines {window + 1}-{total - window}) ...\n\n"
        f"{tail}"
    )


async def layer1_scan(
    markdown: str, llm_config: dict, verbose: bool = True
) -> dict:
    """
    Layer 1: Structural boundary detection.
    Identifies header/footer regions and metadata block locations.
    """
    from openai import OpenAI

    model = llm_config["provider"].split("/")[-1]
    client = OpenAI(api_key=llm_config["api_token"], base_url=llm_config["base_url"])

    lines = markdown.split("\n")
    total = len(lines)
    preview = _build_scan_preview(lines)

    if verbose:
        logger.debug(f"  🔍 Layer 1: 结构扫描 ({total} 行, {model})...")

    messages = [
        {"role": "system", "content": _LAYER1_SYSTEM},
        {"role": "user", "content": _LAYER1_USER.format(total_lines=total, preview=preview)},
    ]

    try:
        resp = client.chat.completions.create(model=model, messages=messages)
        msg = resp.choices[0].message

        content = msg.content or ""
        match = re.search(r"\{.*\}", content, re.DOTALL)
        if match:
            result = json.loads(match.group())
            # Sanitize boundaries
            result["body_start_line"] = max(1, min(result.get("body_start_line", 1), total))
            result["body_end_line"] = max(
                result["body_start_line"],
                min(result.get("body_end_line", total), total),
            )

            if verbose:
                start = result["body_start_line"]
                end = result["body_end_line"]
                blocks = result.get("metadata_blocks", [])
                logger.info(f"  ✅ 正文范围: 行 {start}-{end} ({end - start + 1} 行)")
            return result
    except Exception as e:
        if verbose:
            logger.warning(f"  ⚠️  Layer 1 失败: {e}")

    return {"body_start_line": 1, "body_end_line": len(lines), "metadata_blocks": []}


# ============================================================
# Layer 2: Extract + Clean
# ============================================================

_LAYER2_SYSTEM = """You are a metadata extraction and content cleaning expert.

You receive:
1. Metadata block texts extracted from the article's header/footer
2. The article body content (with line numbers)

## Tasks:

### A. Extract metadata from the provided blocks
Map to these database fields:

**Common fields** (→ content table):
- title — article title
- author_name — real person name (NOT column/program name)
- author_id — platform-specific ID if visible
- author_avatar_url — URL of author's profile picture
- published_at — normalize to ISO 8601 YYYY-MM-DD HH:MM:SS (or just YYYY-MM-DD)
- cover_url — hero/cover image URL
- view_count, like_count, collect_count, share_count, comment_count — integers

**Extension fields** (→ archive_metadata JSON):
- editor, source, source_url, category, copyright, collection
- original_author, column_name, photographer, disclaimer

### B. Scan article body for remaining inline issues
- Standalone navigation links, edit/publish buttons, ad remnants
- Mark specific line numbers for removal

### C. Fix headings in the body
- Standalone bold (**text**) functioning as section dividers → promote to ## or ###
- Duplicate # headings (only one # per article) → demote to ##
- Do NOT touch correctly-formatted ## or ### headings

## Rules:
- When multiple author candidates exist: author_name = person, column_name = program
- Be CONSERVATIVE — never remove article body paragraphs
- Images and their captions are CONTENT — never remove
- Stats values → integers only
- Only include fields with actual non-null values
- The title from the body's first # heading should be extracted as common_fields.title

Return JSON ONLY:"""

_LAYER2_USER = """## Metadata Blocks:

{metadata_section}

## Article Body ({body_line_count} lines):

{body_preview}

Return:
{{
  "common_fields": {{
    "title": "...",
    "author_name": "person name or null",
    "author_avatar_url": "url or null",
    "published_at": "YYYY-MM-DD or null",
    "cover_url": "url or null",
    "view_count": "integer or null",
    "like_count": "integer or null",
    "collect_count": "integer or null",
    "share_count": "integer or null",
    "comment_count": "integer or null"
  }},
  "extension_fields": {{
    "editor": "...",
    "source": "...",
    "column_name": "..."
  }},
  "tags": ["tag1", "tag2"],
  "heading_fixes": [
    {{"line": 27, "level": 2, "text": "clean heading text without ** markers"}}
  ],
  "lines_to_remove": [55, 56],
  "summary": "brief description"
}}
JSON:"""


def _build_metadata_section(lines: list[str], blocks: list[dict], dom_info: dict = None) -> str:
    """Extract and format metadata block texts for Layer 2."""
    sections = []
    
    if dom_info:
        meta_lines = []
        if dom_info.get("page_title"):
            meta_lines.append(f"Page Title: {dom_info['page_title']}")
        if dom_info.get("og_metadata"):
            for k, v in dom_info["og_metadata"].items():
                meta_lines.append(f"OG Meta {k}: {v}")
        if dom_info.get("image_summary") and dom_info["image_summary"] != "(no images found)":
            meta_lines.append(f"Important Images:\n{dom_info['image_summary']}")
        
        if meta_lines:
            sections.append(
                f"### Global Page Meta & Images (From full HTML)\n```\n" + "\n".join(meta_lines) + "\n```"
            )

    if not blocks and not sections:
        return "(no metadata blocks identified)"

    for i, block in enumerate(blocks):
        start = block.get("start_line", 1) - 1
        end = block.get("end_line", 1)
        location = block.get("location", "?")
        block_type = block.get("type", "?")
        hint = block.get("hint", "")

        block_lines = []
        for j in range(start, min(end, len(lines))):
            block_lines.append(lines[j])
        text = "\n".join(block_lines)

        sections.append(
            f"### Block {i + 1} [{location}] type={block_type}: {hint}\n```\n{text}\n```"
        )

    return "\n\n".join(sections)


def _build_body_preview(lines: list[str], body_start: int, body_end: int) -> str:
    """Build numbered body preview for Layer 2."""
    result = []
    for i in range(body_start - 1, min(body_end, len(lines))):
        line = lines[i]
        s = line.strip()
        is_structural = s.startswith(("#", "!", "**", "◎", "▲", "△", "[", "|", "---", "***"))
        if len(s) > 120 and not is_structural:
            result.append(f"{i + 1}: {s[:100]}...")
        else:
            result.append(f"{i + 1}: {line}")
    return "\n".join(result)


async def layer2_extract(
    lines: list[str],
    scan_result: dict,
    llm_config: dict,
    verbose: bool = True,
    dom_info: dict = None,
) -> Tuple[dict, dict, list, list, list, str]:
    """
    Layer 2: Metadata extraction + content cleaning.

    Returns: (common_fields, extension_fields, tags, heading_fixes, lines_to_remove, summary)
    """
    from openai import OpenAI

    model = llm_config["provider"].split("/")[-1]
    client = OpenAI(api_key=llm_config["api_token"], base_url=llm_config["base_url"])

    body_start = scan_result.get("body_start_line", 1)
    body_end = scan_result.get("body_end_line", len(lines))
    blocks = scan_result.get("metadata_blocks", [])

    body_line_count = body_end - body_start + 1
    metadata_section = _build_metadata_section(lines, blocks, dom_info)
    
    # Token Optimization: Truncate middle of very long bodies for Layer 2 context
    # Layer 2 needs header/footer context for metadata, but not the full middle text.
    if body_line_count > 600:
        head_preview = _build_body_preview(lines, body_start, body_start + 200)
        tail_preview = _build_body_preview(lines, body_end - 200, body_end)
        body_preview = (
            f"{head_preview}\n\n"
            f"... (middle {body_line_count - 400} lines omitted for efficiency) ...\n\n"
            f"{tail_preview}"
        )
    else:
        body_preview = _build_body_preview(lines, body_start, body_end)

    if verbose:
        logger.debug(
            f"  🔍 Layer 2: 提取+清洗 "
            f"({body_line_count} 行正文, {len(blocks)} 个元数据块, {model})..."
        )

    messages = [
        {"role": "system", "content": _LAYER2_SYSTEM},
        {
            "role": "user",
            "content": _LAYER2_USER.format(
                metadata_section=metadata_section,
                body_preview=body_preview,
                body_line_count=body_line_count,
            ),
        },
    ]

    try:
        resp = client.chat.completions.create(model=model, messages=messages)
        msg = resp.choices[0].message

        content = msg.content or ""
        match = re.search(r"\{.*\}", content, re.DOTALL)
        if match:
            result = json.loads(match.group())

            # Parse common fields
            common_fields = {}
            for k, v in result.get("common_fields", {}).items():
                if v and str(v).lower() not in ("null", "none"):
                    if k.endswith("_count"):
                        digits = re.sub(r"[^\d]", "", str(v))
                        if digits:
                            common_fields[k] = int(digits)
                    else:
                        common_fields[k] = v

            # Parse extension fields
            extension_fields = {}
            for k, v in result.get("extension_fields", {}).items():
                if v and str(v).lower() not in ("null", "none"):
                    extension_fields[k] = v

            tags = result.get("tags", [])
            heading_fixes = result.get("heading_fixes", [])
            lines_to_remove = result.get("lines_to_remove", [])
            summary = result.get("summary", "")

            if verbose:
                logger.info(
                    f"  ✅ 提取: {len(common_fields)} 通用字段, "
                    f"{len(extension_fields)} 扩展字段, {len(tags)} 标签"
                )

            return common_fields, extension_fields, tags, heading_fixes, lines_to_remove, summary
    except Exception as e:
        if verbose:
            logger.warning(f"  ⚠️  Layer 2 失败: {e}")

    return {}, {}, [], [], [], ""


# ============================================================
# Apply Results
# ============================================================

def _apply_results(
    lines: list[str],
    scan_result: dict,
    heading_fixes: list,
    body_lines_to_remove: list,
) -> str:
    """Apply Layer 1 boundaries + Layer 2 fixes to produce clean markdown."""
    body_start = scan_result.get("body_start_line", 1)
    body_end = scan_result.get("body_end_line", len(lines))

    remove_set = set()
    replace_map = {}

    # 1. Remove header region
    for i in range(0, body_start - 1):
        remove_set.add(i)

    # 2. Remove footer region
    for i in range(body_end, len(lines)):
        remove_set.add(i)

    # 3. Remove Layer 2's inline noise lines
    for ln in body_lines_to_remove:
        if 0 <= ln - 1 < len(lines):
            remove_set.add(ln - 1)

    # 4. Heading fixes
    for h in heading_fixes:
        idx = h.get("line", 0) - 1
        level = h.get("level", 2)
        text = h.get("text", "")
        if 0 <= idx < len(lines) and text:
            replace_map[idx] = f"{'#' * level} {text}"

    # 5. Build output
    new_lines = []
    prev_removed = False
    for i, line in enumerate(lines):
        if i in remove_set:
            prev_removed = True
            continue
        if i in replace_map:
            if prev_removed and new_lines and new_lines[-1].strip():
                new_lines.append("")
            new_lines.append(replace_map[i])
            prev_removed = False
        else:
            if prev_removed and new_lines and new_lines[-1].strip() and line.strip():
                new_lines.append("")
            new_lines.append(line)
            prev_removed = False

    result = "\n".join(new_lines)
    result = re.sub(r"\n{3,}", "\n\n", result)
    return result.strip()


# ============================================================
# Orchestrator
# ============================================================

async def process_content(
    url: str,
    fetch_result,
    llm_config: dict,
    verbose: bool = True,
) -> ProcessResult:
    """
    Full pipeline orchestrator.

    Markdown path: layer1 → layer2 (2 LLM calls)
    HTML path: (auto|llm) targeting → convert → layer1 → layer2 (2-3 LLM calls)
    """
    llm_calls = 0
    selector = ""
    cover_url = ""
    dom_info = {}

    if fetch_result.content_type == "markdown":
        # ═══ Markdown Path: skip DOM analysis + conversion ═══
        if verbose:
            logger.debug(f"  📄 Markdown 路径 (跳过 DOM 分析和转换)")
        markdown = _cleanup_markdown(fetch_result.content)
        selector = "(markdown path — no selector)"

    else:
        # ═══ HTML Path: analyze → target → convert ═══
        html = fetch_result.html or fetch_result.content

        # Tool: DOM analysis
        if verbose:
            logger.debug(f"  🔧 Tool: DOM 分析...")
        dom_info = tool_analyze_dom(html, url, verbose)
        cover_url = dom_info.get("cover_url", "")

        # Selector: auto or LLM fallback
        auto_sel = dom_info.get("auto_selector")
        if auto_sel:
            selector = auto_sel
        else:
            targeting = await llm_target_selector(url, dom_info, llm_config, verbose)
            selector = targeting.get("content_selector", "body")
            cover_url = cover_url or targeting.get("cover_image_url", "") or ""
            llm_calls += 1

        # Tool: HTML → Markdown
        if verbose:
            logger.debug(f"  🔧 Tool: HTML → Markdown (selector: {selector})...")
        markdown = tool_convert_html(html, url, selector, verbose)

    # ═══ Layer 1: Structural Scan ═══
    scan_result = await layer1_scan(markdown, llm_config, verbose)
    llm_calls += 1

    # ═══ Layer 2: Extract + Clean ═══
    lines = markdown.split("\n")
    common_fields, extension_fields, tags, heading_fixes, body_removals, summary = (
        await layer2_extract(lines, scan_result, llm_config, verbose, dom_info=dom_info)
    )
    llm_calls += 1

    # Merge tags & cover
    if tags:
        common_fields["source_tags"] = tags
    if cover_url and "cover_url" not in common_fields:
        common_fields["cover_url"] = cover_url

    # ═══ Apply ═══
    cleaned = _apply_results(lines, scan_result, heading_fixes, body_removals)

    # Build ops log
    ops_log = []
    body_start = scan_result.get("body_start_line", 1)
    body_end = scan_result.get("body_end_line", len(lines))
    if body_start > 1:
        ops_log.append({"op": "remove_header", "lines": f"1-{body_start - 1}"})
    if body_end < len(lines):
        ops_log.append({"op": "remove_footer", "lines": f"{body_end + 1}-{len(lines)}"})
    for block in scan_result.get("metadata_blocks", []):
        ops_log.append({"op": "metadata_block", **block})
    for k, v in common_fields.items():
        ops_log.append({"op": "extract_common", "field": k, "value": str(v)[:60]})
    for k, v in extension_fields.items():
        ops_log.append({"op": "extract_extension", "field": k, "value": str(v)[:60]})
    for h in heading_fixes:
        ops_log.append({"op": "heading_fix", **h})
    for ln in body_removals:
        ops_log.append({"op": "remove_body_line", "line": ln})

    return ProcessResult(
        cleaned_markdown=cleaned,
        original_markdown=markdown,
        common_fields=common_fields,
        extension_fields=extension_fields,
        ops_log=ops_log,
        fetch_source=fetch_result.source,
        selector=selector,
        cover_url=common_fields.get("cover_url", cover_url),
        llm_calls=llm_calls,
    )
