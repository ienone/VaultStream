# 收藏读取逻辑参考自 twitter-cli:
# https://github.com/jackwener/twitter-cli (Apache-2.0 License)
# 当前采用 subprocess 桥接模式，远期可切换为原生 curl_cffi 实现。

from __future__ import annotations

import asyncio
import json
from typing import Optional

from app.adapters.favorites.base import BaseFavoritesFetcher, FavoriteItem
from app.adapters.favorites.errors import FavoritesFetchError
from app.core.logging import logger


class TwitterFavoritesFetcher(BaseFavoritesFetcher):
    """Twitter/X 书签拉取器（subprocess 桥接）。"""

    def platform_name(self) -> str:
        return "twitter"

    async def check_auth(self) -> bool:
        try:
            proc = await asyncio.create_subprocess_exec(
                "twitter",
                "bookmarks",
                "--max",
                "1",
                "--json",
                stdout=asyncio.subprocess.PIPE,
                stderr=asyncio.subprocess.PIPE,
            )
            _, stderr = await asyncio.wait_for(proc.communicate(), timeout=30)
            if proc.returncode == 0:
                return True
            err_text = stderr.decode(errors="ignore")[:300]
            logger.warning("[twitter favorites] check_auth failed: {}", err_text)
            lower = err_text.lower()
            if "login" in lower or "auth" in lower or "unauthorized" in lower:
                raise FavoritesFetchError(
                    code="auth_required",
                    message="Twitter CLI is not authenticated",
                    hint="请先使用 `twitter login` 完成登录后再同步收藏",
                    auth_required=True,
                )
            return False
        except FileNotFoundError as e:
            logger.warning("[twitter favorites] cli unavailable: {}", e)
            raise FavoritesFetchError(
                code="cli_unavailable",
                message="twitter cli is not installed",
                hint="请安装并配置 twitter CLI，再执行收藏同步",
            ) from e
        except asyncio.TimeoutError as e:
            logger.warning("[twitter favorites] check_auth timeout: {}", e)
            raise FavoritesFetchError(
                code="network_timeout",
                message="Twitter CLI auth check timeout",
                hint="网络连接超时，请稍后重试",
                retryable=True,
            ) from e

    async def fetch_favorites(
        self,
        *,
        max_items: int = 50,
        cursor: Optional[str] = None,
    ) -> tuple[list[FavoriteItem], Optional[str]]:
        del cursor
        try:
            proc = await asyncio.create_subprocess_exec(
                "twitter",
                "bookmarks",
                "--max",
                str(max_items),
                "--json",
                stdout=asyncio.subprocess.PIPE,
                stderr=asyncio.subprocess.PIPE,
            )
            stdout, stderr = await asyncio.wait_for(proc.communicate(), timeout=120)
        except FileNotFoundError as e:
            logger.error("[twitter favorites] subprocess error: {}", e)
            raise FavoritesFetchError(
                code="cli_unavailable",
                message="twitter cli is not installed",
                hint="请安装并配置 twitter CLI，再执行收藏同步",
            ) from e
        except asyncio.TimeoutError as e:
            logger.error("[twitter favorites] subprocess timeout: {}", e)
            raise FavoritesFetchError(
                code="network_timeout",
                message="Twitter CLI request timeout",
                hint="请求超时，请稍后重试",
                retryable=True,
            ) from e

        if proc.returncode != 0:
            err_text = stderr.decode(errors="ignore")[:500]
            logger.error("[twitter favorites] command failed: {}", err_text)
            lower = err_text.lower()
            if "login" in lower or "auth" in lower or "unauthorized" in lower:
                raise FavoritesFetchError(
                    code="auth_required",
                    message="Twitter CLI is not authenticated",
                    hint="请先使用 `twitter login` 完成登录后再同步收藏",
                    auth_required=True,
                )
            if "rate" in lower or "too many requests" in lower or "429" in lower:
                raise FavoritesFetchError(
                    code="rate_limited",
                    message="Twitter API rate limited",
                    hint="触发限流，建议稍后重试",
                    retryable=True,
                )
            raise FavoritesFetchError(
                code="fetch_failed",
                message="Twitter CLI command failed",
                hint="请检查 twitter CLI 输出日志和网络连通性",
            )

        try:
            data = json.loads(stdout.decode(errors="ignore"))
        except json.JSONDecodeError as e:
            logger.error("[twitter favorites] invalid JSON output")
            raise FavoritesFetchError(
                code="parse_failed",
                message="Twitter CLI returned invalid JSON",
                hint="CLI 输出格式异常，请升级 CLI 或稍后重试",
                retryable=True,
            ) from e

        tweets = data.get("data", data) if isinstance(data, dict) else data
        if isinstance(tweets, dict):
            tweets = [tweets]
        if not isinstance(tweets, list):
            tweets = []

        items: list[FavoriteItem] = []
        for tweet in tweets:
            if len(items) >= max_items:
                break
            if not isinstance(tweet, dict):
                continue

            tweet_id = str(tweet.get("id", "") or "")
            if not tweet_id:
                continue

            author = tweet.get("author", {}) or {}
            screen_name = author.get("screen_name") or tweet.get("screen_name") or ""
            author_name = author.get("name") or tweet.get("author_name") or screen_name
            text = tweet.get("text") or tweet.get("full_text") or ""

            if screen_name:
                tweet_url = f"https://x.com/{screen_name}/status/{tweet_id}"
            else:
                tweet_url = f"https://x.com/i/web/status/{tweet_id}"

            items.append(
                FavoriteItem(
                    url=tweet_url,
                    title=(text or "")[:100] or f"Tweet {tweet_id}",
                    platform=self.platform_name(),
                    item_id=tweet_id,
                    author=author_name,
                    content_type="tweet",
                )
            )

        return items, None
