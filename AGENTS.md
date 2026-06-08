# Repository Guidelines

## Project Structure & Module Organization
VaultStream is split into a Python backend and a Flutter frontend:
- `backend/app/`: FastAPI application code (`routers/`, `services/`, `repositories/`, `adapters/`, `tasks/`, `core/`).
- `backend/tests/`: backend pytest suites (`test_api/`, `test_adapters/`, `test_tasks/`, etc.).
- `frontend/lib/`: Flutter app code, organized by feature (`features/`) and shared layers (`core/`, `routing/`, `theme/`).
- `frontend/test/`: Flutter unit and widget tests.
- `docs/`: architecture notes and API/database docs.
- `scripts/`: utility scripts.

## Build, Test, and Development Commands
- Backend setup: `cd backend && pip install -r requirements-dev.txt`
- Start backend locally (Windows): `cd backend && ./start.ps1`
- Start backend locally (Linux/macOS): `cd backend && ./start.sh`
- Backend tests: `cd backend && pytest`
- Frontend setup: `cd frontend && flutter pub get`
- Frontend codegen: `cd frontend && dart run build_runner build --delete-conflicting-outputs`
- Frontend run (web): `cd frontend && flutter run -d chrome`
- Frontend checks: `cd frontend && flutter analyze && flutter test`
- Docker stack (service deployment): `cd backend && docker compose up -d`

## Coding Style & Naming Conventions
- Python: 4-space indentation, type hints where practical, `snake_case` for functions/files, `PascalCase` for classes.
- Dart/Flutter: follow `flutter_lints` (`frontend/analysis_options.yaml`), use `lowerCamelCase` for members, `UpperCamelCase` for types, and `snake_case.dart` filenames.
- Keep modules focused: adapters parse/fetch, services orchestrate business logic, routers stay thin.
- Frontend UI should follow Material 3 expressive patterns with clear hierarchy and intentional color/shape choices.
- Implement responsive behavior for portrait and landscape (phone/tablet/desktop) and validate core screens at multiple breakpoints.
- Use smooth, purposeful motion with consistent durations/curves to avoid jank.

## Testing Guidelines
- Backend uses `pytest` with coverage enabled by default (`backend/pytest.ini`, `.coveragerc`).
- Backend must run with the project virtualenv Python (repo root `.venv`), not a global/system interpreter.
  - Windows example: `.venv\Scripts\python.exe -m pytest backend/tests -q`
  - This avoids environment drift issues.
- Mark external/integration tests with `@pytest.mark.integration`.
- Add tests near the changed area (e.g., new API route -> `backend/tests/test_api/`).
- Flutter changes should include `flutter test` updates in `frontend/test/unit` or `frontend/test/widget`.
- Keep formal, repeatable backend tests under `backend/tests/` so new test files are visible to Git by default.
- Put local-only probes, real-platform debugging scripts, cookie/database-dependent checks, and captured outputs under `backend/manual_tests/`. That directory is ignored and must not be used for CI or normal acceptance evidence.
- Do not add individual backend test filenames to `.gitignore`. If a file is not suitable for normal collection, move it out of `backend/tests/` or convert it into a repeatable test with explicit skips/markers.

## Commit & Pull Request Guidelines
- Follow Conventional Commit style seen in history: `feat: ...`, `fix(scope): ...`, `chore: ...` (scopes like `backend`, `frontend`, `adapters` are common).
- Keep commits focused and atomic; avoid mixing backend/frontend refactors without need.
- PRs should include:
  - concise summary and motivation,
  - linked issue/task (if any),
  - validation evidence (`pytest`, `flutter analyze`, `flutter test`),
  - screenshots for UI changes.

## Security & Configuration Tips
- Use `backend/.env.example` as the template; never commit real secrets in `.env`.
- Keep API tokens, bot credentials, and keystores out of git.
