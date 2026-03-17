# 收藏读取逻辑参考自 twitter-cli:
# https://github.com/jackwener/twitter-cli (Apache-2.0 License)
# 当前采用 subprocess 桥接模式，远期可切换为原生 curl_cffi 实现。

from __future__ import annotations

import asyncio
import json
from typing import Optional

from app.adapters.favorites.base import BaseFavoritesFetcher, FavoriteItem
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
            logger.warning("[twitter favorites] check_auth failed: {}", stderr.decode(errors="ignore")[:300])
            return False
        except (FileNotFoundError, asyncio.TimeoutError) as e:
            logger.warning("[twitter favorites] cli unavailable: {}", e)
            return False

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
        except (FileNotFoundError, asyncio.TimeoutError) as e:
            logger.error("[twitter favorites] subprocess error: {}", e)
            return [], None

        if proc.returncode != 0:
            logger.error("[twitter favorites] command failed: {}", stderr.decode(errors="ignore")[:500])
            return [], None

        try:
            data = json.loads(stdout.decode(errors="ignore"))
        except json.JSONDecodeError:
            logger.error("[twitter favorites] invalid JSON output")
            return [], None

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
