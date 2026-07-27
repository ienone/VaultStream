from __future__ import annotations

import copy
import queue
import shutil
import subprocess
import threading
import time
import uuid
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any

from .security import redact_text, resolve_test_target


MAX_CAPTURE_CHARS = 200_000
ALLOWED_REPORTERS = {"compact", "expanded", "json"}


class TaskValidationError(ValueError):
    pass


def build_task_command(
    task_name: str,
    payload: dict[str, Any],
    frontend_dir: Path,
) -> list[str]:
    """Map a whitelisted task and constrained arguments to a fixed argv list."""

    fixed_commands = {
        "generate": [
            "dart",
            "run",
            "build_runner",
            "build",
            "--delete-conflicting-outputs",
        ],
        "analyze": ["flutter", "analyze"],
        "format-check": [
            "dart",
            "format",
            "--output=none",
            "--set-exit-if-changed",
            ".",
        ],
    }
    if task_name in fixed_commands:
        unexpected = set(payload) - {"task"}
        if unexpected:
            raise TaskValidationError(
                f"任务 {task_name} 不接受参数: {', '.join(sorted(unexpected))}"
            )
        return fixed_commands[task_name].copy()

    if task_name != "test":
        raise TaskValidationError(f"不支持的任务: {task_name}")

    unexpected = set(payload) - {"task", "target", "reporter"}
    if unexpected:
        raise TaskValidationError(
            f"test 不接受参数: {', '.join(sorted(unexpected))}"
        )

    command = ["flutter", "test"]
    target = payload.get("target")
    if target is not None:
        try:
            resolved = resolve_test_target(frontend_dir, target)
        except ValueError as exc:
            raise TaskValidationError(str(exc)) from exc
        command.append(str(resolved))

    reporter = payload.get("reporter", "compact")
    if reporter not in ALLOWED_REPORTERS:
        raise TaskValidationError("reporter 只允许 compact、expanded 或 json")
    command.extend(["--reporter", reporter])
    return command


@dataclass
class TaskRecord:
    task_id: str
    name: str
    command: list[str]
    state: str = "queued"
    created_at: float = field(default_factory=time.time)
    started_at: float | None = None
    finished_at: float | None = None
    exit_code: int | None = None
    stdout: str = ""
    stderr: str = ""
    error: str | None = None

    def as_dict(self) -> dict[str, Any]:
        duration_ms = None
        if self.started_at is not None:
            end = self.finished_at if self.finished_at is not None else time.time()
            duration_ms = round((end - self.started_at) * 1000)
        return {
            "taskId": self.task_id,
            "task": self.name,
            "state": self.state,
            "createdAt": self.created_at,
            "startedAt": self.started_at,
            "finishedAt": self.finished_at,
            "durationMs": duration_ms,
            "exitCode": self.exit_code,
            "stdout": self.stdout,
            "stderr": self.stderr,
            "error": self.error,
        }


class TaskRunner:
    def __init__(self, frontend_dir: Path) -> None:
        self.frontend_dir = frontend_dir.resolve()
        self._process: subprocess.Popen[str] | None = None
        self._lock = threading.Lock()

    def run(self, command: list[str]) -> tuple[int, str, str]:
        executable = shutil.which(command[0])
        if executable is None:
            raise OSError(f"PATH 中找不到 {command[0]}")
        resolved_command = [executable, *command[1:]]
        process = subprocess.Popen(
            resolved_command,
            cwd=self.frontend_dir,
            stdin=subprocess.DEVNULL,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            encoding="utf-8",
            errors="replace",
            shell=False,
        )
        with self._lock:
            self._process = process
        try:
            stdout, stderr = process.communicate()
        finally:
            with self._lock:
                self._process = None
        return (
            process.returncode,
            redact_text(stdout[-MAX_CAPTURE_CHARS:]),
            redact_text(stderr[-MAX_CAPTURE_CHARS:]),
        )

    def stop(self) -> None:
        with self._lock:
            process = self._process
        if process is not None and process.poll() is None:
            process.terminate()


class TaskManager:
    """Serialize one-shot Flutter/Dart jobs to avoid tool/cache contention."""

    def __init__(
        self,
        frontend_dir: Path,
        runner: TaskRunner | None = None,
    ) -> None:
        self.frontend_dir = frontend_dir.resolve()
        self.runner = runner or TaskRunner(self.frontend_dir)
        self._records: dict[str, TaskRecord] = {}
        self._records_lock = threading.Lock()
        self._queue: queue.Queue[str | None] = queue.Queue()
        self._worker = threading.Thread(
            target=self._work,
            name="dev-controller-task-worker",
            daemon=True,
        )
        self._worker.start()

    def submit(self, payload: dict[str, Any]) -> dict[str, Any]:
        task_name = payload.get("task")
        if not isinstance(task_name, str):
            raise TaskValidationError("缺少字符串类型的 task")
        command = build_task_command(task_name, payload, self.frontend_dir)
        task_id = f"task-{uuid.uuid4().hex[:12]}"
        record = TaskRecord(task_id=task_id, name=task_name, command=command)
        with self._records_lock:
            self._records[task_id] = record
        self._queue.put(task_id)
        return record.as_dict()

    def get(self, task_id: str) -> dict[str, Any] | None:
        with self._records_lock:
            record = self._records.get(task_id)
            return copy.deepcopy(record.as_dict()) if record is not None else None

    def _work(self) -> None:
        while True:
            task_id = self._queue.get()
            if task_id is None:
                return
            with self._records_lock:
                record = self._records[task_id]
                record.state = "running"
                record.started_at = time.time()
            try:
                exit_code, stdout, stderr = self.runner.run(record.command)
                with self._records_lock:
                    record.exit_code = exit_code
                    record.stdout = stdout
                    record.stderr = stderr
                    record.state = "completed" if exit_code == 0 else "failed"
            except (OSError, subprocess.SubprocessError) as exc:
                with self._records_lock:
                    record.state = "failed"
                    record.error = redact_text(str(exc))
            finally:
                with self._records_lock:
                    record.finished_at = time.time()
                self._queue.task_done()

    def close(self) -> None:
        self.runner.stop()
        self._queue.put(None)
        self._worker.join(timeout=3)
