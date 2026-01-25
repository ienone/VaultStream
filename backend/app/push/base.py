"""
推送服务基类

定义推送服务的接口规范
"""
from abc import ABC, abstractmethod
from typing import Dict, Any, Optional


class BasePushService(ABC):
    """
    推送服务基类
    
    所有推送服务实现都应该继承此类并实现push方法
    """
    
    @abstractmethod
    async def push(
        self, 
        content: Dict[str, Any], 
        target_id: str
    ) -> Optional[str]:
        """
        推送内容到目标平台
        
        Args:
            content: 内容字典,包含title、description、media_urls等字段
            target_id: 目标平台的ID（如Telegram频道ID、QQ群号等）
            
        Returns:
            推送成功返回消息ID,失败返回None
            
        Raises:
            可能抛出平台特定的异常
        """
        pass
    
    @abstractmethod
    async def close(self):
        """
        关闭服务连接
        
        释放资源,关闭网络连接等清理工作
        """
        pass
