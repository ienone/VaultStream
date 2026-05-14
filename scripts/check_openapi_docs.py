"""Check that docs/API.md contains the current FastAPI endpoint inventory."""

from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path


ENDPOINT_ROW = re.compile(r"^\|\s*`(?P<methods>[^`]+)`\s*\|\s*`(?P<path>[^`]+)`\s*\|")


def _bootstrap_backend_path() -> Path:
    repo_root = Path(__file__).resolve().parents[1]
    backend_dir = repo_root / "backend"
    sys.path.insert(0, str(backend_dir))
    return repo_root


def _openapi_inventory() -> dict[str, str]:
    from loguru import logger

    logger.remove()
    from app.main import app

    inventory: dict[str, str] = {}
    for path, methods in sorted(app.openapi()["paths"].items()):
        method_list = ", ".join(
            sorted(method.upper() for method in methods if method.lower() != "parameters")
        )
        inventory[path] = method_list
    return inventory


def _docs_inventory(api_doc: Path) -> dict[str, str]:
    inventory: dict[str, str] = {}
    for line in api_doc.read_text(encoding="utf-8").splitlines():
        match = ENDPOINT_ROW.match(line.strip())
        if match:
            inventory[match.group("path")] = match.group("methods")
    return inventory


def main() -> int:
    repo_root = _bootstrap_backend_path()
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "api_doc",
        nargs="?",
        default=str(repo_root / "docs" / "API.md"),
        help="Path to docs/API.md",
    )
    args = parser.parse_args()

    api_doc = Path(args.api_doc)
    if not api_doc.is_absolute():
        api_doc = (Path.cwd() / api_doc).resolve()

    expected = _openapi_inventory()
    actual = _docs_inventory(api_doc)

    missing = sorted(set(expected) - set(actual))
    stale = sorted(set(actual) - set(expected))
    method_mismatch = sorted(
        path for path in set(expected) & set(actual) if expected[path] != actual[path]
    )

    if not (missing or stale or method_mismatch):
        print(f"OpenAPI docs check passed: {len(expected)} endpoints covered.")
        return 0

    if missing:
        print("Missing endpoints in docs/API.md:")
        for path in missing:
            print(f"  | `{expected[path]}` | `{path}` |")
    if stale:
        print("Stale endpoints in docs/API.md:")
        for path in stale:
            print(f"  | `{actual[path]}` | `{path}` |")
    if method_mismatch:
        print("Method mismatches in docs/API.md:")
        for path in method_mismatch:
            print(f"  {path}: docs={actual[path]} openapi={expected[path]}")

    return 1


if __name__ == "__main__":
    raise SystemExit(main())
