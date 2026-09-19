"""
AI 巡逻评分服务

对发现缓冲区中的内容进行 LLM 评分，根据阈值决定是否展示。
"""
from pydantic import BaseModel, ConfigDict, Field

from langchain_core.messages import SystemMessage, HumanMessage
from sqlalchemy import select, update
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm.exc import StaleDataError

from app.core.llm_factory import LLMFactory
from app.core.logging import logger
from app.models.content import Content
from app.models.base import DiscoveryState
from app.services.background_task_state import (
    record_task_run_error,
    record_task_run_started,
    record_task_run_success,
)
from app.services.config_service import ConfigService


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

_CONTENT_ANALYSIS_USER = """Analyze the following content and provide:
- score (0-10): Importance score
- reason: Brief explanation for the score
- tags: Relevant topic tags (3-5 tags)

Content:
Title: {title}
Source: {source}
Author: {author}
URL: {url}
Content: {content}
Return the result through the supplied structured-output tool."""


class PatrolScore(BaseModel):
    model_config = ConfigDict(extra="forbid", strict=True, str_strip_whitespace=True)
    score: float = Field(ge=0, le=10, allow_inf_nan=False)
    reason: str = Field(min_length=1)
    tags: list[str]


class PatrolService:
    """AI 巡逻评分服务"""

    def __init__(self, config_service: ConfigService | None = None) -> None:
        self._config_service = config_service or ConfigService()

    async def _get_score_threshold(self) -> float:
        return float(await self._config_service.get_value("discovery_score_threshold", 6.0))

    async def _get_interest_profile(self) -> str:
        value = await self._config_service.get_value("discovery_interest_profile", "")
        return str(value or "")

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

    async def score_item(self, content: Content, interest_profile: str = "", *, db: AsyncSession) -> bool:
        """
        Score a single discovery item.
        Returns True if scoring succeeded.
        """
        revision = content.updated_at
        llm = await LLMFactory.get_text_llm()
        if llm is None:
            logger.warning("巡逻评分: LLM 不可用，跳过评分")
            return False

        system_prompt = self._build_system_prompt(interest_profile)
        user_prompt = self._build_user_prompt(content)

        try:
            parsed = await llm.with_structured_output(
                PatrolScore, method="function_calling"
            ).ainvoke([
                SystemMessage(content=system_prompt),
                HumanMessage(content=user_prompt),
            ])
            if parsed is None:
                raise ValueError("模型未调用巡逻评分结构化输出工具")
        except Exception as e:
            logger.error(f"巡逻评分 LLM 调用失败: {e}")
            return False

        threshold = await self._get_score_threshold()
        state = DiscoveryState.VISIBLE if parsed.score >= threshold else DiscoveryState.IGNORED
        with db.no_autoflush:
            result = await db.execute(update(Content).where(
                Content.id == content.id, Content.updated_at == revision,
            ).values(ai_score=parsed.score, ai_reason=parsed.reason,
                     ai_tags=parsed.tags, discovery_state=state
            ).execution_options(synchronize_session=False))
        if result.rowcount != 1:
            await db.commit()
            raise StaleDataError("评分期间内容或处理状态已变化，请刷新后重试")
        await db.commit()
        await db.refresh(content)

        logger.info(
            f"巡逻评分完成: content_id={content.id}, "
            f"score={parsed.score}, state={content.discovery_state.value}"
        )
        return True

    async def score_batch(
        self, items: list[Content], interest_profile: str = "", batch_size: int = 10, *, db: AsyncSession
    ) -> int:
        """
        Score multiple items sequentially.
        Returns count of successfully scored items.
        """
        scored = 0
        size = max(1, batch_size)
        for start in range(0, len(items), size):
            for item in items[start:start + size]:
                try:
                    ok = await self.score_item(item, interest_profile=interest_profile, db=db)
                except StaleDataError:
                    ok = False
                if ok:
                    scored += 1
        return scored

    async def score_pending(self, db: AsyncSession) -> int:
        """
        Query all contents with discovery_state=INGESTED, load settings, and score them.
        This is the entry point called by background tasks.
        """
        stmt = select(Content).where(Content.discovery_state == DiscoveryState.INGESTED)
        result = await db.execute(stmt)
        items = list(result.scalars().all())

        if not items:
            logger.debug("巡逻评分: 没有待评分内容")
            return 0

        run = await record_task_run_started(
            "discovery_patrol",
            trigger="auto",
            candidate_count=len(items),
        )
        run_id = run["run_id"]

        try:
            interest_profile = await self._get_interest_profile()

            logger.info(f"巡逻评分: 开始处理 {len(items)} 条待评分内容")
            scored = await self.score_batch(items, interest_profile=interest_profile, db=db)

            await db.commit()
            metadata = dict(
                trigger="auto",
                candidate_count=len(items),
                scored_count=scored,
                failed_count=max(0, len(items) - scored),
                interest_profile_present=bool(interest_profile.strip()),
            )
            if scored < len(items):
                await record_task_run_error(
                    "discovery_patrol", run_id, "部分候选评分失败，未评分候选保留待处理", **metadata,
                )
            else:
                await record_task_run_success("discovery_patrol", run_id, **metadata)
            logger.info(f"巡逻评分: 完成, 成功 {scored}/{len(items)}")
            return scored
        except Exception as e:
            await db.rollback()
            await record_task_run_error(
                "discovery_patrol",
                run_id,
                e,
                trigger="auto",
                candidate_count=len(items),
            )
            raise
