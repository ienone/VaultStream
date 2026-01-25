"""
Worker 模块

后台任务处理模块，包含:
- TaskWorker: 任务处理器主类
- ContentParser: 内容解析逻辑
- ContentDistributor: 内容分发逻辑
"""
from .task_processor import TaskWorker

# 全局单例
worker = TaskWorker()

__all__ = ['worker', 'TaskWorker']
