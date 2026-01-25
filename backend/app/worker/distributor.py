"""
分发任务处理器

处理内容分发到不同平台的逻辑
"""
import traceback
from sqlalchemy import select
from app.core.logging import logger, log_context
from app.core.database import AsyncSessionLocal
from app.models import Content, ReviewStatus, PushedRecord, Platform
from app.push.factory import get_push_service


class ContentDistributor:
    """内容分发器"""

    async def process_distribution_task(self, task_data: dict, task_id: str):
        """
        处理分发任务（M4）
        
        task_data 示例:
        {
            "action": "distribute",
            "content_id": 123,
            "rule_id": 1,
            "target_platform": "telegram",
            "target_id": "@my_channel"
        }
        """
        content_id = task_data.get('content_id')
        target_platform = task_data.get('target_platform')
        target_id = task_data.get('target_id')
        rule_id = task_data.get('rule_id')
        
        with log_context(task_id=task_id, content_id=content_id):
            logger.info(f"开始处理分发任务: target={target_platform}:{target_id}")
            
            async with AsyncSessionLocal() as session:
                try:
                    # 获取内容记录
                    result = await session.execute(
                        select(Content).where(Content.id == content_id)
                    )
                    content = result.scalar_one_or_none()
                    
                    if not content:
                        logger.warning(f"内容不存在: {content_id}")
                        return
                    
                    # 检查审批状态
                    if content.review_status not in [ReviewStatus.APPROVED, ReviewStatus.AUTO_APPROVED]:
                        logger.warning(f"内容未批准，跳过分发: review_status={content.review_status}")
                        return
                    
                    # 检查是否已推送
                    existing = await session.execute(
                        select(PushedRecord).where(
                            PushedRecord.content_id == content_id,
                            PushedRecord.target_id == target_id
                        )
                    )
                    if existing.scalar_one_or_none():
                        logger.info(f"内容已推送到目标，跳过: target_id={target_id}")
                        return
                    
                    # 获取推送服务
                    try:
                        push_service = get_push_service(target_platform)
                    except ValueError:
                        logger.warning(f"不支持的推送平台: {target_platform}")
                        return
                    
                    # 构造内容数据（需要转为 dict）
                    content_dict = {
                        "id": content.id,
                        "title": content.title,
                        "platform": content.platform.value if content.platform else None,
                        "cover_url": content.cover_url,
                        "raw_metadata": content.raw_metadata,
                        "canonical_url": content.canonical_url,
                        "tags": content.tags,
                        "is_nsfw": content.is_nsfw,
                        # 兼容字段
                        "description": content.description,
                        "author_name": content.author_name,
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
                    
                    # 推送消息
                    message_id = await push_service.push(content_dict, target_id)
                    
                    if message_id:
                        # 创建推送记录
                        push_record = PushedRecord(
                            content_id=content_id,
                            target_platform=target_platform,
                            target_id=target_id,
                            message_id=str(message_id),
                            push_status="success"
                        )
                        session.add(push_record)
                        await session.commit()
                        
                        logger.info(
                            f"分发任务完成: content_id={content_id}, "
                            f"target={target_id}, message_id={message_id}"
                        )
                    else:
                        # 推送失败，记录失败状态
                        push_record = PushedRecord(
                            content_id=content_id,
                            target_platform=target_platform,
                            target_id=target_id,
                            push_status="failed"
                        )
                        session.add(push_record)
                        await session.commit()
                        logger.error(f"分发任务失败: content_id={content_id}, target={target_id}")
                    
                except Exception as e:
                    logger.error(f"分发任务失败: {e}", exc_info=True)
                    await session.rollback()
