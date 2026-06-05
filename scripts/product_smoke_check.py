#!/usr/bin/env python
"""Product-level smoke check for a running VaultStream backend.

This script intentionally uses only the Python standard library so it can run
from the project virtualenv or a system Python. It does not create data or call
external platforms; it checks whether the local backend exposes enough status
for a user to decide what to verify next.
"""

from __future__ import annotations

import argparse
import json
import os
import sys
import time
from dataclasses import dataclass
from typing import Any
from urllib.error import HTTPError, URLError
from urllib.parse import urlencode
from urllib.request import Request, urlopen


@dataclass
class Check:
    name: str
    path: str
    auth: bool = True
    query: dict[str, Any] | None = None


CHECKS = [
    Check("backend_health", "/health", auth=False),
    Check("init_status", "/api/v1/init-status"),
    Check("platform_health", "/api/v1/platform-health"),
    Check("ai_capabilities", "/api/v1/ai/capabilities"),
    Check("favorites_sync", "/api/v1/favorites-sync/status"),
    Check("background_diagnostics", "/api/v1/background-tasks/diagnostics"),
    Check("semantic_index", "/api/v1/search/semantic/index-status"),
    Check("discovery_sources", "/api/v1/discovery/sources"),
    Check("distribution_queue", "/api/v1/distribution-queue/stats"),
]


def _url(base_url: str, path: str, query: dict[str, Any] | None = None) -> str:
    url = base_url.rstrip("/") + path
    if query:
        url += "?" + urlencode(query)
    return url


def _request_json(url: str, token: str | None, timeout: float) -> tuple[int, Any]:
    headers = {"Accept": "application/json"}
    if token:
        headers["X-API-Token"] = token
    request = Request(url, headers=headers)
    with urlopen(request, timeout=timeout) as response:
        body = response.read().decode("utf-8", errors="replace")
        if not body:
            return response.status, None
        try:
            return response.status, json.loads(body)
        except json.JSONDecodeError:
            return response.status, body


def _summarize(name: str, data: Any) -> dict[str, Any]:
    if name == "platform_health" and isinstance(data, dict):
        platforms = data.get("platforms") or []
        return {
            "platform_count": len(platforms),
            "error_platforms": [
                item.get("platform")
                for item in platforms
                if item.get("health") == "error"
            ],
        }
    if name == "ai_capabilities" and isinstance(data, dict):
        capabilities = data.get("capabilities") or []
        return {
            "capabilities": {
                item.get("key"): item.get("status")
                for item in capabilities
            }
        }
    if name == "favorites_sync" and isinstance(data, dict):
        return {
            "running": data.get("running"),
            "enabled_platforms": data.get("enabled_platforms") or [],
            "recent_runs": len(data.get("recent_runs") or []),
        }
    if name == "background_diagnostics" and isinstance(data, dict):
        return {
            "task_states": len(data.get("task_states") or []),
            "recent_task_runs": len(data.get("recent_task_runs") or []),
        }
    if name == "semantic_index" and isinstance(data, dict):
        keys = [
            "indexed_total",
            "parse_success_total",
            "pending_total",
            "failed_total",
        ]
        return {key: data.get(key) for key in keys if key in data}
    if name == "discovery_sources" and isinstance(data, list):
        return {"source_count": len(data)}
    return {}


def run_checks(base_url: str, token: str | None, timeout: float) -> dict[str, Any]:
    results: list[dict[str, Any]] = []
    started = time.time()

    for check in CHECKS:
        url = _url(base_url, check.path, check.query)
        try:
            status, data = _request_json(url, token if check.auth else None, timeout)
            ok = 200 <= status < 300
            results.append(
                {
                    "name": check.name,
                    "path": check.path,
                    "ok": ok,
                    "status": status,
                    "summary": _summarize(check.name, data),
                }
            )
        except HTTPError as exc:
            results.append(
                {
                    "name": check.name,
                    "path": check.path,
                    "ok": False,
                    "status": exc.code,
                    "error": exc.read().decode("utf-8", errors="replace")[:500],
                }
            )
        except (TimeoutError, URLError, OSError) as exc:
            results.append(
                {
                    "name": check.name,
                    "path": check.path,
                    "ok": False,
                    "status": None,
                    "error": str(exc),
                }
            )

    return {
        "base_url": base_url,
        "elapsed_ms": round((time.time() - started) * 1000, 2),
        "ok": all(item["ok"] for item in results),
        "results": results,
    }


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Run product smoke checks against a VaultStream backend.")
    parser.add_argument("--base-url", default=os.getenv("VAULTSTREAM_BASE_URL", "http://127.0.0.1:8000"))
    parser.add_argument("--api-token", default=os.getenv("API_TOKEN") or os.getenv("VAULTSTREAM_API_TOKEN"))
    parser.add_argument("--timeout", type=float, default=10.0)
    args = parser.parse_args(argv)

    report = run_checks(args.base_url, args.api_token, args.timeout)
    print(json.dumps(report, ensure_ascii=False, indent=2))
    return 0 if report["ok"] else 1


if __name__ == "__main__":
    sys.exit(main())
