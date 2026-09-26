from typing import Optional
from loguru import logger

# LangChain 导入
from langchain_openai import ChatOpenAI
from app.services.config_service import ConfigService

class LLMFactory:
    """
    LLM 工厂类：统一管理 Vision 和 Text 模型的加载与配置。
    """

    @staticmethod
    async def get_vision_llm() -> Optional[ChatOpenAI]:
        """
        获取视觉大模型 (用于 Agent 图片读取)
        读取 VISION_LLM_* 配置
        """
        config = await ConfigService().get_vision_llm_config()

        if not config.api_key:
            logger.warning("LLMFactory: VISION_LLM_API_KEY not found. Vision features will be disabled.")
            return None

        logger.debug(f"LLMFactory: Loading Vision Model ({config.model}) from {config.base_url}")
        
        try:
            return ChatOpenAI(
                model=config.model,
                api_key=config.api_key,
                base_url=config.base_url,
                use_responses_api=False,
                temperature=0.0, # Agent 任务通常需要低温度以保证确定性
            )
        except Exception as e:
            logger.error(f"LLMFactory: Failed to initialize Vision LLM - {e}")
            return None

    @staticmethod
    async def get_text_llm() -> Optional[ChatOpenAI]:
        """
        获取文本大模型 (用于巡逻评分与内容聚合)
        读取 TEXT_LLM_* 配置
        """
        config = await ConfigService().get_text_llm_config()

        if not config.api_key:
            # 如果没有专门配置文本模型，尝试回退到视觉模型配置 (假设视觉模型也能处理文本)
            logger.debug("LLMFactory: TEXT_LLM_API_KEY not found, trying fallback to VISION_LLM.")
            return await LLMFactory.get_vision_llm()

        logger.debug(f"LLMFactory: Loading Text Model ({config.model}) from {config.base_url}")

        try:
            return ChatOpenAI(
                model=config.model,
                api_key=config.api_key,
                base_url=config.base_url,
                use_responses_api=False,
                temperature=0.3, # 文本生成稍微增加一点创造性
                extra_body=await ConfigService().get_value("text_llm_extra_body", None),
            )
        except Exception as e:
            logger.error(f"LLMFactory: Failed to initialize Text LLM - {e}")
            return None

    @staticmethod
    async def get_agent_chat_llm() -> Optional[ChatOpenAI]:
        """
        获取 Agent 对话模型。

        优先使用 agent_chat_* 动态配置；未配置时兼容回退到 text_llm_*，
        再由 get_text_llm() 保留旧的 vision fallback。
        """
        config = await ConfigService().get_agent_chat_config()

        if not config.api_key:
            logger.debug("LLMFactory: AGENT_CHAT_API_KEY not found, trying text LLM fallback.")
            return await LLMFactory.get_text_llm()

        logger.debug(f"LLMFactory: Loading Agent Chat Model ({config.model}) from {config.base_url}")

        try:
            service = ConfigService()
            extra_body = await service.get_value("agent_chat_extra_body", None)
            # Inherit provider parameters only when Agent uses the entire text
            # model configuration. An independently configured provider owns its
            # own parameters, even when one of its fields happens to match.
            dedicated = any([
                await service.get_value("agent_chat_api_key"),
                await service.get_value("agent_chat_base_url"),
                await service.get_value("agent_chat_model"),
            ])
            if extra_body is None and not dedicated:
                extra_body = await service.get_value("text_llm_extra_body", None)
            return ChatOpenAI(
                model=config.model,
                api_key=config.api_key,
                base_url=config.base_url,
                use_responses_api=False,
                temperature=0.2,
                extra_body=extra_body,
            )
        except Exception as e:
            logger.error(f"LLMFactory: Failed to initialize Agent Chat LLM - {e}")
            return None
