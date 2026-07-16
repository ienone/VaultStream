from __future__ import annotations

import argparse
import os
import sys
from pathlib import Path
from unittest.mock import patch


def _bootstrap_backend_path() -> Path:
    repo_root = Path(__file__).resolve().parents[1]
    sys.path.insert(0, str(repo_root / "backend"))
    return repo_root


def _render() -> str:
    # OpenAPI generation is metadata-only. Avoid creating the default relative
    # SQLite directory when importing the application from the repository root.
    os.environ["SQLITE_DB_PATH"] = ":memory:"
    from app.core import logging as app_logging

    app_logging.logger.remove()
    with patch.object(app_logging, "setup_logging"):
        from app.main import app

    lines = [
        "# OpenAPI 端点清单",
        "",
        "## 文档状态",
        "",
        "active",
        "",
        "> 本文件由 `scripts/export_openapi_endpoints.py` 从当前 FastAPI OpenAPI 生成，不手工补写行为说明。",
        "",
        "| Methods | Path |",
        "| :--- | :--- |",
    ]
    for path, methods in sorted(app.openapi()["paths"].items()):
        method_list = ", ".join(
            sorted(method.upper() for method in methods if method.lower() != "parameters")
        )
        lines.append(f"| `{method_list}` | `{path}` |")
    return "\n".join(lines) + "\n"


def main() -> int:
    repo_root = _bootstrap_backend_path()
    parser = argparse.ArgumentParser(description="Export the FastAPI endpoint inventory.")
    parser.add_argument(
        "--out",
        type=Path,
        help="Write the generated Markdown to this path instead of stdout.",
    )
    args = parser.parse_args()

    rendered = _render()
    if args.out is None:
        print(rendered, end="")
        return 0

    output = args.out if args.out.is_absolute() else repo_root / args.out
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(rendered, encoding="utf-8")
    print(f"Wrote {output}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
