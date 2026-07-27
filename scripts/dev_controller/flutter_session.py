from __future__ import annotations

import collections
import json
import os
import shutil
import subprocess
import threading
import time
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any, TextIO

from .security import redact_text


class FlutterSessionError(RuntimeError):
    pass


@dataclass
class _PendingRequest:
    event: threading.Event = field(default_factory=threading.Event)
    result: Any = None
    error: Any = None


def decode_machine_line(line: str) -> dict[str, Any] | None:
    stripped = line.strip()
    if not (stripped.startswith("[{") and stripped.endswith("}]")):
        return None
    try:
        value = json.loads(stripped)
    except json.JSONDecodeError:
        return None
    if not isinstance(value, list) or len(value) != 1 or not isinstance(value[0], dict):
        return None
    return value[0]


def encode_machine_request(
    request_id: str,
    method: str,
    params: dict[str, Any],
) -> str:
    return json.dumps(
        [{"id": request_id, "method": method, "params": params}],
        ensure_ascii=False,
        separators=(",", ":"),
    ) + "\n"


def build_flutter_web_command(
    flutter: str,
    *,
    device: str,
    web_host: str,
    web_port: int,
    api_base_url: str,
) -> list[str]:
    return [
        flutter,
        "run",
        "--machine",
        "-d",
        device,
        "--web-hostname",
        web_host,
        "--web-port",
        str(web_port),
        f"--dart-define=API_BASE_URL={api_base_url}",
    ]


class FlutterMachineSession:
    def __init__(
        self,
        frontend_dir: Path,
        web_port: int = 8123,
        device: str = "web-server",
        web_host: str = "127.0.0.1",
        api_base_url: str = "http://127.0.0.1:8008/api/v1",
        max_log_lines: int = 500,
    ) -> None:
        self.frontend_dir = frontend_dir.resolve()
        self.web_port = web_port
        self.device = device
        self.web_host = web_host
        self.api_base_url = api_base_url.rstrip("/")
        self._process: subprocess.Popen[str] | None = None
        self._state = "stopped"
        self._app_id: str | None = None
        self._supports_restart = False
        self._devtools_uri: str | None = None
        self._debug_port: int | None = None
        self._started_at: float | None = None
        self._process_exit_code: int | None = None
        self._generation = 0
        self._last_reload: dict[str, Any] | None = None
        self._last_error: str | None = None
        self._logs: collections.deque[dict[str, Any]] = collections.deque(
            maxlen=max_log_lines
        )
        self._pending: dict[str, _PendingRequest] = {}
        self._request_number = 0
        self._lock = threading.RLock()
        self._write_lock = threading.Lock()

    def start(self) -> dict[str, Any]:
        with self._lock:
            if self._process is not None and self._process.poll() is None:
                raise FlutterSessionError("Flutter 会话已经在运行")
            flutter = shutil.which("flutter")
            if flutter is None:
                raise FlutterSessionError("PATH 中找不到 flutter")
            command = build_flutter_web_command(
                flutter,
                device=self.device,
                web_host=self.web_host,
                web_port=self.web_port,
                api_base_url=self.api_base_url,
            )
            creation_flags = 0
            if os.name == "nt":
                creation_flags = subprocess.CREATE_NEW_PROCESS_GROUP
            self._state = "starting"
            self._app_id = None
            self._supports_restart = False
            self._devtools_uri = None
            self._debug_port = None
            self._process_exit_code = None
            self._last_error = None
            self._started_at = time.time()
            try:
                self._process = subprocess.Popen(
                    command,
                    cwd=self.frontend_dir,
                    stdin=subprocess.PIPE,
                    stdout=subprocess.PIPE,
                    stderr=subprocess.PIPE,
                    text=True,
                    encoding="utf-8",
                    errors="replace",
                    bufsize=1,
                    shell=False,
                    creationflags=creation_flags,
                )
            except OSError as exc:
                self._state = "failed"
                self._last_error = redact_text(str(exc))
                raise FlutterSessionError(self._last_error) from exc

            process = self._process
            assert process.stdout is not None
            assert process.stderr is not None
            threading.Thread(
                target=self._consume_stream,
                args=(process.stdout, "stdout"),
                name="flutter-machine-stdout",
                daemon=True,
            ).start()
            threading.Thread(
                target=self._consume_stream,
                args=(process.stderr, "stderr"),
                name="flutter-machine-stderr",
                daemon=True,
            ).start()
            threading.Thread(
                target=self._wait_for_exit,
                args=(process,),
                name="flutter-machine-exit",
                daemon=True,
            ).start()
            return self.status()

    def _consume_stream(self, stream: TextIO, channel: str) -> None:
        for line in stream:
            message = decode_machine_line(line) if channel == "stdout" else None
            if message is not None:
                self._handle_machine_message(message)
            else:
                self._append_log(channel, line.rstrip())

    def _handle_machine_message(self, message: dict[str, Any]) -> None:
        request_id = message.get("id")
        if request_id is not None and "method" not in message:
            with self._lock:
                pending = self._pending.get(str(request_id))
                if pending is not None:
                    pending.result = message.get("result")
                    pending.error = message.get("error")
                    pending.event.set()
            return

        event = message.get("event")
        params = message.get("params")
        if not isinstance(event, str) or not isinstance(params, dict):
            return
        with self._lock:
            if event == "app.start":
                app_id = params.get("appId")
                self._app_id = str(app_id) if app_id is not None else None
                self._supports_restart = bool(params.get("supportsRestart"))
                self._state = "starting"
            elif event == "app.started":
                self._state = "ready"
            elif event == "app.stop":
                self._state = "stopped"
                self._app_id = None
                self._supports_restart = False
            elif event == "app.devTools":
                uri = params.get("uri")
                self._devtools_uri = str(uri) if uri is not None else None
            elif event == "app.debugPort":
                port = params.get("port")
                self._debug_port = port if isinstance(port, int) else None
            elif event == "app.log":
                self._append_log_locked(
                    "flutter",
                    str(params.get("log", "")),
                    bool(params.get("error")),
                )

    def _append_log(self, channel: str, line: str, error: bool = False) -> None:
        with self._lock:
            self._append_log_locked(channel, line, error)

    def _append_log_locked(self, channel: str, line: str, error: bool = False) -> None:
        if not line:
            return
        self._logs.append(
            {
                "timestamp": time.time(),
                "channel": channel,
                "error": error,
                "message": redact_text(line),
            }
        )

    def _wait_for_exit(self, process: subprocess.Popen[str]) -> None:
        exit_code = process.wait()
        with self._lock:
            if process is not self._process:
                return
            self._process_exit_code = exit_code
            if self._state not in {"stopped", "stopping"}:
                self._state = "failed" if exit_code != 0 else "stopped"
            for pending in self._pending.values():
                pending.error = "Flutter 进程已退出"
                pending.event.set()

    def _request(
        self,
        method: str,
        params: dict[str, Any],
        timeout: float,
    ) -> Any:
        with self._lock:
            process = self._process
            if process is None or process.poll() is not None or process.stdin is None:
                raise FlutterSessionError("Flutter 会话未运行")
            self._request_number += 1
            request_id = f"vaultstream-{self._request_number}"
            pending = _PendingRequest()
            self._pending[request_id] = pending
            message = encode_machine_request(request_id, method, params)

        try:
            with self._write_lock:
                process.stdin.write(message)
                process.stdin.flush()
            if not pending.event.wait(timeout):
                raise FlutterSessionError(f"Flutter 请求超时: {method}")
            if pending.error is not None:
                raise FlutterSessionError(redact_text(str(pending.error)))
            return pending.result
        finally:
            with self._lock:
                self._pending.pop(request_id, None)

    def reload(self, full_restart: bool = False, timeout: float = 120) -> dict[str, Any]:
        with self._lock:
            app_id = self._app_id
            if app_id is None:
                raise FlutterSessionError("Flutter 应用尚未完成启动")
            if self._state != "ready":
                raise FlutterSessionError(
                    f"Flutter 应用尚未就绪，当前状态: {self._state}"
                )
            if not self._supports_restart:
                raise FlutterSessionError("当前 Flutter 设备不支持重载")
        result = self._request(
            "app.restart",
            {
                "appId": app_id,
                "fullRestart": full_restart,
                "pause": False,
                "reason": "vaultstream-dev-controller",
                "debounce": True,
            },
            timeout,
        )
        succeeded = not isinstance(result, dict) or result.get("code", 0) == 0
        outcome = {
            "kind": "restart" if full_restart else "reload",
            "success": succeeded,
            "timestamp": time.time(),
            "result": result,
        }
        with self._lock:
            self._last_reload = outcome
            if succeeded:
                self._generation += 1
                self._last_error = None
            else:
                self._last_error = f"Flutter 重载失败: {result}"
        if not succeeded:
            raise FlutterSessionError(f"Flutter 重载失败: {result}")
        return {"reload": outcome, "session": self.status()}

    def stop(self, timeout: float = 20) -> dict[str, Any]:
        with self._lock:
            process = self._process
            app_id = self._app_id
            if process is None or process.poll() is not None:
                self._state = "stopped"
                return self.status()
            self._state = "stopping"
        if app_id is not None:
            try:
                self._request("app.stop", {"appId": app_id}, timeout=min(timeout, 10))
            except FlutterSessionError as exc:
                self._append_log("controller", str(exc), error=True)
        try:
            process.wait(timeout=timeout)
        except subprocess.TimeoutExpired:
            process.terminate()
            try:
                process.wait(timeout=5)
            except subprocess.TimeoutExpired:
                process.kill()
                process.wait(timeout=5)
        with self._lock:
            self._state = "stopped"
            self._app_id = None
            self._supports_restart = False
        return self.status()

    def status(self) -> dict[str, Any]:
        with self._lock:
            process = self._process
            pid = process.pid if process is not None and process.poll() is None else None
            return {
                "state": self._state,
                "pid": pid,
                "appId": self._app_id,
                "supportsRestart": self._supports_restart,
                "webUrl": f"http://{self.web_host}:{self.web_port}",
                "apiBaseUrl": self.api_base_url,
                "devToolsUri": self._devtools_uri,
                "debugPort": self._debug_port,
                "buildGeneration": self._generation,
                "lastReload": self._last_reload,
                "lastError": self._last_error,
                "startedAt": self._started_at,
                "processExitCode": self._process_exit_code,
            }

    def logs(self, limit: int = 100) -> list[dict[str, Any]]:
        if limit < 1 or limit > 500:
            raise FlutterSessionError("日志条数必须在 1 到 500 之间")
        with self._lock:
            return list(self._logs)[-limit:]

    def close(self) -> None:
        self.stop()
