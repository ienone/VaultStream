"""
AI 巡逻评分服务

对发现缓冲区中的内容进行 LLM 评分，根据阈值决定是否展示。
"""
import json
from typing import Optional

from langchain_core.messages import SystemMessage, HumanMessage
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.llm_factory import LLMFactory
from app.core.logging import logger
from app.models.content import Content
from app.models.base import DiscoveryState


# Horizon prompts
_CONTENT_ANALYSIS_SYSTEM = """You are an expert content curator helping filter important technical and academic information.

Score content on a 0-10 scale based on importance and relevance:

**9-10: Groundbreaking** - Major breakthroughs, paradigm shifts, or highly significant announcements
**7-8: High Value** - Important developments worth immediate attention
**5-6: Interesting** - Worth knowing but not urgent
**3-4: Low Priority** - Generic or routine content
**0-2: Noise** - Not relevant or low quality

Consider:
- Technical depth and novelty
- Potential impact on the field
- Quality of writing/presentation
- Relevance to software engineering, AI/ML, and systems research
- Community discussion quality
- Engagement signals"""

_CONTENT_ANALYSIS_USER = """Analyze the following content and provide a JSON response with:
- score (0-10): Importance score
- reason: Brief explanation for the score
- summary: One-sentence summary of the content
- tags: Relevant topic tags (3-5 tags)

Content:
Title: {title}
Source: {source}
Author: {author}
URL: {url}
Content: {content}

Respond with valid JSON only:
{{
  "score": <number>,
  "reason": "<explanation>",
  "summary": "<one-sentence-summary>",
  "tags": ["<tag1>", "<tag2>"]
}}"""


class PatrolService:
    """AI 巡逻评分服务"""

    def _build_system_prompt(self, interest_profile: str) -> str:
        """Build system prompt combining base scoring criteria + user interest profile."""
        prompt = _CONTENT_ANALYSIS_SYSTEM
        if interest_profile and interest_profile.strip():
            prompt += f"\n\nUser interest profile:\n{interest_profile.strip()}"
        return prompt

    def _build_user_prompt(self, content: Content) -> str:
        """Build user prompt from content fields."""
        return _CONTENT_ANALYSIS_USER.format(
            title=content.title or "",
            source=content.source or content.platform.value if content.platform else "",
            author=content.author_name or "",
            url=content.url or "",
            content=(content.body or "")[:4000],
        )

    def _parse_scoring_response(self, response_text: str) -> Optional[dict]:
        """Parse JSON response, return None on failure."""
        try:
            data = json.loads(response_text)
            if not isinstance(data, dict):
                return None
            if "score" not in data:
                return None
            return {
                "score": float(data["score"]),
                "reason": str(data.get("reason", "")),
                "summary": str(data.get("summary", "")),
                "tags": list(data.get("tags", [])),
            }
        except (json.JSONDecodeError, ValueError, TypeError) as e:
            logger.warning(f"巡逻评分响应解析失败: {e}")
            return None

    async def score_item(self, content: Content, interest_profile: str = "") -> bool:
        """
        Score a single discovery item.
        Returns True if scoring succeeded.
        """
        from app.services.settings_service import get_setting_value

        llm = await LLMFactory.get_text_llm()
        if llm is None:
            logger.warning("巡逻评分: LLM 不可用，跳过评分")
            return False

        system_prompt = self._build_system_prompt(interest_profile)
        user_prompt = self._build_user_prompt(content)

        try:
            response = await llm.ainvoke([
                SystemMessage(content=system_prompt),
                HumanMessage(content=user_prompt),
            ])
            result_text = response.content.strip()
        except Exception as e:
            logger.error(f"巡逻评分 LLM 调用失败: {e}")
            return False

        parsed = self._parse_scoring_response(result_text)
        if parsed is None:
            logger.warning(f"巡逻评分响应解析失败, content_id={content.id}")
            return False

        # Update content fields
        content.ai_score = parsed["score"]
        content.ai_reason = parsed["reason"]
        content.summary = parsed["summary"]
        content.ai_tags = parsed["tags"]

        # State transition
        threshold = float(await get_setting_value("discovery_score_threshold", 6.0))
        if parsed["score"] >= threshold:
            content.discovery_state = DiscoveryState.VISIBLE
        else:
            content.discovery_state = DiscoveryState.IGNORED

        logger.info(
            f"巡逻评分完成: content_id={content.id}, "
            f"score={parsed['score']}, state={content.discovery_state.value}"
        )
        return True

    async def score_batch(
        self, items: list[Content], interest_profile: str = "", batch_size: int = 10
    ) -> int:
        """
        Score multiple items sequentially.
        Returns count of successfully scored items.
        """
        scored = 0
        for item in items:
            ok = await self.score_item(item, interest_profile=interest_profile)
            if ok:
                scored += 1
        return scored

    async def score_pending(self, db: AsyncSession) -> int:
        """
        Query all contents with discovery_state=INGESTED, load settings, and score them.
        This is the entry point called by background tasks.
        """
        from app.services.settings_service import get_setting_value

        stmt = select(Content).where(Content.discovery_state == DiscoveryState.INGESTED)
        result = await db.execute(stmt)
        items = list(result.scalars().all())

        if not items:
            logger.debug("巡逻评分: 没有待评分内容")
            return 0

        interest_profile = await get_setting_value("discovery_interest_profile", "") or ""

        logger.info(f"巡逻评分: 开始处理 {len(items)} 条待评分内容")
        scored = await self.score_batch(items, interest_profile=interest_profile)

        await db.commit()
        logger.info(f"巡逻评分: 完成, 成功 {scored}/{len(items)}")
        return scored
