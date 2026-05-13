"""Export the FastAPI OpenAPI endpoint inventory as a Markdown table."""

from __future__ import annotations

import sys
from pathlib import Path


def _bootstrap_backend_path() -> None:
    repo_root = Path(__file__).resolve().parents[1]
    backend_dir = repo_root / "backend"
    sys.path.insert(0, str(backend_dir))


def main() -> int:
    _bootstrap_backend_path()
    from loguru import logger

    logger.remove()
    from app.main import app

    print("| Methods | Path |")
    print("| :--- | :--- |")
    for path, methods in sorted(app.openapi()["paths"].items()):
        method_list = ", ".join(
            sorted(method.upper() for method in methods if method.lower() != "parameters")
        )
        print(f"| `{method_list}` | `{path}` |")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
