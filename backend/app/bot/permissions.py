"""
Bot 权限检查模块
"""
from typing import Optional, Set, Tuple
from .messages import MSG_NO_PERMISSION, MSG_BLACKLISTED, MSG_ADMIN_ONLY


class PermissionManager:
    """权限管理器"""
    
    def __init__(self, admin_ids: Set[int], whitelist_ids: Set[int], blacklist_ids: Set[int]):
        self.admin_ids = admin_ids
        self.whitelist_ids = whitelist_ids
        self.blacklist_ids = blacklist_ids
    
    def check_permission(self, user_id: int, require_admin: bool = False) -> Tuple[bool, Optional[str]]:
        """
        检查用户权限
        
        Args:
            user_id: 用户ID
            require_admin: 是否需要管理员权限
        
        Returns:
            (是否允许, 拒绝原因)
        """
        # 检查黑名单
        if user_id in self.blacklist_ids:
            return False, MSG_BLACKLISTED
        
        # 检查管理员权限
        if require_admin:
            if user_id not in self.admin_ids:
                return False, MSG_ADMIN_ONLY
            return True, None
        
        # 检查白名单（如果配置了白名单）
        if self.whitelist_ids:
            # 管理员自动在白名单中
            if user_id not in self.whitelist_ids and user_id not in self.admin_ids:
                return False, MSG_NO_PERMISSION
        
        return True, None


def get_permission_manager(bot_data: dict) -> PermissionManager:
    """从 bot_data 获取权限管理器实例"""
    return bot_data.get("permission_manager")
