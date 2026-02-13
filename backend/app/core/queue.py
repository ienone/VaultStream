"""任务队列服务（适配器抽象）。"""
from app.core.queue_adapter import get_queue_adapter

# 获取队列适配器（根据配置自动选择）
task_queue = get_queue_adapter()
