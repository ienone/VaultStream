from typing import List, Optional, Tuple
from sqlalchemy import select, and_, or_, func, desc, text, bindparam
from sqlalchemy.orm import defer
from sqlalchemy.ext.asyncio import AsyncSession
from app.models import Content, ContentStatus, ReviewStatus, DiscoveryState
from app.utils.text_search import build_fts_or_like_condition
from datetime import datetime

class ContentRepository:
    def __init__(self, db: AsyncSession):
        self.db = db

    async def _fetch_tagged_content_ids(self, tags: List[str]) -> list[int]:
        tag_subquery = text(
            "SELECT DISTINCT c.id FROM contents c, json_each(c.tags) AS je "
            "WHERE je.value IN :tags"
        ).bindparams(bindparam("tags", expanding=True))
        tag_ids_result = await self.db.execute(tag_subquery, {"tags": tags})
        return [row[0] for row in tag_ids_result.all()]

    async def _build_conditions(
        self,
        *,
        platforms: Optional[List[str]],
        statuses: Optional[List[str]],
        review_status: Optional[ReviewStatus],
        tags: Optional[List[str]],
        q: Optional[str],
        is_nsfw: Optional[bool],
        author: Optional[str],
        start_date: Optional[datetime],
        end_date: Optional[datetime],
    ) -> list:
        conditions: list = []
        if platforms:
            conditions.append(Content.platform.in_(platforms))
        if statuses:
            conditions.append(Content.status.in_(statuses))
        if review_status:
            conditions.append(Content.review_status == review_status)
        if is_nsfw is not None:
            conditions.append(Content.is_nsfw == is_nsfw)
        if author:
            conditions.append(Content.author_name.ilike(f"%{author}%"))
        if start_date:
            conditions.append(Content.created_at >= start_date)
        if end_date:
            conditions.append(Content.created_at <= end_date)

        # 默认隔离 discovery 缓冲区：只有 discovery_state 为 NULL（正式收藏）或 PROMOTED 的内容进入主库视图
        conditions.append(
            or_(
                Content.discovery_state.is_(None),
                Content.discovery_state == DiscoveryState.PROMOTED,
            )
        )

        if tags:
            tag_ids = await self._fetch_tagged_content_ids(tags)
            if tag_ids:
                conditions.append(Content.id.in_(tag_ids))
            else:
                conditions.append(text("0 = 1"))

        if q:
            conditions.append(
                await build_fts_or_like_condition(
                    session=self.db,
                    query=q,
                    like_columns=(Content.title, Content.body, Content.author_name),
                )
            )

        return conditions

    async def list_contents(
        self,
        page: int = 1,
        size: int = 20,
        platforms: Optional[List[str]] = None,
        statuses: Optional[List[str]] = None,
        review_status: Optional[ReviewStatus] = None,
        tags: Optional[List[str]] = None,
        q: Optional[str] = None,
        is_nsfw: Optional[bool] = None,
        author: Optional[str] = None,
        start_date: Optional[datetime] = None,
        end_date: Optional[datetime] = None,
        include_archive_metadata: bool = False,
    ) -> Tuple[List[Content], int]:
        """统一的内容查询逻辑，支持 FTS5 搜索"""
        conditions = await self._build_conditions(
            platforms=platforms,
            statuses=statuses,
            review_status=review_status,
            tags=tags,
            q=q,
            is_nsfw=is_nsfw,
            author=author,
            start_date=start_date,
            end_date=end_date,
        )

        # 统计总数
        count_stmt = select(func.count()).select_from(Content).where(and_(*conditions))
        total = (await self.db.execute(count_stmt)).scalar() or 0

        # 分页查询（列表场景跳过加载 archive_metadata / last_error_detail 大字段）
        stmt = (
            select(Content)
            .where(and_(*conditions))
            .order_by(desc(Content.created_at))
            .offset((page - 1) * size)
            .limit(size)
        )
        if not include_archive_metadata:
            stmt = stmt.options(defer(Content.archive_metadata), defer(Content.last_error_detail))
        else:
            stmt = stmt.options(defer(Content.last_error_detail))
        
        result = await self.db.execute(stmt)
        return result.scalars().all(), total

    async def list_cards(
        self,
        page: int = 1,
        size: int = 20,
        platforms: Optional[List[str]] = None,
        statuses: Optional[List[str]] = None,
        review_status: Optional[ReviewStatus] = None,
        tags: Optional[List[str]] = None,
        q: Optional[str] = None,
        is_nsfw: Optional[bool] = None,
        author: Optional[str] = None,
        start_date: Optional[datetime] = None,
        end_date: Optional[datetime] = None,
    ) -> Tuple[List[Content], int]:
        """轻量级卡片查询 — 延迟加载大字段，仅返回展示所需列"""
        conditions = await self._build_conditions(
            platforms=platforms,
            statuses=statuses,
            review_status=review_status,
            tags=tags,
            q=q,
            is_nsfw=is_nsfw,
            author=author,
            start_date=start_date,
            end_date=end_date,
        )

        count_stmt = select(func.count()).select_from(Content).where(and_(*conditions))
        total = (await self.db.execute(count_stmt)).scalar() or 0

        stmt = (
            select(Content)
            .options(
                defer(Content.body),
                defer(Content.rich_payload),
                defer(Content.archive_metadata),
                defer(Content.context_data),
                defer(Content.extra_stats),
                defer(Content.summary),
                defer(Content.last_error),
                defer(Content.last_error_detail),
                defer(Content.media_urls),
            )
            .where(and_(*conditions))
            .order_by(desc(Content.created_at))
            .offset((page - 1) * size)
            .limit(size)
        )

        result = await self.db.execute(stmt)
        return result.scalars().all(), total

    async def get_by_id(self, content_id: int) -> Optional[Content]:
        result = await self.db.execute(select(Content).where(Content.id == content_id))
        return result.scalar_one_or_none()

    async def list_parsed_contents(self) -> List[Content]:
        """获取所有解析成功的内容（用于规则刷新）"""
        result = await self.db.execute(
            select(Content).where(Content.status == ContentStatus.PARSE_SUCCESS)
        )
        return list(result.scalars().all())
