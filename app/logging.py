"""VaultStream logging utilities.

Goal (M0): provide structured logs with `request_id`, `content_id`, `task_id`.

- Uses loguru.
- Injects context via contextvars so existing `logger.info(...)` calls pick up IDs automatically.
"""

from __future__ import annotations

import sys
import uuid
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
    """Configure loguru sinks.

    Args:
        level: log level.
        fmt: 'json' or 'text'.
        debug: enable loguru backtrace/diagnose.
    """
    logger.remove()

    if fmt.lower() == "json":
        logger.add(
            sys.stdout,
            level=level.upper(),
            serialize=True,
            backtrace=debug,
            diagnose=debug,
        )
        return

    # text format (still includes the structured IDs)
    logger.add(
        sys.stdout,
        level=level.upper(),
        backtrace=debug,
        diagnose=debug,
        format=(
            "{time:YYYY-MM-DD HH:mm:ss.SSS} | {level:<8} | "
            "rid={extra[request_id]} cid={extra[content_id]} tid={extra[task_id]} | "
            "{name}:{function}:{line} - {message}"
        ),
    )
