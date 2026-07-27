from __future__ import annotations

import argparse
import hmac
import json
import os
import secrets
import signal
import sys
import threading
from http import HTTPStatus
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from typing import Any
from urllib.parse import parse_qs, urlparse

from .flutter_session import FlutterMachineSession, FlutterSessionError
from .tasks import TaskManager, TaskValidationError


MAX_REQUEST_BYTES = 16_384


def _repo_root() -> Path:
    return Path(__file__).resolve().parents[2]


class DevController:
    def __init__(self, repo_root: Path, web_port: int, control_port: int) -> None:
        self.repo_root = repo_root.resolve()
        self.frontend_dir = self.repo_root / "frontend"
        self.runtime_dir = self.repo_root / ".runtime"
        self.runtime_file = self.runtime_dir / "dev-controller.json"
        self.web_port = web_port
        self.control_port = control_port
        self.token = secrets.token_urlsafe(32)
        self.session = FlutterMachineSession(self.frontend_dir, web_port=web_port)
        self.tasks = TaskManager(self.frontend_dir)
        self.httpd: ThreadingHTTPServer | None = None
        self._closing = threading.Event()

    def authorized(self, header: str | None) -> bool:
        if header is None or not header.startswith("Bearer "):
            return False
        return hmac.compare_digest(header[7:], self.token)

    def write_runtime_file(self) -> None:
        self.runtime_dir.mkdir(parents=True, exist_ok=True)
        temporary = self.runtime_file.with_suffix(".tmp")
        temporary.write_text(
            json.dumps(
                {
                    "pid": os.getpid(),
                    "controlUrl": f"http://127.0.0.1:{self.control_port}",
                    "webUrl": f"http://127.0.0.1:{self.web_port}",
                    "token": self.token,
                },
                ensure_ascii=False,
                indent=2,
            ),
            encoding="utf-8",
        )
        temporary.replace(self.runtime_file)

    def remove_runtime_file(self) -> None:
        try:
            current = json.loads(self.runtime_file.read_text(encoding="utf-8"))
            if current.get("pid") == os.getpid():
                self.runtime_file.unlink(missing_ok=True)
        except (FileNotFoundError, json.JSONDecodeError, OSError):
            pass

    def start_session(self) -> dict[str, Any]:
        return self.session.start()

    def close(self) -> None:
        if self._closing.is_set():
            return
        self._closing.set()
        try:
            self.tasks.close()
        finally:
            self.session.close()
            self.remove_runtime_file()


class ControllerHTTPServer(ThreadingHTTPServer):
    daemon_threads = True

    def __init__(self, address: tuple[str, int], controller: DevController) -> None:
        self.controller = controller
        super().__init__(address, ControllerRequestHandler)


class ControllerRequestHandler(BaseHTTPRequestHandler):
    server: ControllerHTTPServer

    def log_message(self, format: str, *args: Any) -> None:
        return

    def _json(self, status: HTTPStatus, payload: Any) -> None:
        encoded = json.dumps(payload, ensure_ascii=False).encode("utf-8")
        self.send_response(status.value)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(encoded)))
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(encoded)

    def _require_auth(self) -> bool:
        if self.server.controller.authorized(self.headers.get("Authorization")):
            return True
        self._json(HTTPStatus.UNAUTHORIZED, {"error": "unauthorized"})
        return False

    def _read_body(self) -> dict[str, Any]:
        content_type = self.headers.get("Content-Type", "")
        if not content_type.lower().startswith("application/json"):
            raise ValueError("Content-Type 必须是 application/json")
        raw_length = self.headers.get("Content-Length")
        if raw_length is None:
            raise ValueError("缺少 Content-Length")
        try:
            length = int(raw_length)
        except ValueError as exc:
            raise ValueError("Content-Length 无效") from exc
        if length < 0 or length > MAX_REQUEST_BYTES:
            raise ValueError("请求体过大")
        body = self.rfile.read(length)
        try:
            value = json.loads(body or b"{}")
        except json.JSONDecodeError as exc:
            raise ValueError("请求体不是有效 JSON") from exc
        if not isinstance(value, dict):
            raise ValueError("请求体必须是 JSON 对象")
        return value

    def do_GET(self) -> None:  # noqa: N802
        if not self._require_auth():
            return
        parsed = urlparse(self.path)
        controller = self.server.controller
        if parsed.path == "/status":
            self._json(
                HTTPStatus.OK,
                {
                    "controller": {"pid": os.getpid(), "state": "ready"},
                    "session": controller.session.status(),
                },
            )
            return
        if parsed.path == "/logs":
            query = parse_qs(parsed.query)
            try:
                limit = int(query.get("limit", ["100"])[0])
                logs = controller.session.logs(limit)
            except (ValueError, FlutterSessionError) as exc:
                self._json(HTTPStatus.BAD_REQUEST, {"error": str(exc)})
                return
            self._json(HTTPStatus.OK, {"logs": logs})
            return
        if parsed.path.startswith("/tasks/"):
            task_id = parsed.path.removeprefix("/tasks/")
            record = controller.tasks.get(task_id)
            if record is None:
                self._json(HTTPStatus.NOT_FOUND, {"error": "task not found"})
            else:
                self._json(HTTPStatus.OK, record)
            return
        self._json(HTTPStatus.NOT_FOUND, {"error": "not found"})

    def do_POST(self) -> None:  # noqa: N802
        if not self._require_auth():
            return
        parsed = urlparse(self.path)
        controller = self.server.controller
        try:
            payload = self._read_body()
            if parsed.path == "/session/start":
                result = controller.session.start()
            elif parsed.path == "/session/reload":
                result = controller.session.reload(full_restart=False)
            elif parsed.path == "/session/restart":
                result = controller.session.reload(full_restart=True)
            elif parsed.path == "/session/stop":
                result = controller.session.stop()
            elif parsed.path == "/controller/shutdown":
                self._json(HTTPStatus.OK, {"controller": "shutting-down"})
                threading.Thread(target=self.server.shutdown, daemon=True).start()
                return
            elif parsed.path == "/tasks":
                result = controller.tasks.submit(payload)
                self._json(HTTPStatus.ACCEPTED, result)
                return
            else:
                self._json(HTTPStatus.NOT_FOUND, {"error": "not found"})
                return
        except (ValueError, TaskValidationError) as exc:
            self._json(HTTPStatus.BAD_REQUEST, {"error": str(exc)})
            return
        except FlutterSessionError as exc:
            self._json(HTTPStatus.CONFLICT, {"error": str(exc)})
            return
        self._json(HTTPStatus.OK, result)


def parse_args(argv: list[str] | None = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="VaultStream Flutter 开发控制器")
    parser.add_argument("--web-port", type=int, default=8123)
    parser.add_argument("--control-port", type=int, default=8791)
    parser.add_argument(
        "--no-start",
        action="store_true",
        help="只启动控制面，不立即启动 Flutter",
    )
    return parser.parse_args(argv)


def main(argv: list[str] | None = None) -> int:
    args = parse_args(argv)
    for name, port in (("web", args.web_port), ("control", args.control_port)):
        if port < 1 or port > 65535:
            raise SystemExit(f"{name} port 必须在 1 到 65535 之间")

    controller = DevController(_repo_root(), args.web_port, args.control_port)
    try:
        httpd = ControllerHTTPServer(("127.0.0.1", args.control_port), controller)
    except OSError as exc:
        print(f"控制端口启动失败: {exc}", file=sys.stderr)
        return 2
    controller.httpd = httpd
    controller.write_runtime_file()

    def request_shutdown(signum: int, frame: Any) -> None:
        threading.Thread(target=httpd.shutdown, daemon=True).start()

    signal.signal(signal.SIGINT, request_shutdown)
    if hasattr(signal, "SIGTERM"):
        signal.signal(signal.SIGTERM, request_shutdown)

    print(f"控制器: http://127.0.0.1:{args.control_port}")
    print(f"前端目标: http://127.0.0.1:{args.web_port}")
    if not args.no_start:
        try:
            controller.start_session()
            print("Flutter 启动请求已提交；使用 devctl status 查看状态。")
        except FlutterSessionError as exc:
            print(f"Flutter 启动失败: {exc}", file=sys.stderr)
    try:
        httpd.serve_forever(poll_interval=0.25)
    finally:
        httpd.server_close()
        controller.close()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
