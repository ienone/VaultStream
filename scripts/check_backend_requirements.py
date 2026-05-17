"""Check backend requirements cover direct imports and pytest plugin fixtures."""

from __future__ import annotations

import ast
import sys
from collections import defaultdict
from importlib import metadata
from pathlib import Path

from packaging.requirements import Requirement
from packaging.utils import canonicalize_name


REPO_ROOT = Path(__file__).resolve().parents[1]
BACKEND_DIR = REPO_ROOT / "backend"
LOCAL_MODULES = {"app", "tests", "scripts"}
STDLIB_MODULES = set(getattr(sys, "stdlib_module_names", set()))
CI_SCRIPT_PATHS = [
    REPO_ROOT / "scripts" / "check_backend_requirements.py",
    REPO_ROOT / "scripts" / "check_database_schema.py",
    REPO_ROOT / "scripts" / "check_openapi_docs.py",
]

PACKAGE_ALIASES = {
    "beautifulsoup4": {"bs4"},
    "google-genai": {"google"},
    "langchain-core": {"langchain_core"},
    "langchain-openai": {"langchain_openai"},
    "pillow": {"PIL"},
    "pip-audit": {"pip_audit"},
    "pydantic-settings": {"pydantic_settings"},
    "pytest-asyncio": {"pytest_asyncio"},
    "pytest-cov": {"pytest_cov"},
    "pytest-env": {"pytest_env"},
    "pytest-httpx": {"pytest_httpx"},
    "pytest-subtests": {"pytest_subtests"},
    "python-dateutil": {"dateutil"},
    "python-dotenv": {"dotenv"},
    "python-telegram-bot": {"telegram"},
}

PLUGIN_FIXTURES = {
    "httpx_mock": "pytest-httpx",
    "mocker": "pytest-mock",
    "requests_mock": "requests-mock",
    "respx_mock": "respx",
    "subtests": "pytest-subtests",
}


def _parse_requirements(path: Path, seen: set[Path] | None = None) -> list[str]:
    seen = seen or set()
    requirements: list[str] = []

    for raw_line in path.read_text(encoding="utf-8").splitlines():
        line = raw_line.split("#", 1)[0].strip()
        if not line:
            continue
        if line.startswith("-r "):
            child = (path.parent / line[3:].strip()).resolve()
            if child not in seen:
                seen.add(child)
                requirements.extend(_parse_requirements(child, seen))
            continue
        requirements.append(canonicalize_name(Requirement(line).name))

    return requirements


def _declared_top_modules(requirements: set[str]) -> set[str]:
    package_to_distributions = metadata.packages_distributions()
    distribution_to_packages: dict[str, set[str]] = defaultdict(set)
    for package, distributions in package_to_distributions.items():
        for distribution in distributions:
            distribution_to_packages[canonicalize_name(distribution)].add(package)

    modules: set[str] = set()
    for requirement in requirements:
        modules.update(distribution_to_packages.get(requirement, set()))
        modules.update(PACKAGE_ALIASES.get(requirement, set()))
    return modules


def _scan_imports(root: Path) -> dict[str, set[str]]:
    return _scan_imports_from_paths([root])


def _scan_imports_from_paths(paths: list[Path]) -> dict[str, set[str]]:
    imports: dict[str, set[str]] = defaultdict(set)
    files: list[Path] = []
    for path in paths:
        if path.is_file():
            files.append(path)
        else:
            files.extend(path.rglob("*.py"))

    for path in sorted(files):
        relative = path.relative_to(REPO_ROOT)
        tree = ast.parse(path.read_text(encoding="utf-8-sig"), filename=str(relative))
        for node in ast.walk(tree):
            if isinstance(node, ast.Import):
                for alias in node.names:
                    imports[alias.name.split(".", 1)[0]].add(str(relative))
            elif isinstance(node, ast.ImportFrom) and node.level == 0 and node.module:
                imports[node.module.split(".", 1)[0]].add(str(relative))
    return imports


def _missing_imports(
    imports: dict[str, set[str]],
    declared_modules: set[str],
) -> dict[str, set[str]]:
    missing: dict[str, set[str]] = {}
    for module, files in imports.items():
        if module in STDLIB_MODULES or module in LOCAL_MODULES:
            continue
        if module not in declared_modules:
            missing[module] = files
    return missing


def _scan_plugin_fixtures(root: Path) -> dict[str, set[str]]:
    fixtures: dict[str, set[str]] = defaultdict(set)
    for path in sorted(root.rglob("*.py")):
        relative = path.relative_to(REPO_ROOT)
        tree = ast.parse(path.read_text(encoding="utf-8-sig"), filename=str(relative))
        for node in ast.walk(tree):
            if not isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef)):
                continue
            for arg in node.args.args:
                if arg.arg in PLUGIN_FIXTURES:
                    fixtures[arg.arg].add(str(relative))
    return fixtures


def _print_missing(title: str, missing: dict[str, set[str]]) -> None:
    if not missing:
        return
    print(title)
    for module, files in sorted(missing.items()):
        sample = ", ".join(sorted(files)[:5])
        print(f"  {module}: {sample}")


def main() -> int:
    runtime_requirements = set(_parse_requirements(BACKEND_DIR / "requirements.txt"))
    dev_requirements = set(_parse_requirements(BACKEND_DIR / "requirements-dev.txt"))

    runtime_modules = _declared_top_modules(runtime_requirements)
    dev_modules = _declared_top_modules(dev_requirements)

    missing_runtime = _missing_imports(_scan_imports(BACKEND_DIR / "app"), runtime_modules)
    missing_tests = _missing_imports(_scan_imports(BACKEND_DIR / "tests"), dev_modules)
    missing_ci_scripts = _missing_imports(_scan_imports_from_paths(CI_SCRIPT_PATHS), dev_modules)

    missing_fixtures: dict[str, set[str]] = {}
    for fixture, files in _scan_plugin_fixtures(BACKEND_DIR / "tests").items():
        required_distribution = canonicalize_name(PLUGIN_FIXTURES[fixture])
        if required_distribution not in dev_requirements:
            missing_fixtures[f"{fixture} -> {required_distribution}"] = files

    if not (missing_runtime or missing_tests or missing_ci_scripts or missing_fixtures):
        print("Backend requirements check passed.")
        return 0

    _print_missing("Runtime imports missing from backend/requirements.txt:", missing_runtime)
    _print_missing("Test imports missing from backend/requirements-dev.txt:", missing_tests)
    _print_missing("CI script imports missing from backend/requirements-dev.txt:", missing_ci_scripts)
    _print_missing("Pytest plugin fixtures missing from backend/requirements-dev.txt:", missing_fixtures)
    return 1


if __name__ == "__main__":
    raise SystemExit(main())
