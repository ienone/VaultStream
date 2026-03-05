import pytest
import os
from app.adapters.utils.content_agent import (
    tool_analyze_dom, 
    _build_dom_summary, 
    tool_convert_html,
    _cleanup_markdown
)

# Load real HTML data for testing
DATA_DIR = os.path.join(os.path.dirname(__file__), "..", "data", "universal")
ITHOME_HTML_PATH = os.path.join(DATA_DIR, "ithome_926158.html")

def load_ithome_html():
    if os.path.exists(ITHOME_HTML_PATH):
        with open(ITHOME_HTML_PATH, "r", encoding="utf-8") as f:
            return f.read()
    return None

def test_tool_analyze_dom_ithome():
    """Test DOM analysis with a real ITHome article"""
    html = load_ithome_html()
    if not html:
        pytest.skip("ITHome test data not found")
        
    url = "https://www.ithome.com/0/926/158.htm"
    result = tool_analyze_dom(html, url)
    
    # IT之家 in this sample doesn't have OG tags in head
    assert result["page_title"] is not None
    assert "Aluminium OS" in result["page_title"]
    
    # Verify auto selector found the main content container
    # IT之家 uses <div class="post_content" id="paragraph">
    assert result["auto_selector"] in ["#paragraph", ".post_content", "article", ".post_content "]

def test_tool_convert_html_ithome():
    """Test HTML to Markdown conversion with real content"""
    html = load_ithome_html()
    if not html:
        pytest.skip("ITHome test data not found")
        
    url = "https://www.ithome.com/0/926/158.htm"
    # Use detected selector or fallback
    dom_info = tool_analyze_dom(html, url)
    selector = dom_info["auto_selector"] or "body"
    
    markdown = tool_convert_html(html, url, selector)
    
    assert markdown is not None
    assert len(markdown) > 500
    # Check if images are preserved and links fixed
    assert "![" in markdown
    assert "https://" in markdown

def test_cleanup_markdown_logic():
    """Test markdown cleanup regexes"""
    dirty_md = """
# Title #
> * List item in quote
> 
> 1. Numbered in quote
> ```python
> print(1)
> ```

Text with &nbsp; and \ufffd.


Multiple newlines.
    """
    cleaned = _cleanup_markdown(dirty_md)
    
    assert "# Title" in cleaned
    assert "Title #" not in cleaned
    assert "- List item" in cleaned
    assert "1. Numbered" in cleaned
    assert "```python" in cleaned
    assert "&nbsp;" not in cleaned
    assert "\ufffd" not in cleaned
    assert "\n\n\n" not in cleaned

def test_tool_analyze_dom_basic():
    html = """
    <html>
        <head>
            <title>Test Page</title>
            <meta property="og:title" content="OG Title">
            <meta property="og:image" content="http://example.com/image.jpg">
        </head>
        <body>
            <h1>Main Heading</h1>
            <article class="tl_article_content">
                <p>This is a long paragraph that should trigger the auto selector. 
                It needs to be more than 200 characters long to be detected by the current logic.
                Adding more text here to ensure it reaches the length requirement. 
                Almost there, just a bit more text to be absolutely sure.
                Done!</p>
            </article>
        </body>
    </html>
    """
    url = "http://example.com/test"
    result = tool_analyze_dom(html, url)
    
    assert result["page_title"] == "Test Page"
    assert result["og_metadata"]["og:title"] == "OG Title"
    assert result["cover_url"] == "http://example.com/image.jpg"
    assert result["h1_text"] == "Main Heading"
    assert result["auto_selector"] == "article.tl_article_content"

def test_tool_analyze_dom_no_selector():
    html = """
    <html>
        <body>
            <div>Short text</div>
        </body>
    </html>
    """
    result = tool_analyze_dom(html, "http://test.com")
    assert result["auto_selector"] is None

def test_build_dom_summary():
    from bs4 import BeautifulSoup
    html = """
    <div>
        <article id="main">
            <p>Important text</p>
        </article>
        <footer class="side">
            <p>Irrelevant footer</p>
        </footer>
    </div>
    """
    soup = BeautifulSoup(html, "html.parser")
    summary = _build_dom_summary(soup)
    assert "article" in summary
    assert "main" in summary
