import asyncio
import random
from loguru import logger
from app.services.browser_auth_service import browser_auth_service

async def zhihu_keepalive_loop():
    """
    知乎 Cookie 保活循环。
    随机在 12 到 20 小时之间触发，以模拟真实用户打开网页防风控。
    """
    logger.info("Started Zhihu keepalive worker loop.")
    while True:
        # 随机睡眠 12 到 20 小时
        sleep_hours = random.uniform(12, 20)
        logger.info(f"Next Zhihu keepalive in {sleep_hours:.2f} hours")
        await asyncio.sleep(sleep_hours * 3600)
        
        logger.info("Running Zhihu keepalive check...")
        is_valid = await browser_auth_service.check_platform_status("zhihu")
        if not is_valid:
            logger.warning("Zhihu keepalive check failed. The cookie might have expired or been blocked.")
        else:
            logger.info("Zhihu keepalive check succeeded.")

async def xiaohongshu_keepalive_loop():
    """
    小红书 Cookie 保活循环。
    随机在 24 到 48 小时之间触发，以模拟真实用户打开网页防风控。
    """
    logger.info("Started Xiaohongshu keepalive worker loop.")
    while True:
        # 随机睡眠 24 到 48 小时
        sleep_hours = random.uniform(24, 48)
        logger.info(f"Next Xiaohongshu keepalive in {sleep_hours:.2f} hours")
        await asyncio.sleep(sleep_hours * 3600)
        
        logger.info("Running Xiaohongshu keepalive check...")
        is_valid = await browser_auth_service.check_platform_status("xiaohongshu")
        if not is_valid:
            logger.warning("Xiaohongshu keepalive check failed. The cookie might have expired or been blocked.")
        else:
            logger.info("Xiaohongshu keepalive check succeeded.")

def start_cookie_keepalive_tasks():
    """
    启动用于 Cookie 维护的后台任务。
    应在 FastAPI 应用启动期间调用。
    """
    try:
        asyncio.create_task(zhihu_keepalive_loop())
        asyncio.create_task(xiaohongshu_keepalive_loop())
        logger.info("Successfully launched cookie keepalive tasks.")
    except Exception as e:
        logger.error(f"Failed to start cookie keepalive tasks: {e}")
