from app.adapters.favorites.base import BaseFavoritesFetcher, FavoriteItem, FavoritesCapability
from app.adapters.favorites.errors import FavoritesFetchError
from app.adapters.favorites.zhihu_fetcher import ZhihuFavoritesFetcher
from app.adapters.favorites.xiaohongshu_fetcher import XiaohongshuFavoritesFetcher
from app.adapters.favorites.bilibili_fetcher import BilibiliFavoritesFetcher
from app.adapters.favorites.weibo_fetcher import WeiboFavoritesFetcher
from app.adapters.favorites.twitter_fetcher import TwitterBookmarksFetcher

FAVORITES_FETCHERS: dict[str, type[BaseFavoritesFetcher]] = {
    "zhihu": ZhihuFavoritesFetcher,
    "xiaohongshu": XiaohongshuFavoritesFetcher,
    "bilibili": BilibiliFavoritesFetcher,
    "weibo": WeiboFavoritesFetcher,
    "twitter": TwitterBookmarksFetcher,
}

FAVORITES_CAPABILITIES = {
    "zhihu": FavoritesCapability(supported=True, scope="本人创建的收藏夹", pagination=True,
        collection_metadata=True, authentication="platform_cookie"),
    "xiaohongshu": FavoritesCapability(supported=True, scope="本人收藏笔记", pagination=True,
        collection_metadata=False, authentication="platform_cookie",
        limitation="当前读取收藏笔记列表，不提供收藏专辑发现"),
    "bilibili": FavoritesCapability(supported=True, scope="本人创建的视频收藏夹", pagination=True,
        collection_metadata=True, authentication="platform_cookie",
        limitation="不包含收藏的他人合集、课程；不可用和非视频项明确跳过"),
    "twitter": FavoritesCapability(supported=True, scope="个人书签", pagination=True,
        collection_metadata=False, authentication="platform_cookie",
        limitation="复用 X 网页登录读取书签；需要服务端浏览器，不提供书签文件夹；遇到验证停止"),
    "weibo": FavoritesCapability(supported=True, scope="个人收藏微博", pagination=True,
        collection_metadata=False, authentication="platform_cookie",
        limitation="网页收藏列表，支持页内恢复；不包含收藏标签分类"),
}

__all__ = [
    "BaseFavoritesFetcher",
    "FavoriteItem",
    "FavoritesFetchError",
    "ZhihuFavoritesFetcher",
    "XiaohongshuFavoritesFetcher",
    "BilibiliFavoritesFetcher",
    "FAVORITES_FETCHERS",
    "FAVORITES_CAPABILITIES",
]
