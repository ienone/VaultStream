import os
import logging
from typing import Optional, Literal
from loguru import logger
from pydantic import Field, ConfigDict

# LangChain Imports
from langchain_openai import ChatOpenAI

class ChatOpenAICompatible(ChatOpenAI):
    """
    兼容性补丁类：
    1. 允许 Pydantic 动态添加属性 (extra='allow')，解决 browser-use 的 monkey-patch 问题。
    2. 强制注入 provider 字段，满足 browser-use 的类型检查。
    """
    model_config = ConfigDict(extra='allow', frozen=False) 
    provider: str = Field(default="openai")

class LLMFactory:
    """
    LLM 工厂类：统一管理 Vision 和 Text 模型的加载与配置。
    """

    @staticmethod
    def get_vision_llm() -> Optional[ChatOpenAICompatible]:
        """
        获取视觉大模型 (用于 Browser Use / 复杂 Agent 任务)
        读取 VISION_LLM_* 配置
        """
        api_key = os.getenv("VISION_LLM_API_KEY")
        base_url = os.getenv("VISION_LLM_BASE_URL")
        model = os.getenv("VISION_LLM_MODEL", "qwen-vl-max")

        if not api_key:
            logger.warning("LLMFactory: VISION_LLM_API_KEY not found. Vision features will be disabled.")
            return None

        logger.info(f"LLMFactory: Loading Vision Model ({model}) from {base_url}")
        
        try:
            return ChatOpenAICompatible(
                model=model,
                api_key=api_key,
                base_url=base_url,
                temperature=0.0, # Agent 任务通常需要低温度以保证确定性
            )
        except Exception as e:
            logger.error(f"LLMFactory: Failed to initialize Vision LLM - {e}")
            return None

    @staticmethod
    def get_text_llm() -> Optional[ChatOpenAICompatible]:
        """
        获取文本大模型 (用于 Crawl4AI 提取 / 摘要生成 / 清洗)
        读取 TEXT_LLM_* 配置
        """
        api_key = os.getenv("TEXT_LLM_API_KEY")
        base_url = os.getenv("TEXT_LLM_BASE_URL")
        model = os.getenv("TEXT_LLM_MODEL", "deepseek-chat")

        if not api_key:
            # 如果没有专门配置文本模型，尝试回退到视觉模型配置 (假设视觉模型也能处理文本)
            logger.debug("LLMFactory: TEXT_LLM_API_KEY not found, trying fallback to VISION_LLM.")
            return LLMFactory.get_vision_llm()

        logger.info(f"LLMFactory: Loading Text Model ({model}) from {base_url}")

        try:
            return ChatOpenAICompatible(
                model=model,
                api_key=api_key,
                base_url=base_url,
                temperature=0.3, # 文本生成稍微增加一点创造性
            )
        except Exception as e:
            logger.error(f"LLMFactory: Failed to initialize Text LLM - {e}")
            return None

    @staticmethod
    def get_crawl4ai_config(model_type: Literal["vision", "text"] = "text") -> dict:
        """
        专门为 Crawl4AI 获取 LLM 配置字典 (Crawl4AI 不需要 LangChain 对象，而是需要 dict)
        """
        prefix = "VISION_LLM" if model_type == "vision" else "TEXT_LLM"
        
        api_key = os.getenv(f"{prefix}_API_KEY")
        base_url = os.getenv(f"{prefix}_BASE_URL")
        model = os.getenv(f"{prefix}_MODEL")
        
        # 兼容性处理：Crawl4AI 的 provider 格式通常是 "openai/model-name"
        # 如果我们用的是兼容接口，provider 写 openai 即可
        
        if not api_key:
            logger.warning(f"LLMFactory: Missing API Key for {model_type} config.")
            return {}

        return {
            "provider": f"openai/{model}", # 这里的格式取决于 liteLLM
            "api_token": api_key,
            "base_url": base_url
        }

