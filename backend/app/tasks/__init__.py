from .parsing import ContentParser
from .distribution_worker import DistributionQueueWorker
from .maintenance import CookieKeepAliveTask
from .runner import TaskWorker
from .discovery_sync import DiscoverySyncTask
from .discovery_cleanup import DiscoveryCleanupTask
from .favorites_sync import FavoritesSyncTask
from .notification_digest import NotificationDigestTask

# 全局单例
worker = TaskWorker()

__all__ = [
    "worker",
    "ContentParser",
    "DistributionQueueWorker",
    "CookieKeepAliveTask",
    "TaskWorker",
    "DiscoverySyncTask",
    "DiscoveryCleanupTask",
    "FavoritesSyncTask",
    "NotificationDigestTask",
]
