from __future__ import annotations

import json
import os
from pathlib import Path
from typing import Optional

from app.core.logging import logger


def _is_process_alive(pid: int) -> bool:
    if pid <= 0:
        return False
    try:
        os.kill(pid, 0)
        return True
    except PermissionError:
        return True
    except OSError:
        return False


class BackgroundTaskLeader:
    """
    Local single-host leader lock for periodic background loops.

    Only one backend process should own this lock at a time.
    """

    def __init__(self, lock_file: Optional[Path] = None):
        backend_root = Path(__file__).resolve().parents[2]
        self._lock_file = lock_file or backend_root / "data" / "periodic_tasks.lock"
        self._owned = False

    def _read_owner_pid(self) -> Optional[int]:
        if not self._lock_file.exists():
            return None
        try:
            raw = self._lock_file.read_text(encoding="utf-8").strip()
            if not raw:
                return None
            payload = json.loads(raw)
            pid = int(payload.get("pid", 0))
            return pid if pid > 0 else None
        except Exception:
            return None

    def try_acquire(self) -> bool:
        pid = os.getpid()
        self._lock_file.parent.mkdir(parents=True, exist_ok=True)
        payload = json.dumps({"pid": pid}, ensure_ascii=False)

        for _ in range(2):
            try:
                fd = os.open(str(self._lock_file), os.O_CREAT | os.O_EXCL | os.O_WRONLY)
                with os.fdopen(fd, "w", encoding="utf-8") as f:
                    f.write(payload)
                self._owned = True
                logger.info("Periodic task leader lock acquired: pid={}", pid)
                return True
            except FileExistsError:
                owner_pid = self._read_owner_pid()
                if owner_pid == pid:
                    self._owned = True
                    return True
                if owner_pid and _is_process_alive(owner_pid):
                    logger.info("Periodic task leader lock held by pid={}, skip startup loops", owner_pid)
                    self._owned = False
                    return False
                # stale file
                try:
                    self._lock_file.unlink(missing_ok=True)
                except Exception as e:
                    logger.warning("Failed to clean stale periodic task lock: {}", e)
                    self._owned = False
                    return False
            except Exception as e:
                logger.warning("Acquire periodic task leader lock failed: {}", e)
                self._owned = False
                return False

        self._owned = False
        return False

    def release(self) -> None:
        if not self._owned:
            return
        pid = os.getpid()
        owner_pid = self._read_owner_pid()
        if owner_pid != pid:
            self._owned = False
            return
        try:
            self._lock_file.unlink(missing_ok=True)
            logger.info("Periodic task leader lock released: pid={}", pid)
        except Exception as e:
            logger.warning("Release periodic task leader lock failed: {}", e)
        finally:
            self._owned = False

    @property
    def owned(self) -> bool:
        return self._owned


background_task_leader = BackgroundTaskLeader()
