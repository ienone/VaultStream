"""Telegram Bot 进程管理服务。"""

from __future__ import annotations

import os
import signal
import subprocess
import sys
import time
from pathlib import Path
from typing import Any

from app.core.logging import logger

_BACKEND_ROOT = Path(__file__).resolve().parents[2]
_PID_FILE = _BACKEND_ROOT / "data" / "telegram_bot.pid"
_LOG_FILE = _BACKEND_ROOT / "logs" / "telegram_bot.log"


def _read_pid() -> int | None:
    if not _PID_FILE.exists():
        return None
    try:
        value = _PID_FILE.read_text(encoding="utf-8").strip()
        return int(value) if value else None
    except Exception:
        return None


def _write_pid(pid: int) -> None:
    _PID_FILE.parent.mkdir(parents=True, exist_ok=True)
    _PID_FILE.write_text(str(pid), encoding="utf-8")


def _remove_pid_file() -> None:
    try:
        if _PID_FILE.exists():
            _PID_FILE.unlink()
    except Exception:
        pass


def _is_process_alive(pid: int) -> bool:
    try:
        os.kill(pid, 0)
        return True
    except PermissionError:
        return True
    except OSError:
        return False
    except SystemError:
        return False


def start_telegram_bot(*, reason: str = "manual") -> dict[str, Any]:
    existing_pid = _read_pid()
    if existing_pid and _is_process_alive(existing_pid):
        return {
            "status": "already_running",
            "pid": existing_pid,
            "reason": reason,
        }

    _LOG_FILE.parent.mkdir(parents=True, exist_ok=True)
    log_file = _LOG_FILE.open("a", encoding="utf-8")

    args = [sys.executable, "-m", "app.bot.main"]
    creationflags = 0

    # 将当前内存中的 API Token 通过环境变量传给子进程，
    # 因为 token 可能是主进程启动时动态生成的，.env 文件中没有。
    from app.core.config import settings as _settings
    child_env = os.environ.copy()
    current_token = _settings.api_token.get_secret_value() if _settings.api_token else ""
    if current_token:
        child_env["API_TOKEN"] = current_token

    popen_kwargs: dict[str, Any] = {
        "cwd": str(_BACKEND_ROOT),
        "stdout": log_file,
        "stderr": log_file,
        "env": child_env,
    }

    if os.name == "nt":
        creationflags = subprocess.CREATE_NEW_PROCESS_GROUP | subprocess.DETACHED_PROCESS
        popen_kwargs["creationflags"] = creationflags
    else:
        popen_kwargs["start_new_session"] = True

    proc = subprocess.Popen(args, **popen_kwargs)
    _write_pid(proc.pid)

    logger.info("Telegram bot process started: pid={}, reason={}", proc.pid, reason)
    return {
        "status": "started",
        "pid": proc.pid,
        "reason": reason,
    }


def stop_telegram_bot(*, reason: str = "manual") -> dict[str, Any]:
    pid = _read_pid()
    if not pid:
        return {"status": "not_running", "reason": reason}

    if not _is_process_alive(pid):
        _remove_pid_file()
        return {"status": "not_running", "reason": reason, "pid": pid}

    try:
        if os.name == "nt":
            result = subprocess.run(
                ["taskkill", "/PID", str(pid), "/T", "/F"],
                capture_output=True,
                text=True,
                timeout=10,
            )
            if result.returncode not in (0, 128):
                return {
                    "status": "error",
                    "reason": reason,
                    "pid": pid,
                    "error": (result.stderr or result.stdout or "taskkill failed").strip(),
                }
        else:
            os.kill(pid, signal.SIGTERM)
    except Exception as e:
        return {
            "status": "error",
            "reason": reason,
            "pid": pid,
            "error": str(e),
        }

    _remove_pid_file()
    logger.info("Telegram bot process stopped: pid={}, reason={}", pid, reason)
    return {
        "status": "stopped",
        "pid": pid,
        "reason": reason,
    }


def restart_telegram_bot(*, reason: str = "manual") -> dict[str, Any]:
    stopped = stop_telegram_bot(reason=reason)
    time.sleep(0.6)
    started = start_telegram_bot(reason=reason)
    return {
        "status": "restarted",
        "reason": reason,
        "stopped": stopped,
        "started": started,
    }


def _main() -> int:
    action = (sys.argv[1] if len(sys.argv) > 1 else "status").lower().strip()
    if action == "start":
        result = start_telegram_bot(reason="cli")
    elif action == "stop":
        result = stop_telegram_bot(reason="cli")
    elif action == "restart":
        result = restart_telegram_bot(reason="cli")
    elif action == "status":
        pid = _read_pid()
        result = {
            "status": "running" if (pid and _is_process_alive(pid)) else "not_running",
            "pid": pid,
        }
    else:
        print({"status": "error", "error": f"Unsupported action: {action}"})
        return 2

    print(result)
    return 0


if __name__ == "__main__":
    raise SystemExit(_main())
