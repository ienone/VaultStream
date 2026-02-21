"""
HTML 预处理器：在传递给 DefaultMarkdownGenerator 之前，
清理代码块中的行号元素，将博客框架的代码高亮结构还原为标准 <pre><code>。
"""

from typing import Optional
from bs4 import BeautifulSoup, Tag


def preprocess_code_blocks(html: str) -> str:
    """
    预处理 HTML，移除代码块中的行号结构，还原为标准 <pre><code>。

    处理以下结构：
    1. figure.highlight > table > tr > td.gutter + td.code  (Hexo)
    2. figure.highlight > div.gutter + div.code              (Hexo 变体)
    3. div.highlight > table > tr > td.lntd(line-number) + td.lntd(code)  (Hugo)
    4. pre > code > table.hljs-ln > tr > td.hljs-ln-numbers + td.hljs-ln-code (highlight.js)
    5. pre.line-numbers > code + span.line-numbers-rows      (Prism.js)
    """
    soup = BeautifulSoup(html, "html.parser")
    changed = False

    # --- 规则 1: figure.highlight 包含 table 或 div 结构 (Hexo) ---
    for figure in soup.select("figure.highlight"):
        lang = _extract_lang_from_class(figure)
        code_text = _extract_code_from_gutter_structure(figure)
        if code_text is not None:
            _replace_with_pre_code(soup, figure, code_text, lang)
            changed = True

    # --- 规则 2: Hugo highlight (div.highlight > table > td.lntd) ---
    for div in soup.select("div.highlight"):
        table = div.find("table")
        if not table:
            continue
        tds = table.find_all("td", class_="lntd")
        if len(tds) == 2:
            code_td = tds[1]
            code_el = code_td.find("code")
            lang = ""
            if code_el:
                lang = _extract_lang_from_class(code_el) or code_el.get("data-lang", "")
            code_text = _extract_lines_text(code_td)
            if code_text:
                _replace_with_pre_code(soup, div, code_text, lang)
                changed = True

    # --- 规则 3: highlight.js 的 table.hljs-ln (在 pre > code 内部) ---
    for table in soup.select("table.hljs-ln"):
        parent_pre = table.find_parent("pre")
        if not parent_pre:
            continue
        parent_code = table.find_parent("code")
        lang = ""
        if parent_code:
            lang = _extract_lang_from_class(parent_code)
        lines = []
        for row in table.find_all("tr"):
            code_cell = row.select_one("td.hljs-ln-code")
            if code_cell:
                lines.append(code_cell.get_text())
        if lines:
            code_text = "\n".join(lines)
            _replace_with_pre_code(soup, parent_pre, code_text, lang)
            changed = True

    # --- 规则 4: Prism.js line-numbers-rows ---
    for span in soup.select("span.line-numbers-rows"):
        span.decompose()
        changed = True

    # --- 规则 5: 通用清理 - .lineno, .line-number 残留 ---
    for elem in soup.select(".lineno, .line-number"):
        elem.decompose()
        changed = True

    return str(soup) if changed else html


# ==================== 辅助函数 ====================

def _extract_lang_from_class(tag: Tag) -> str:
    """从标签的 class 列表中提取编程语言名称。"""
    if not tag or not tag.get("class"):
        return ""
    for cls in tag.get("class", []):
        if cls in ("highlight", "hljs"):
            continue
        for prefix in ("language-", "lang-", "hljs-", "highlight-"):
            if cls.startswith(prefix):
                return cls[len(prefix):]
        # Hexo 直接用语言名作为 class (如 figure.highlight.c)
        if cls.isalpha() and len(cls) <= 12:
            return cls
    return ""


def _extract_code_from_gutter_structure(container: Tag) -> Optional[str]:
    """
    从含有 gutter + code 的结构（table 或 div）中提取纯代码文本。
    先查 table 结构，再查 div 结构。
    返回 None 表示不匹配。
    """
    # table 方式 (Hexo 最常见)
    table = container.find("table")
    if table:
        gutter = table.select_one("td.gutter")
        code_td = table.select_one("td.code")
        if code_td:
            if gutter:
                gutter.decompose()
            return _extract_lines_text(code_td)

    # div 方式 (Hexo 变体)
    gutter = container.select_one(".gutter")
    code_div = container.select_one(".code")
    if code_div:
        if gutter:
            gutter.decompose()
        return _extract_lines_text(code_div)

    return None


def _extract_lines_text(container: Tag) -> str:
    """
    从代码容器中提取文本，尊重 <span class="line"> 的行结构。
    每个 line span 内的所有文本拼接为一行，各 line span 之间用换行分隔。
    如果没有 line span，则按 <br> 分割或直接获取文本。
    """
    # 尝试找 span.line 元素（Hexo 的标准结构）
    line_spans = container.select("span.line")
    if line_spans:
        lines = []
        for span in line_spans:
            line_text = span.get_text()
            lines.append(line_text.rstrip())
        return "\n".join(lines)

    # 没有 span.line，尝试用 <br> 分隔
    pre = container.find("pre")
    target = pre if pre else container

    # 将 <br> 替换为换行标记再提取
    for br in target.find_all("br"):
        br.replace_with("\n")

    text = target.get_text()
    lines = []
    for line in text.split("\n"):
        stripped = line.rstrip()
        if stripped:
            lines.append(stripped)
    return "\n".join(lines)


def _replace_with_pre_code(soup: BeautifulSoup, original: Tag, code_text: str, lang: str = ""):
    """用标准的 <pre><code> 替换原始标签。"""
    pre = soup.new_tag("pre")
    code_attrs = {}
    if lang:
        code_attrs["class"] = f"language-{lang}"
    code = soup.new_tag("code", **code_attrs)
    code.string = code_text
    pre.append(code)
    original.replace_with(pre)
