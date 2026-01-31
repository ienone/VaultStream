import os
import asyncio
from typing import List, Optional
from loguru import logger

# 异步环境补丁
import nest_asyncio
nest_asyncio.apply()

from browser_use import Agent, Browser, BrowserConfig
from app.core.llm_factory import LLMFactory

# 1. 禁用导致超时的扩展下载
os.environ['BROWSER_USE_DISABLE_EXTENSIONS'] = 'true'

class DiscoveryService:
    """
    发现服务 (Discovery Service)
    
    使用 browser-use (AI Agent) 自动浏览社交平台并发现高质量内容。
    依赖 Vision LLM 模型。
    """

    def __init__(self):
        # 本地 Chrome 路径和数据目录
        self.chrome_path = os.getenv("CHROME_PATH", r"C:\Program Files\Google\Chrome\Application\chrome.exe")
        self.user_data_dir = os.getenv("CHROME_USER_DATA_DIR")
        
    def _get_llm(self):
        """获取 Vision LLM 实例"""
        llm = LLMFactory.get_vision_llm()
        if not llm:
            raise ValueError("DiscoveryService requires a valid VISION_LLM configuration.")
        return llm

    async def run_task(self, task_prompt: str, headless: bool = True) -> str:
        """
        执行一个具体的发现任务。
        """
        logger.info(f"DiscoveryService: Starting task - {task_prompt}")
        
        try:
            llm = self._get_llm()
        except ValueError as e:
            logger.error(str(e))
            return str(e)
        
        # 配置浏览器
        browser_config_kwargs = {
            "headless": headless,
        }
        
        if os.path.exists(self.chrome_path):
            browser_config_kwargs["chrome_instance_path"] = self.chrome_path
            if self.user_data_dir:
                browser_config_kwargs["extra_chromium_args"] = [f"--user-data-dir={self.user_data_dir}"]
        
        browser = Browser(config=BrowserConfig(**browser_config_kwargs))
        
        agent = Agent(
            task=task_prompt,
            llm=llm,
            browser=browser,
            use_vision=True
        )

        try:
            history = await agent.run()
            result = history.final_result()
            logger.success("DiscoveryService: Task completed successfully.")
            return result
        except Exception as e:
            logger.error(f"DiscoveryService: Task failed - {e}")
            raise e
        finally:
            try:
                await browser.close()
            except:
                pass