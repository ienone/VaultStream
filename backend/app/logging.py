"""VaultStream 日志模块

目标（M0）：提供带有 \`request_id\`、\`content_id\`、\`task_id\` 的结构化日志。

- 使用 loguru。
- 通过 contextvars 注入上下文，使现有的 \`logger.info(...)\` 调用自动带上这些 ID。
"""

from __future__ import annotations

import sys
import uuid
import os
from contextlib import contextmanager
from contextvars import ContextVar
from typing import Iterator, Optional

from loguru import logger as _base_logger


_request_id: ContextVar[Optional[str]] = ContextVar("request_id", default=None)
_content_id: ContextVar[Optional[int]] = ContextVar("content_id", default=None)
_task_id: ContextVar[Optional[str]] = ContextVar("task_id", default=None)


def _patch_record(record: dict) -> dict:
    record_extra = record.get("extra")
    if record_extra is None:
        record_extra = {}
        record["extra"] = record_extra

    record_extra.setdefault("request_id", _request_id.get())
    record_extra.setdefault("content_id", _content_id.get())
    record_extra.setdefault("task_id", _task_id.get())
    return record


logger = _base_logger.patch(_patch_record)


def new_request_id() -> str:
    return uuid.uuid4().hex


def ensure_task_id(task_id: Optional[str] = None) -> str:
    return task_id or uuid.uuid4().hex


@contextmanager
def log_context(
    *,
    request_id: Optional[str] = None,
    content_id: Optional[int] = None,
    task_id: Optional[str] = None,
) -> Iterator[None]:
    tokens = []
    if request_id is not None:
        tokens.append((_request_id, _request_id.set(request_id)))
    if content_id is not None:
        tokens.append((_content_id, _content_id.set(content_id)))
    if task_id is not None:
        tokens.append((_task_id, _task_id.set(task_id)))

    try:
        yield
    finally:
        for var, token in reversed(tokens):
            var.reset(token)


def setup_logging(*, level: str = "INFO", fmt: str = "json", debug: bool = False) -> None:
    """设置日志配置

    参数:
        level: 日志级别。
        fmt: 'json' 或 'text'。
        debug: 是否启用 loguru 的 backtrace/diagnose。
    """
    logger.remove()
    
    # 确保日志目录存在
    os.makedirs("logs", exist_ok=True)

    if fmt.lower() == "json":
        # 终端 JSON 输出
        logger.add(
            sys.stdout,
            level=level.upper(),
            serialize=True,
            backtrace=debug,
            diagnose=debug,
        )
        # JSON 格式的日志文件
        logger.add(
            "logs/vaultstream.json.log",
            level=level.upper(),
            serialize=True,
            rotation="10 MB",
            retention="7 days",
            compression="zip",
            backtrace=debug,
            diagnose=debug,
        )
        return

    # text format - 简洁模式：仅在有ID时显示
    def format_message(record):
        parts = ["{time:YYYY-MM-DD HH:mm:ss}", "|", "{level:<8}", "|"]
        
        # 仅在存在时添加ID信息
        ids = []
        if record["extra"].get("request_id"):
            ids.append(f"req={record['extra']['request_id'][:8]}")
        if record["extra"].get("content_id"):
            ids.append(f"cnt={record['extra']['content_id']}")
        if record["extra"].get("task_id"):
            ids.append(f"tsk={record['extra']['task_id'][:8]}")

        if ids:
            parts.append(" " + " | ".join(ids) + " -")
        
        parts.append(" {name}:{function} -")
        parts.append(" {message}")
        return "".join(parts) + "\n"

    # 终端文本输出
    logger.add(
        sys.stdout,
        level=level.upper(),
        format=format_message,
        backtrace=debug,
        diagnose=debug,
    )
    # 文本格式的日志文件
    logger.add(
        "logs/vaultstream.log",
        level=level.upper(),
        format=format_message,
        rotation="10 MB",
        retention="7 days",
        compression="zip",
        backtrace=debug,
        diagnose=debug,
    )
