import pytest
import os
import asyncio
import sqlite3
from unittest.mock import patch, AsyncMock
from pydantic import SecretStr

# 1. Force the correct DB path
DB_PATH = "./backend/data/vaultstream.db"

def get_keys_manually():
    """Manually extract keys from DB using sqlite3 to bypass app logic issues"""
    if not os.path.exists(DB_PATH):
        return None, None, None
    
    conn = sqlite3.connect(DB_PATH)
    cur = conn.cursor()
    try:
        api_key = cur.execute("SELECT value FROM system_settings WHERE key='text_llm_api_key'").fetchone()
        base_url = cur.execute("SELECT value FROM system_settings WHERE key='text_llm_api_base'").fetchone()
        model = cur.execute("SELECT value FROM system_settings WHERE key='text_llm_model'").fetchone()
        
        return (
            api_key[0] if api_key else None,
            base_url[0] if base_url else "https://api.deepseek.com", # Default if missing
            model[0] if model else "deepseek-chat"
        )
    finally:
        conn.close()

# Extract keys before app imports
REAL_KEY, REAL_BASE, REAL_MODEL = get_keys_manually()

# Now import app modules
from app.adapters.utils.content_agent import process_content
from app.adapters.utils.tiered_fetcher import FetchResult

# Load real HTML data for testing
DATA_DIR = os.path.join(os.path.dirname(__file__), "..", "data", "universal")
ITHOME_HTML_PATH = os.path.join(DATA_DIR, "ithome_926158.html")

def load_ithome_html():
    if os.path.exists(ITHOME_HTML_PATH):
        with open(ITHOME_HTML_PATH, "r", encoding="utf-8") as f:
            return f.read()
    return None

@pytest.mark.asyncio
async def test_content_agent_with_real_llm():
    """
    REAL LLM TEST: Manually injected keys to ensure execution.
    """
    if not REAL_KEY:
        pytest.skip(f"REAL LLM TEST SKIPPED: No API Key found in {DB_PATH}")

    print(f"\n[Real LLM Test] Using model: {REAL_MODEL}")
    print(f"[Real LLM Test] Base URL: {REAL_BASE}")

    # Prepare config dict for Crawl4AI style
    llm_config = {
        "provider": f"openai/{REAL_MODEL}",
        "api_token": REAL_KEY,
        "base_url": REAL_BASE
    }

    # Prepare real data
    html = load_ithome_html()
    url = "https://www.ithome.com/0/926/158.htm"
    
    fetch_result = FetchResult(
        url=url,
        content=html,
        content_type="html",
        source="local_file",
        status_code=200
    )

    print("\n" + ">"*20 + " PROCEEDING WITH REAL LLM CALLS " + "<"*20)
    try:
        # We also need to patch get_setting_value to prevent process_content from 
        # trying to lookup other settings from the wrong DB
        with patch("app.services.settings_service.get_setting_value", AsyncMock(return_value=None)):
            result = await process_content(url, fetch_result, llm_config, verbose=True)
        
        # Output results
        print("\n" + "="*50)
        print("REAL LLM PARSE RESULTS")
        print("="*50)
        print(f"TITLE:  {result.common_fields.get('title')}")
        print(f"AUTHOR: {result.common_fields.get('author_name')}")
        print(f"PUB_AT: {result.common_fields.get('published_at')}")
        print(f"TAGS:   {result.common_fields.get('source_tags')}")
        print(f"LLM CALLS: {result.llm_calls}")
        print("-"*50)
        print(f"CLEANED MARKDOWN (Preview):\n{result.cleaned_markdown[:800]}...")
        print("="*50)

        assert result.common_fields.get("title") is not None
        assert "Aluminium OS" in result.common_fields.get("title")
        assert result.llm_calls >= 2
        
    except Exception as e:
        print(f"\nReal LLM call failed: {e}")
        raise e

if __name__ == "__main__":
    asyncio.run(test_content_agent_with_real_llm())
