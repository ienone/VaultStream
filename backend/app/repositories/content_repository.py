from typing import List, Optional, Tuple
from sqlalchemy import select, and_, or_, func, desc, text
from sqlalchemy.orm import defer
from sqlalchemy.ext.asyncio import AsyncSession
from app.models import Content, ContentStatus, Platform, ReviewStatus
from datetime import datetime

class ContentRepository:
    def __init__(self, db: AsyncSession):
        self.db = db

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
    ) -> Tuple[List[Content], int]:
        """统一的内容查询逻辑，支持 FTS5 搜索"""
        conditions = []
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
        
        if tags:
            # 使用 SQLite json_each() 将 JSON 数组展开为行，再用 IN 匹配
            # 条件数恒定为 1，不随标签数量膨胀
            placeholders = ", ".join(f":tag_{i}" for i in range(len(tags)))
            tag_subquery = text(
                f"SELECT DISTINCT c.id FROM contents c, json_each(c.tags) AS je "
                f"WHERE je.value IN ({placeholders})"
            )
            params = {f"tag_{i}": t for i, t in enumerate(tags)}
            tag_ids_result = await self.db.execute(tag_subquery, params)
            tag_ids = [row[0] for row in tag_ids_result.all()]
            if tag_ids:
                conditions.append(Content.id.in_(tag_ids))
            else:
                conditions.append(text("0 = 1"))

        if q:
            # 整合 FTS5 与 ILIKE
            safe_q = q.replace("'", "''")
            fts_stmt = text("SELECT content_id FROM contents_fts WHERE contents_fts MATCH :q")
            try:
                fts_result = await self.db.execute(fts_stmt, {"q": safe_q})
                fts_ids = [row[0] for row in fts_result.all()]
            except Exception:
                fts_ids = []

            like_cond = or_(
                Content.title.ilike(f"%{q}%"),
                Content.body.ilike(f"%{q}%"),
                Content.author_name.ilike(f"%{q}%")
            )
            if fts_ids:
                conditions.append(or_(Content.id.in_(fts_ids), like_cond))
            else:
                conditions.append(like_cond)

        # 统计总数
        count_stmt = select(func.count()).select_from(Content).where(and_(*conditions))
        total = (await self.db.execute(count_stmt)).scalar() or 0

        # 分页查询（列表场景跳过加载 archive_metadata / last_error_detail 大字段）
        stmt = (
            select(Content)
            .options(defer(Content.archive_metadata), defer(Content.last_error_detail))
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
