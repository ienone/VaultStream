import pytest
from app.adapters.utils.content_agent import tool_analyze_dom, _build_dom_summary

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
