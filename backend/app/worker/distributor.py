"""
内容分发 Worker。

处理向不同平台分发内容的逻辑。
"""
from sqlalchemy import select

from app.core.logging import logger, log_context
from app.core.database import AsyncSessionLocal
from app.core.time_utils import utcnow
from app.models import Content, ReviewStatus, PushedRecord, DistributionRule
from app.push.factory import get_push_service


class ContentDistributor:
    """内容分发器。"""

    async def _build_content_payload(
        self,
        content: Content,
        rule: DistributionRule | None,
        target_render_config: dict | None = None,
    ) -> dict:
        payload = {
            "id": content.id,
            "title": content.title,
            "platform": content.platform.value if content.platform else None,
            "cover_url": content.cover_url,
            "raw_metadata": content.raw_metadata,
            "canonical_url": content.canonical_url,
            "tags": content.tags,
            "is_nsfw": content.is_nsfw,
            "description": content.description,
            "author_name": content.author_name,
            "author_id": content.author_id,
            "published_at": content.published_at,
            "view_count": content.view_count,
            "like_count": content.like_count,
            "collect_count": content.collect_count,
            "share_count": content.share_count,
            "comment_count": content.comment_count,
            "extra_stats": content.extra_stats or {},
            "content_type": content.content_type,
            "clean_url": content.clean_url,
            "url": content.url,
        }

        if rule and rule.render_config:
            payload["render_config"] = rule.render_config

        if target_render_config:
            base = payload.get("render_config") or {}
            payload["render_config"] = {**base, **target_render_config}

        return payload

    async def _handle_batch_push(
        self,
        session: AsyncSessionLocal,
        batch_contents: list,
        target_platform: str,
        target_id: str,
        target_meta: dict,
    ) -> None:
        if target_platform != "qq":
            logger.info("Batch push is only supported for QQ targets")
            return

        try:
            push_service = get_push_service(target_platform)
        except ValueError:
            logger.warning(f"Unsupported push platform: {target_platform}")
            return

        if not hasattr(push_service, "push_forward"):
            logger.warning("Push service does not support forward merge")
            return

        contents_payload: list[dict] = []
        for item in batch_contents:
            content_id = item.get("id")
            if not content_id:
                continue
            result = await session.execute(
                select(Content).where(Content.id == content_id)
            )
            content = result.scalar_one_or_none()
            if not content:
                continue
            if content.review_status not in [ReviewStatus.APPROVED, ReviewStatus.AUTO_APPROVED]:
                continue

            existing = await session.execute(
                select(PushedRecord).where(
                    PushedRecord.content_id == content_id,
                    PushedRecord.target_id == target_id,
                ).order_by(PushedRecord.pushed_at.desc()).limit(1)
            )
            record = existing.scalar_one_or_none()
            if record:
                should_skip = True
                if content.reviewed_at and record.pushed_at:
                    if content.reviewed_at > record.pushed_at:
                        should_skip = False
                if should_skip:
                    continue

            rule = None
            rule_id = item.get("rule_id")
            if rule_id is not None:
                rule_result = await session.execute(
                    select(DistributionRule).where(DistributionRule.id == rule_id)
                )
                rule = rule_result.scalar_one_or_none()

            contents_payload.append(await self._build_content_payload(
                content, rule, target_render_config=target_meta.get("render_config"),
            ))

        if not contents_payload:
            logger.info("No eligible content for batch forward")
            return

        use_author_name = bool(target_meta.get("use_author_name", True))
        summary = target_meta.get("summary")
        message_id = await push_service.push_forward(
            contents_payload,
            target_id,
            use_author_name=use_author_name,
            summary=summary,
        )

        if not message_id:
            logger.error(f"Batch forward failed: target={target_id}")
            return

        for item in contents_payload:
            content_id = item.get("id")
            if not content_id:
                continue
            record_query = await session.execute(
                select(PushedRecord).where(
                    PushedRecord.content_id == content_id,
                    PushedRecord.target_id == target_id,
                )
            )
            record = record_query.scalar_one_or_none()

            if record:
                record.message_id = str(message_id)
                record.push_status = "success"
                record.pushed_at = utcnow()
                record.error_message = None
                session.add(record)
            else:
                session.add(
                    PushedRecord(
                        content_id=content_id,
                        target_platform=target_platform,
                        target_id=target_id,
                        message_id=str(message_id),
                        push_status="success",
                    )
                )

        await session.commit()
        logger.info(
            "Batch forward completed: target=%s, message_id=%s, count=%s",
            target_id,
            message_id,
            len(contents_payload),
        )

    async def process_distribution_task(self, task_data: dict, task_id: str):
        """
        处理分发任务。

        task_data 示例:
        {
            "action": "distribute",
            "content_id": 123,
            "rule_id": 1,
            "target_platform": "telegram",
            "target_id": "@my_channel"
        }
        """
        content_id = task_data.get("content_id")
        target_platform = task_data.get("target_platform")
        target_id = task_data.get("target_id")
        rule_id = task_data.get("rule_id")
        batch_contents = task_data.get("batch_contents")
        target_meta = task_data.get("target_meta") or {}

        with log_context(task_id=task_id, content_id=content_id):
            logger.info(f"Start distribution task: target={target_platform}:{target_id}")

            async with AsyncSessionLocal() as session:
                try:
                    if batch_contents:
                        await self._handle_batch_push(
                            session,
                            batch_contents,
                            target_platform,
                            target_id,
                            target_meta,
                        )
                        return

                    if content_id is None:
                        logger.warning("Missing content_id in task")
                        return

                    result = await session.execute(
                        select(Content).where(Content.id == content_id)
                    )
                    content = result.scalar_one_or_none()

                    if not content:
                        logger.warning(f"Content not found: {content_id}")
                        return

                    if content.review_status not in [ReviewStatus.APPROVED, ReviewStatus.AUTO_APPROVED]:
                        logger.warning(
                            f"Content not approved, skipping: review_status={content.review_status}"
                        )
                        return

                    existing = await session.execute(
                        select(PushedRecord).where(
                            PushedRecord.content_id == content_id,
                            PushedRecord.target_id == target_id,
                        ).order_by(PushedRecord.pushed_at.desc()).limit(1)
                    )
                    record = existing.scalar_one_or_none()

                    if record:
                        should_skip = True
                        if content.reviewed_at and record.pushed_at:
                            if content.reviewed_at > record.pushed_at:
                                logger.info(f"Detected repush: target={target_id}")
                                should_skip = False

                        if should_skip:
                            logger.info(f"Content already pushed to target, skipping: target_id={target_id}")
                            return

                    try:
                        push_service = get_push_service(target_platform)
                    except ValueError:
                        logger.warning(f"Unsupported push platform: {target_platform}")
                        return

                    rule = None
                    if rule_id is not None:
                        rule_result = await session.execute(
                            select(DistributionRule).where(DistributionRule.id == rule_id)
                        )
                        rule = rule_result.scalar_one_or_none()

                    content_dict = await self._build_content_payload(
                        content, rule, target_render_config=target_meta.get("render_config"),
                    )

                    message_id = await push_service.push(content_dict, target_id)

                    if message_id:
                        record_query = await session.execute(
                            select(PushedRecord).where(
                                PushedRecord.content_id == content_id,
                                PushedRecord.target_id == target_id,
                            )
                        )
                        record = record_query.scalar_one_or_none()

                        if record:
                            record.message_id = str(message_id)
                            record.push_status = "success"
                            record.pushed_at = utcnow()
                            record.error_message = None
                            session.add(record)
                            action_type = "updated"
                        else:
                            push_record = PushedRecord(
                                content_id=content_id,
                                target_platform=target_platform,
                                target_id=target_id,
                                message_id=str(message_id),
                                push_status="success",
                            )
                            session.add(push_record)
                            action_type = "created"

                        await session.commit()

                        logger.info(
                            "Distribution task completed (%s): content_id=%s, target=%s, message_id=%s",
                            action_type,
                            content_id,
                            target_id,
                            message_id,
                        )
                    else:
                        record_query = await session.execute(
                            select(PushedRecord).where(
                                PushedRecord.content_id == content_id,
                                PushedRecord.target_id == target_id,
                            )
                        )
                        record = record_query.scalar_one_or_none()

                        if record:
                            record.push_status = "failed"
                            record.error_message = "Push failed (no message_id)"
                            record.pushed_at = utcnow()
                            session.add(record)
                        else:
                            push_record = PushedRecord(
                                content_id=content_id,
                                target_platform=target_platform,
                                target_id=target_id,
                                push_status="failed",
                                error_message="Push failed (no message_id)",
                            )
                            session.add(push_record)

                        await session.commit()
                        logger.error(
                            "Distribution task failed: content_id=%s, target=%s",
                            content_id,
                            target_id,
                        )

                except Exception as e:
                    logger.error(f"Distribution task failed: {e}", exc_info=True)
                    await session.rollback()
