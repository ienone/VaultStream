import pytest
import os
from dotenv import load_dotenv
from app.adapters.universal_adapter import UniversalAdapter

# 显式加载 .env，确保环境变量可用
load_dotenv()

# 只有在配置了 LLM Key 时才运行这些测试，避免 CI 报错
@pytest.mark.skipif(not os.getenv("TEXT_LLM_API_KEY") and not os.getenv("VISION_LLM_API_KEY"), reason="LLM API Key not configured")
@pytest.mark.asyncio
class TestUniversalAdapter:
    
    async def test_zhihu_article(self):
        """测试知乎专栏 (图文提取 + 统计数据)"""
        url = "https://zhuanlan.zhihu.com/p/2000848771446219463"
        adapter = UniversalAdapter()
        result = await adapter.parse(url)
        
        print(f"\n[Zhihu] Title: {result.title}")
        print(f"[Zhihu] Author: {result.author_name}")
        print(f"[Zhihu] Stats: {result.stats}")
        
        assert result.title is not None
        assert "Content" not in result.title # 确保不是默认标题
        assert len(result.description) > 100

    async def test_blog_post(self):
        """测试标准博客 (Saku Best)"""
        url = "https://saku.best/archives/dia.html"
        adapter = UniversalAdapter()
        result = await adapter.parse(url)
        
        print(f"\n[Blog] Title: {result.title}")
        print(f"[Blog] Summary: {result.raw_metadata.get('summary')}")
        
        assert result.title is not None
        assert result.platform == "universal"

    async def test_twitter_post(self):
        """测试 Twitter (需本地 Chrome 配合，否则可能只能拿到登录页)"""
        if not os.getenv("CHROME_USER_DATA_DIR"):
            pytest.skip("Skipping Twitter test: CHROME_USER_DATA_DIR not set")
            
        url = "https://x.com/i/status/2017179732194824656"
        adapter = UniversalAdapter()
        result = await adapter.parse(url)
        
        print(f"\n[Twitter] Content: {result.description[:50]}...")
        print(f"[Twitter] Media: {result.media_urls}")
        
        # 如果突破了登录墙，应该能拿到正文
        assert "登录" not in result.title
        
    async def test_weibo_post(self):
        """测试微博 (动态页面)"""
        url = "https://weibo.com/6220589166/QpyYy9Gfe"
        adapter = UniversalAdapter()
        result = await adapter.parse(url)
        
        print(f"\n[Weibo] Author: {result.author_name}")
        print(f"[Weibo] Content: {result.description[:50]}...")
        
        assert result.description is not None