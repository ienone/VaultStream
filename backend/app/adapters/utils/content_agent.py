"""
Content Agent — 2-Layer Architecture with Tool Functions

Pipeline:
  URL → tiered_fetch → raw content
    [Markdown path] — content already in Markdown
      → layer1_scan → layer2_extract → apply → result   (2 LLM)
    [Explicit article HTML] → semantic body + metadata → result (0 LLM)
    [Other HTML] — content is HTML
      → tool_analyze_dom → (auto_selector | llm_target) → tool_convert_html
      → layer1_scan → layer2_extract → apply → result   (2-3 LLM)
"""

import re
from typing import Literal
from dataclasses import dataclass
from urllib.parse import urljoin, urlsplit, urlunsplit, quote
from loguru import logger

from bs4 import BeautifulSoup
from langchain_openai import ChatOpenAI
from markdownify import markdownify
from pydantic import BaseModel, ConfigDict, Field, model_validator
from app.utils.html_preprocess import preprocess_code_blocks
from app.services.config_service import LLMConfig


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
    ".post_content",                # ITHome
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


class TargetSelection(BaseModel):
    model_config = ConfigDict(extra="forbid", strict=True, str_strip_whitespace=True)
    content_selector: str = Field(min_length=1)
    cover_image_url: str | None = None
    reasoning: str | None = None


class MetadataBlock(BaseModel):
    model_config = ConfigDict(extra="forbid", strict=True, str_strip_whitespace=True)
    start_line: int = Field(gt=0)
    end_line: int = Field(gt=0)
    location: Literal["header", "footer"]
    type: Literal["byline", "stats", "tags", "navigation", "related", "copyright", "other"]
    hint: str

    @model_validator(mode="after")
    def validate_range(self):
        if self.end_line < self.start_line:
            raise ValueError("metadata block ends before it starts")
        return self


class StructuralScan(BaseModel):
    model_config = ConfigDict(extra="forbid", strict=True)
    body_start_line: int = Field(gt=0)
    body_end_line: int = Field(gt=0)
    metadata_blocks: list[MetadataBlock]

    @model_validator(mode="after")
    def validate_range(self):
        if self.body_end_line < self.body_start_line:
            raise ValueError("article body ends before it starts")
        return self


class CommonFields(BaseModel):
    model_config = ConfigDict(extra="forbid", strict=True, str_strip_whitespace=True)
    title: str | None = None
    author_name: str | None = None
    author_id: str | None = None
    author_avatar_url: str | None = None
    published_at: str | None = None
    cover_url: str | None = None
    view_count: int | None = Field(default=None, ge=0)
    like_count: int | None = Field(default=None, ge=0)
    collect_count: int | None = Field(default=None, ge=0)
    share_count: int | None = Field(default=None, ge=0)
    comment_count: int | None = Field(default=None, ge=0)


class ExtensionFields(BaseModel):
    model_config = ConfigDict(extra="forbid", strict=True, str_strip_whitespace=True)
    editor: str | None = None
    source: str | None = None
    source_url: str | None = None
    category: str | None = None
    copyright: str | None = None
    collection: str | None = None
    original_author: str | None = None
    column_name: str | None = None
    photographer: str | None = None
    disclaimer: str | None = None


class HeadingFix(BaseModel):
    model_config = ConfigDict(extra="forbid", strict=True, str_strip_whitespace=True)
    line: int = Field(gt=0)
    level: Literal[2, 3]
    text: str = Field(min_length=1)


class ContentExtraction(BaseModel):
    model_config = ConfigDict(extra="forbid", strict=True, str_strip_whitespace=True)
    common_fields: CommonFields
    extension_fields: ExtensionFields
    tags: list[str]
    heading_fixes: list[HeadingFix]
    lines_to_remove: list[int]
    summary: str


def _content_llm(config: LLMConfig) -> ChatOpenAI:
    return ChatOpenAI(
        model=config.model,
        api_key=config.api_key,
        base_url=config.base_url,
        temperature=0,
        use_responses_api=False,
    )


async def _structured_call(llm: ChatOpenAI, schema: type[BaseModel], messages, *, timeout: float = 60):
    result = await llm.with_structured_output(
        schema, method="function_calling"
    ).ainvoke(messages, timeout=timeout)
    if result is None:
        raise ValueError(f"模型未调用结构化输出工具 {schema.__name__}")
    return result


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
            logger.debug("auto selector: {}", auto_selector)
        else:
            logger.debug("no known selector matched, fallback to LLM targeting")

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
        src = ""
        for attr in ['data-original', 'data-src', 'file', 'data-real-src', 'src']:
            val = img.get(attr)
            if val and not str(val).startswith('data:'):
                src = val
                break
        
        if not src:
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
    """BS4 + markdownify conversion, with link fixing and cleanup."""
    soup = BeautifulSoup(html, "html.parser")
    try:
        target = soup.select_one(selector) if selector != "body" else None
        if not target:
            target = soup.body
            
        # Fix lazy loading images
        if target:
            for img in target.find_all('img'):
                for attr in ['data-original', 'data-src', 'file', 'data-real-src']:
                    real_src = img.get(attr)
                    if real_src and not real_src.startswith('data:'):
                        img['src'] = real_src
                        break
                        
        clean_html = preprocess_code_blocks(str(target))
        md = markdownify(
            clean_html,
            heading_style="ATX",
            bullets="-",
            strip=["script", "style"],
        )
    except Exception as e:
        if verbose:
            logger.warning("conversion failed ({}), fallback to body text", e)
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
Find a CSS selector for the MAIN article content.

URL: {url}

HTML Structure:
{dom_summary}

Images:
{image_summary}

Rules:
- Choose tightest container around article text
- Exclude nav/sidebar/ads/comments
- Prefer id/class selectors over tag-only
- Cover image: large hero/banner/featured image at top

Return the result through the supplied structured-output tool."""


async def llm_target_selector(
    url: str, dom_info: dict, llm: ChatOpenAI, verbose: bool = True
) -> TargetSelection:
    """Lightweight LLM call for CSS selector. Only used when auto-detect fails."""
    prompt = _TARGETING_PROMPT.format(
        url=url,
        dom_summary=dom_info["dom_summary"],
        image_summary=dom_info["image_summary"],
    )

    if verbose:
        logger.debug("LLM targeting ({})", llm.model_name)
    result = await _structured_call(llm, TargetSelection, prompt)
    if verbose:
        logger.info("selector: {}", result.content_selector)
    return result


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

Return the result through the supplied structured-output tool."""

_LAYER1_USER = """Total: {total_lines} lines

{preview}"""


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
    markdown: str, llm: ChatOpenAI, verbose: bool = True
) -> StructuralScan:
    """
    Layer 1: Structural boundary detection.
    Identifies header/footer regions and metadata block locations.
    """
    lines = markdown.split("\n")
    total = len(lines)
    preview = _build_scan_preview(lines)

    if verbose:
        logger.debug("Layer 1: structural scan ({} lines, {})", total, llm.model_name)

    messages = [
        {"role": "system", "content": _LAYER1_SYSTEM},
        {"role": "user", "content": _LAYER1_USER.format(total_lines=total, preview=preview)},
    ]

    result = await _structured_call(llm, StructuralScan, messages, timeout=30)
    if result.body_end_line > total or any(block.end_line > total for block in result.metadata_blocks):
        raise ValueError("结构扫描返回了超出输入范围的行号")
    if verbose:
        logger.info("body range: L{}-L{} ({} lines)", result.body_start_line,
                    result.body_end_line, result.body_end_line - result.body_start_line + 1)
    return result


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

Return the result through the supplied structured-output tool."""

_LAYER2_USER = """## Metadata Blocks:

{metadata_section}

## Article Body ({body_line_count} lines):

{body_preview}
"""


def _build_metadata_section(lines: list[str], blocks: list[MetadataBlock], dom_info: dict = None) -> str:
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
        start = block.start_line - 1
        end = block.end_line

        block_lines = []
        for j in range(start, min(end, len(lines))):
            block_lines.append(lines[j])
        text = "\n".join(block_lines)

        sections.append(
            f"### Block {i + 1} [{block.location}] type={block.type}: {block.hint}\n```\n{text}\n```"
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
    scan_result: StructuralScan,
    llm: ChatOpenAI,
    verbose: bool = True,
    dom_info: dict = None,
) -> ContentExtraction:
    """
    Layer 2: Metadata extraction + content cleaning.

    Returns validated metadata and cleanup operations.
    """
    body_start = scan_result.body_start_line
    body_end = scan_result.body_end_line
    blocks = scan_result.metadata_blocks

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
            f"Layer 2: extract+clean "
            f"({body_line_count} 行正文, {len(blocks)} 个元数据块, {llm.model_name})..."
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

    result = await _structured_call(llm, ContentExtraction, messages)
    affected_lines = [fix.line for fix in result.heading_fixes] + result.lines_to_remove
    if any(line < body_start or line > body_end for line in affected_lines):
        raise ValueError("内容清理返回了正文范围之外的行号")
    if verbose:
        logger.info("extracted: {} common, {} ext, {} tags",
                    len(result.common_fields.model_dump(exclude_none=True)),
                    len(result.extension_fields.model_dump(exclude_none=True)), len(result.tags))
    return result


# ============================================================
# Apply Results
# ============================================================

def _apply_results(
    lines: list[str],
    scan_result: StructuralScan,
    heading_fixes: list[HeadingFix],
    body_lines_to_remove: list,
) -> str:
    """Apply Layer 1 boundaries + Layer 2 fixes to produce clean markdown."""
    body_start = scan_result.body_start_line
    body_end = scan_result.body_end_line

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
        idx = h.line - 1
        replace_map[idx] = f"{'#' * h.level} {h.text}"

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

def _extract_semantic_content(url: str, fetch_result) -> ProcessResult | None:
    """Use explicit article boundaries and metadata without rewriting the text."""
    if fetch_result.content_type != "html":
        return None
    soup = BeautifulSoup(fetch_result.html or fetch_result.content, "html.parser")
    telegraph = urlsplit(url).hostname == "telegra.ph"
    selector = "article.tl_article_content" if telegraph else '[itemprop~="articleBody"]'
    bodies = soup.select(selector)
    if len(bodies) != 1:
        return None
    body = bodies[0]
    if body.find(["iframe", "video", "audio"]):
        return None
    scope = body.find_parent(attrs={"itemscope": True})
    if not telegraph:
        article_types = {"Article", "NewsArticle", "BlogPosting", "TechArticle"}
        if not scope or not any(
            item.rsplit("/", 1)[-1] in article_types
            for item in str(scope.get("itemtype", "")).split()
        ):
            return None
        free = scope.select_one('[itemprop="isAccessibleForFree"]')
        if free and str(free.get("content", free.get_text())).lower() == "false":
            return None

    def meta(name: str) -> str | None:
        tag = soup.find("meta", attrs={"property": name}) or soup.find("meta", attrs={"name": name})
        return tag.get("content") if tag else None

    title_node = soup.select_one(".tl_article_header h1") if telegraph else scope.select_one('[itemprop="headline"]')
    title = title_node.get_text(strip=True) if title_node else meta("og:title")
    if not title:
        return None
    fields = {"title": title}
    if telegraph:
        author = soup.select_one('.tl_article_header [rel="author"]')
        date = soup.select_one('.tl_article_header time[datetime]')
        # Telegraph duplicates the heading/byline inside the editor body.
        first = body.find(recursive=False)
        if first and first.name == "h1" and first.get_text(strip=True) == title:
            first.decompose()
            first = body.find(recursive=False)
            if first and first.name == "address":
                first.decompose()
    else:
        author = scope.select_one('[itemprop="author"] [itemprop="name"]') or scope.select_one('[itemprop="author"]')
        date = scope.select_one('[itemprop="datePublished"]')
    author_name = author.get("content") or author.get_text(strip=True) if author else meta("author")
    if author_name:
        fields["author_name"] = author_name
    published = (date.get("datetime") or date.get("content")) if date else meta("article:published_time")
    if published:
        fields["published_at"] = published
    cover = meta("og:image")
    if cover:
        fields["cover_url"] = urljoin(url, cover)
    for tag in body.find_all(["script", "style", "nav", "aside", "form"]):
        tag.decompose()
    markdown = tool_convert_html(str(body), url, selector, verbose=False)
    if not markdown.strip():
        return None
    return ProcessResult(
        cleaned_markdown=markdown, original_markdown=markdown,
        common_fields=fields, extension_fields={},
        ops_log=[{"op": "extract_semantic_article", "selector": selector}],
        fetch_source=fetch_result.source, selector=selector, cover_url=fields.get("cover_url", ""),
    )


async def process_content(
    url: str,
    fetch_result,
    llm_config: LLMConfig,
    verbose: bool = True,
) -> ProcessResult:
    """
    Full pipeline orchestrator.

    Markdown path: layer1 → layer2 (2 LLM calls)
    Explicit article HTML: direct body and metadata extraction (0 LLM calls)
    Other HTML: (auto|llm) targeting → convert → layer1 → layer2 (2-3 LLM calls)
    """
    deterministic = _extract_semantic_content(url, fetch_result)
    if deterministic is not None:
        return deterministic
    if not llm_config or not llm_config.api_key:
        raise ValueError("此网页需要模型辅助解析，请配置文本模型 API Key")
    llm_calls = 0
    selector = ""
    cover_url = ""
    dom_info = {}
    llm = _content_llm(llm_config)

    if fetch_result.content_type == "markdown":
        # ═══ Markdown Path: skip DOM analysis + conversion ═══
        if verbose:
            logger.debug("markdown path (skip DOM analysis)")
        markdown = _cleanup_markdown(fetch_result.content)
        selector = "(markdown path — no selector)"

    else:
        # ═══ HTML Path: analyze → target → convert ═══
        html = fetch_result.html or fetch_result.content

        # Tool: DOM analysis
        if verbose:
            logger.debug("tool: DOM analysis")
        dom_info = tool_analyze_dom(html, url, verbose)
        cover_url = dom_info.get("cover_url", "")

        # Selector: auto or LLM fallback
        auto_sel = dom_info.get("auto_selector")
        if auto_sel:
            selector = auto_sel
        else:
            targeting = await llm_target_selector(url, dom_info, llm, verbose)
            selector = targeting.content_selector
            cover_url = cover_url or targeting.cover_image_url or ""
            llm_calls += 1

        # Tool: HTML → Markdown
        if verbose:
            logger.debug("tool: HTML->Markdown (selector: {})", selector)
        markdown = tool_convert_html(html, url, selector, verbose)

    # ═══ Layer 1: Structural Scan ═══
    scan_result = await layer1_scan(markdown, llm, verbose)
    llm_calls += 1

    # ═══ Layer 2: Extract + Clean ═══
    lines = markdown.split("\n")
    extraction = await layer2_extract(lines, scan_result, llm, verbose, dom_info=dom_info)
    common_fields = extraction.common_fields.model_dump(exclude_none=True)
    extension_fields = extraction.extension_fields.model_dump(exclude_none=True)
    tags = extraction.tags
    heading_fixes = extraction.heading_fixes
    body_removals = extraction.lines_to_remove
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
    body_start = scan_result.body_start_line
    body_end = scan_result.body_end_line
    if body_start > 1:
        ops_log.append({"op": "remove_header", "lines": f"1-{body_start - 1}"})
    if body_end < len(lines):
        ops_log.append({"op": "remove_footer", "lines": f"{body_end + 1}-{len(lines)}"})
    for block in scan_result.metadata_blocks:
        ops_log.append({"op": "metadata_block", **block.model_dump()})
    for k, v in common_fields.items():
        ops_log.append({"op": "extract_common", "field": k, "value": str(v)[:60]})
    for k, v in extension_fields.items():
        ops_log.append({"op": "extract_extension", "field": k, "value": str(v)[:60]})
    for h in heading_fixes:
        ops_log.append({"op": "heading_fix", **h.model_dump()})
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
