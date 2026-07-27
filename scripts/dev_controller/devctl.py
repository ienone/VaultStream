from __future__ import annotations

import argparse
import json
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path
from typing import Any


def _repo_root() -> Path:
    return Path(__file__).resolve().parents[2]


class ClientError(RuntimeError):
    pass


class DevControllerClient:
    def __init__(self, runtime_file: Path) -> None:
        try:
            runtime = json.loads(runtime_file.read_text(encoding="utf-8"))
            self.base_url = runtime["controlUrl"]
            self.token = runtime["token"]
        except (FileNotFoundError, KeyError, json.JSONDecodeError) as exc:
            raise ClientError("找不到有效的 .runtime/dev-controller.json") from exc

    def request(
        self,
        method: str,
        path: str,
        payload: dict[str, Any] | None = None,
        timeout: float = 130,
    ) -> Any:
        data = None
        headers = {"Authorization": f"Bearer {self.token}"}
        if payload is not None:
            data = json.dumps(payload, ensure_ascii=False).encode("utf-8")
            headers["Content-Type"] = "application/json"
        request = urllib.request.Request(
            f"{self.base_url}{path}",
            data=data,
            headers=headers,
            method=method,
        )
        try:
            with urllib.request.urlopen(request, timeout=timeout) as response:
                return json.loads(response.read())
        except urllib.error.HTTPError as exc:
            try:
                detail = json.loads(exc.read()).get("error", str(exc))
            except json.JSONDecodeError:
                detail = str(exc)
            raise ClientError(detail) from exc
        except urllib.error.URLError as exc:
            raise ClientError(f"无法连接开发控制器: {exc.reason}") from exc


def _print_json(value: Any) -> None:
    print(json.dumps(value, ensure_ascii=False, indent=2))


def _wait_for_task(
    client: DevControllerClient,
    record: dict[str, Any],
    timeout: float,
) -> int:
    task_id = record["taskId"]
    deadline = time.monotonic() + timeout
    while True:
        current = client.request("GET", f"/tasks/{task_id}")
        if current["state"] in {"completed", "failed"}:
            if current.get("stdout"):
                print(current["stdout"], end="" if current["stdout"].endswith("\n") else "\n")
            if current.get("stderr"):
                print(current["stderr"], file=sys.stderr)
            if current.get("error"):
                print(current["error"], file=sys.stderr)
            return 0 if current["state"] == "completed" else 1
        if time.monotonic() >= deadline:
            raise ClientError(f"等待任务 {task_id} 超时；任务仍在后台运行")
        time.sleep(0.5)


def parse_args(argv: list[str] | None = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="VaultStream 开发控制器客户端")
    subparsers = parser.add_subparsers(dest="command", required=True)
    for command in ("status", "start", "reload", "restart", "stop", "shutdown"):
        subparsers.add_parser(command)
    logs = subparsers.add_parser("logs")
    logs.add_argument("--limit", type=int, default=100)
    for command in ("generate", "analyze", "format-check"):
        task = subparsers.add_parser(command)
        task.add_argument("--no-wait", action="store_true")
        task.add_argument("--timeout", type=float, default=600)
    test = subparsers.add_parser("test")
    test.add_argument("target", nargs="?")
    test.add_argument(
        "--reporter",
        choices=("compact", "expanded", "json"),
        default="compact",
    )
    test.add_argument("--no-wait", action="store_true")
    test.add_argument("--timeout", type=float, default=600)
    return parser.parse_args(argv)


def main(argv: list[str] | None = None) -> int:
    args = parse_args(argv)
    try:
        client = DevControllerClient(_repo_root() / ".runtime" / "dev-controller.json")
        if args.command == "status":
            _print_json(client.request("GET", "/status"))
            return 0
        if args.command == "logs":
            query = urllib.parse.urlencode({"limit": args.limit})
            _print_json(client.request("GET", f"/logs?{query}"))
            return 0
        if args.command in {"start", "reload", "restart", "stop"}:
            _print_json(client.request("POST", f"/session/{args.command}", {}))
            return 0
        if args.command == "shutdown":
            _print_json(client.request("POST", "/controller/shutdown", {}))
            return 0

        payload: dict[str, Any] = {"task": args.command}
        if args.command == "test":
            if args.target is not None:
                payload["target"] = args.target
            payload["reporter"] = args.reporter
        record = client.request("POST", "/tasks", payload)
        if args.no_wait:
            _print_json(record)
            return 0
        return _wait_for_task(client, record, args.timeout)
    except ClientError as exc:
        print(f"错误: {exc}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
