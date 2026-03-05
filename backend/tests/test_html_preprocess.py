import pytest
from bs4 import BeautifulSoup

from app.utils.html_preprocess import preprocess_code_blocks, _extract_lang_from_class


class TestHexoTableStructure:
    """规则1: figure.highlight > table > tr > td.gutter + td.code"""

    def test_removes_gutter_keeps_code(self):
        html = (
            '<figure class="highlight python">'
            "<table><tr>"
            '<td class="gutter"><pre><span class="line">1</span><br>'
            '<span class="line">2</span></pre></td>'
            '<td class="code"><pre><span class="line">print("hello")</span><br>'
            '<span class="line">print("world")</span></pre></td>'
            "</tr></table></figure>"
        )
        result = preprocess_code_blocks(html)
        soup = BeautifulSoup(result, "html.parser")

        assert soup.find("td", class_="gutter") is None
        assert soup.find("figure") is None
        pre = soup.find("pre")
        assert pre is not None
        code = pre.find("code")
        assert code is not None
        assert 'print("hello")' in code.string
        assert 'print("world")' in code.string
        assert "language-python" in code.get("class", [])


class TestHexoDivStructure:
    """规则1变体: figure.highlight > div.gutter + div.code"""

    def test_removes_gutter_div_keeps_code(self):
        html = (
            '<figure class="highlight js">'
            '<div class="gutter"><pre>1\n2</pre></div>'
            '<div class="code"><pre><span class="line">const a = 1;</span><br>'
            '<span class="line">const b = 2;</span></pre></div>'
            "</figure>"
        )
        result = preprocess_code_blocks(html)
        soup = BeautifulSoup(result, "html.parser")

        assert soup.find("div", class_="gutter") is None
        assert soup.find("figure") is None
        code = soup.find("code")
        assert code is not None
        assert "const a = 1;" in code.string
        assert "const b = 2;" in code.string
        assert "language-js" in code.get("class", [])


class TestHugoHighlight:
    """规则2: div.highlight > table > td.lntd (两个)"""

    def test_removes_line_numbers_keeps_code(self):
        html = (
            '<div class="highlight">'
            "<table><tr>"
            '<td class="lntd"><pre>1\n2</pre></td>'
            '<td class="lntd"><pre><code class="language-go">'
            '<span class="line">fmt.Println("hi")</span><br>'
            '<span class="line">return nil</span>'
            "</code></pre></td>"
            "</tr></table></div>"
        )
        result = preprocess_code_blocks(html)
        soup = BeautifulSoup(result, "html.parser")

        assert soup.find("div", class_="highlight") is None
        assert soup.find("table") is None
        code = soup.find("code")
        assert code is not None
        assert 'fmt.Println("hi")' in code.string
        assert "return nil" in code.string
        assert "language-go" in code.get("class", [])


class TestHighlightjsTable:
    """规则3: pre > code > table.hljs-ln > tr > td.hljs-ln-numbers + td.hljs-ln-code"""

    def test_removes_line_number_cells(self):
        html = (
            "<pre><code>"
            '<table class="hljs-ln"><tbody>'
            '<tr><td class="hljs-ln-numbers">1</td>'
            '<td class="hljs-ln-code">x = 10</td></tr>'
            '<tr><td class="hljs-ln-numbers">2</td>'
            '<td class="hljs-ln-code">y = 20</td></tr>'
            "</tbody></table></code></pre>"
        )
        result = preprocess_code_blocks(html)
        soup = BeautifulSoup(result, "html.parser")

        assert soup.find("table") is None
        code = soup.find("code")
        assert code is not None
        assert "x = 10" in code.string
        assert "y = 20" in code.string

    def test_extracts_lang_from_parent_code(self):
        html = (
            '<pre><code class="language-ruby">'
            '<table class="hljs-ln"><tbody>'
            '<tr><td class="hljs-ln-numbers">1</td>'
            '<td class="hljs-ln-code">puts "hi"</td></tr>'
            "</tbody></table></code></pre>"
        )
        result = preprocess_code_blocks(html)
        soup = BeautifulSoup(result, "html.parser")
        code = soup.find("code")
        assert "language-ruby" in code.get("class", [])


class TestPrismjsLineNumbers:
    """规则4: pre.line-numbers > code + span.line-numbers-rows"""

    def test_removes_line_numbers_rows_span(self):
        html = (
            '<pre class="line-numbers">'
            "<code>console.log(1);\nconsole.log(2);</code>"
            '<span class="line-numbers-rows">'
            "<span></span><span></span>"
            "</span></pre>"
        )
        result = preprocess_code_blocks(html)
        soup = BeautifulSoup(result, "html.parser")

        assert soup.find("span", class_="line-numbers-rows") is None
        code = soup.find("code")
        assert code is not None
        assert "console.log(1);" in code.get_text()


class TestNoCodeBlocksUnchanged:
    def test_plain_html_unchanged(self):
        html = "<p>Hello <strong>world</strong></p>"
        result = preprocess_code_blocks(html)
        assert result == html

    def test_pre_without_special_structure_unchanged(self):
        html = "<pre><code>simple code</code></pre>"
        result = preprocess_code_blocks(html)
        assert result == html


class TestExtractLangFromClass:
    def test_language_prefix(self):
        tag = BeautifulSoup('<code class="language-python"></code>', "html.parser").find("code")
        assert _extract_lang_from_class(tag) == "python"

    def test_lang_prefix(self):
        tag = BeautifulSoup('<code class="lang-js"></code>', "html.parser").find("code")
        assert _extract_lang_from_class(tag) == "js"

    def test_hljs_prefix(self):
        tag = BeautifulSoup('<code class="hljs hljs-python"></code>', "html.parser").find("code")
        assert _extract_lang_from_class(tag) == "python"

    def test_highlight_prefix(self):
        tag = BeautifulSoup('<code class="highlight-c"></code>', "html.parser").find("code")
        assert _extract_lang_from_class(tag) == "c"

    def test_bare_language_name(self):
        tag = BeautifulSoup('<figure class="highlight python"></figure>', "html.parser").find("figure")
        assert _extract_lang_from_class(tag) == "python"

    def test_no_class_returns_empty(self):
        tag = BeautifulSoup("<code></code>", "html.parser").find("code")
        assert _extract_lang_from_class(tag) == ""

    def test_none_tag_returns_empty(self):
        assert _extract_lang_from_class(None) == ""


class TestLinenoCleanup:
    """规则5: .lineno 和 .line-number 元素被移除"""

    def test_lineno_removed(self):
        html = '<pre><span class="lineno">1</span> x = 1\n<span class="lineno">2</span> y = 2</pre>'
        result = preprocess_code_blocks(html)
        soup = BeautifulSoup(result, "html.parser")
        assert soup.find("span", class_="lineno") is None
        assert "x = 1" in result

    def test_line_number_removed(self):
        html = '<pre><span class="line-number">1</span>code here</pre>'
        result = preprocess_code_blocks(html)
        soup = BeautifulSoup(result, "html.parser")
        assert soup.find("span", class_="line-number") is None
        assert "code here" in result
