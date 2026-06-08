import asyncio
import random
from loguru import logger
from app.services.browser_auth_service import browser_auth_service
from app.services.background_task_state import (
    record_task_error,
    record_task_started,
    record_task_success,
)
from app.services.automation_policy import AutomationPolicyService


async def _recorded_platform_check(task_name: str, label: str, check_coro):
    try:
        success = await check_coro
    except Exception as e:
        logger.warning("{} keepalive raised: {}", label, e)
        await record_task_error(task_name, e)
        return False

    if success:
        await record_task_success(task_name)
    else:
        await record_task_error(task_name, f"{label} keepalive check failed")
    return success

async def zhihu_keepalive_loop():
    """
    知乎 Cookie 保活与指纹刷新循环。
    随机在 12 到 20 小时之间触发，直接使用无头浏览器提取最新指纹。
    """
    logger.info("Started Zhihu keepalive and refresh worker loop.")
    while True:
        # 随机睡眠 12 到 20 小时
        sleep_hours = random.uniform(12, 20)
        logger.info(f"Next Zhihu keepalive (zse refresh) in {sleep_hours:.2f} hours")
        await asyncio.sleep(sleep_hours * 3600)
        
        logger.info("Running Zhihu zse cookie refresh...")
        success = await _recorded_platform_check(
            "cookie_keepalive_zhihu",
            "Zhihu",
            browser_auth_service.refresh_zhihu_zse_cookie(),
        )
        if not success:
            logger.warning("Zhihu zse refresh failed. The primary cookie might be invalid.")
        else:
            logger.info("Zhihu zse refresh succeeded in background.")

async def weibo_keepalive_loop():
    """
    微博 Cookie 保活循环。
    随机在 24 到 72 小时之间触发。
    """
    logger.info("Started Weibo keepalive worker loop.")
    while True:
        # 随机睡眠 24 到 72 小时
        sleep_hours = random.uniform(24, 72)
        logger.info(f"Next Weibo keepalive in {sleep_hours:.2f} hours")
        await asyncio.sleep(sleep_hours * 3600)
        
        logger.info("Running Weibo keepalive check...")
        is_valid = await _recorded_platform_check(
            "cookie_keepalive_weibo",
            "Weibo",
            browser_auth_service.check_platform_status("weibo"),
        )
        if not is_valid:
            logger.warning("Weibo keepalive check failed.")
        else:
            logger.info("Weibo keepalive check succeeded.")

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
        is_valid = await _recorded_platform_check(
            "cookie_keepalive_xiaohongshu",
            "Xiaohongshu",
            browser_auth_service.check_platform_status("xiaohongshu"),
        )
        if not is_valid:
            logger.warning("Xiaohongshu keepalive check failed.")
        else:
            logger.info("Xiaohongshu keepalive check succeeded.")

def start_cookie_keepalive_tasks():
    """
    启动用于 Cookie 维护的后台任务。
    应在 FastAPI 应用启动期间调用。
    """
    async def _start_if_allowed():
        policy = await AutomationPolicyService().cookie_keepalive()
        if not policy.allowed:
            logger.bind(policy=policy.as_dict()).info(
                "Cookie keepalive tasks skipped by automation policy"
            )
            return
        asyncio.create_task(zhihu_keepalive_loop())
        asyncio.create_task(xiaohongshu_keepalive_loop())
        asyncio.create_task(weibo_keepalive_loop())
        logger.info("Successfully launched cookie keepalive tasks.")

    try:
        asyncio.create_task(_start_if_allowed())
    except Exception as e:
        logger.error(f"Failed to start cookie keepalive tasks: {e}")

class CookieKeepAliveTask:
    """包装类，用于统一启动接口"""

    def __init__(self):
        self._tasks: list[asyncio.Task] = []

    def start(self):
        try:
            if self._tasks and any(not t.done() for t in self._tasks):
                return
            asyncio.create_task(self._start_if_allowed())
        except Exception as e:
            logger.error(f"Failed to start cookie keepalive tasks: {e}")

    async def _start_if_allowed(self):
        policy = await AutomationPolicyService().cookie_keepalive()
        if not policy.allowed:
            logger.bind(policy=policy.as_dict()).info(
                "Cookie keepalive task skipped by automation policy"
            )
            return
        try:
            for task_name in (
                "cookie_keepalive_zhihu",
                "cookie_keepalive_xiaohongshu",
                "cookie_keepalive_weibo",
            ):
                asyncio.create_task(record_task_started(task_name))
            self._tasks = [
                asyncio.create_task(zhihu_keepalive_loop()),
                asyncio.create_task(xiaohongshu_keepalive_loop()),
                asyncio.create_task(weibo_keepalive_loop()),
            ]
            logger.info("Successfully launched cookie keepalive tasks.")
        except Exception as e:
            logger.error(f"Failed to start cookie keepalive tasks: {e}")

    async def stop(self):
        for task in self._tasks:
            if not task.done():
                task.cancel()
        for task in self._tasks:
            try:
                await task
            except asyncio.CancelledError:
                pass
        self._tasks.clear()
