import pytest
import os
from unittest.mock import patch, MagicMock
from dotenv import load_dotenv
from app.adapters.universal_adapter import UniversalAdapter

# 显式加载 .env，确保环境变量可用
load_dotenv()

# Mock get_setting_value to avoid DB calls
async def mock_get_setting_value(key, default):
    return default

# 只有在配置了 LLM Key 时才运行这些测试，避免 CI 报错
@pytest.mark.skipif(not os.getenv("TEXT_LLM_API_KEY") and not os.getenv("VISION_LLM_API_KEY"), reason="LLM API Key not configured")
@pytest.mark.asyncio
class TestUniversalAdapter:
    
    async def test_zhihu_article(self):
        """测试知乎专栏 (图文提取 + 统计数据)"""
        url = "https://zhuanlan.zhihu.com/p/2000848771446219463"
        adapter = UniversalAdapter()
        
        with patch('app.services.settings_service.get_setting_value', side_effect=mock_get_setting_value):
            result = await adapter.parse(url)
        
        print(f"\n[Zhihu] Title: {result.title}")
        print(f"[Zhihu] Author: {result.author_name}")
        print(f"[Zhihu] Stats: {result.stats}")
        print(f"[Zhihu] Cover: {result.cover_url}")
        
        assert result.title is not None
        assert "Content" not in result.title # 确保不是默认标题
        assert len(result.description) > 100
        assert result.layout_type == "article"
        # Check if cover_url is populated (either from LLM or fallback)
        if result.media_urls:
            assert result.cover_url is not None

    async def test_blog_post(self):
        """测试标准博客 (Saku Best)"""
        url = "https://saku.best/archives/dia.html"
        adapter = UniversalAdapter()
        
        with patch('app.services.settings_service.get_setting_value', side_effect=mock_get_setting_value):
            result = await adapter.parse(url)
        
        print(f"\n[Blog] Title: {result.title}")
        print(f"[Blog] Summary: {result.archive_metadata.get('summary')}")
        
        assert result.title is not None
        assert result.platform == "universal"
        assert result.layout_type == "article"

    async def test_twitter_post(self):
        """测试 Twitter (需本地 Chrome 配合，否则可能只能拿到登录页)"""
        if not os.getenv("CHROME_USER_DATA_DIR"):
            pytest.skip("Skipping Twitter test: CHROME_USER_DATA_DIR not set")
            
        url = "https://x.com/i/status/2017179732194824656"
        adapter = UniversalAdapter()
        
        with patch('app.services.settings_service.get_setting_value', side_effect=mock_get_setting_value):
            result = await adapter.parse(url)
        
        print(f"\n[Twitter] Content: {result.description[:50]}...")
        print(f"\n[Twitter] Layout: {result.layout_type}")
        print(f"[Twitter] Media: {result.media_urls}")
        
        # 如果突破了登录墙，应该能拿到正文
        assert "登录" not in result.title
        assert result.layout_type in ["gallery", "article"]
        
    async def test_weibo_post(self):
        """测试微博 (动态页面)"""
        url = "https://weibo.com/6220589166/QpyYy9Gfe"
        adapter = UniversalAdapter()
        
        with patch('app.services.settings_service.get_setting_value', side_effect=mock_get_setting_value):
            result = await adapter.parse(url)
        
        print(f"\n[Weibo] Author: {result.author_name}")
        print(f"[Weibo] Content: {result.description[:50]}...")
        print(f"[Weibo] Layout: {result.layout_type}")
        
        assert result.description is not None
        assert result.layout_type in ["gallery", "article"]