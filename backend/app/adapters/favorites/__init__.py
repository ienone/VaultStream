from app.adapters.favorites.base import BaseFavoritesFetcher, FavoriteItem
from app.adapters.favorites.zhihu_fetcher import ZhihuFavoritesFetcher
from app.adapters.favorites.xiaohongshu_fetcher import XiaohongshuFavoritesFetcher
from app.adapters.favorites.twitter_fetcher import TwitterFavoritesFetcher

__all__ = [
    "BaseFavoritesFetcher",
    "FavoriteItem",
    "ZhihuFavoritesFetcher",
    "XiaohongshuFavoritesFetcher",
    "TwitterFavoritesFetcher",
]
