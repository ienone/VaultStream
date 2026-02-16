# AGENTS.md — VaultStream

## Build / Test Commands
- **Backend (Python/FastAPI):** `cd backend && .venv/Scripts/python -m pytest tests/` (Windows) or `.venv/bin/python -m pytest tests/` (Linux). Single test: `pytest tests/test_file.py -k test_name`. Config in `backend/pytest.ini` (asyncio_mode=auto).
- **Frontend (Flutter/Dart):** `cd frontend && flutter test` for all tests, `flutter test test/unit/queue_item_test.dart` for a single test. Run `dart run build_runner build` after modifying models/freezed classes. Lint: `flutter analyze`. Format: `dart format lib/`.
- **Backend start:** `cd backend && python -m uvicorn app.main:app --reload`. Frontend start: `cd frontend && flutter run -d chrome`.

## Architecture
- **Backend:** FastAPI + SQLite (aiosqlite, WAL mode). Layered: `routers/` → `services/` → `repositories/` → `models.py` (SQLAlchemy ORM). Pydantic schemas in `schemas.py`. Platform adapters in `adapters/` (bilibili, twitter, xiaohongshu, zhihu, weibo). Async task queue in `worker/`. Push engine in `push/`. Config via `.env` + `core/config.py`.
- **Frontend:** Flutter 3.10+ with Riverpod (riverpod_generator) for state, Dio for HTTP, go_router for routing, freezed + json_serializable for models. Feature-based structure under `lib/features/` (collection, review, dashboard, settings, bot, share_receiver). Core utilities in `lib/core/` (network, providers, services, widgets). Material 3 theming via `lib/theme/`.
- **Database:** SQLite at `backend/data/vaultstream.db`. Media stored locally with SHA256-addressed files in `backend/data/media/`.
- **API:** REST at `http://localhost:8000/api/v1/`. Docs at `/docs` (Swagger) and `/redoc`. See `docs/API.md`.

## Code Style
- **Python:** PEP 8, type hints required. Async/await throughout. Loguru for logging. No print statements.
- **Dart:** Follow Effective Dart. Use `freezed` + `json_serializable` for data classes (run `build_runner` after changes). Riverpod with code generation (`@riverpod` annotations). Lints from `package:flutter_lints`. Prefer `const` constructors. Use `gap` package for spacing, not `SizedBox`.
- **Naming:** Python: snake_case. Dart: camelCase for variables/methods, PascalCase for classes, snake_case for file names.
- **Imports:** Dart: relative imports within the package. Python: absolute imports from `app.*`.
- **Error handling:** Backend raises HTTPException with appropriate status codes. Frontend uses Dio interceptors for API errors.
- **Comments/docs:** Chinese or English both acceptable. Keep commit messages clear.
