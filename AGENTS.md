# AGENTS.md

## Commands
- **Backend tests**: `cd backend && .venv/bin/python -m pytest tests/`
- **Single test**: `cd backend && .venv/bin/python -m pytest tests/test_file.py -k test_name`
- **Start backend**: `./start.sh` (runs at http://localhost:8000)
- **Frontend build**: `cd frontend && flutter build`
- **Frontend analyze**: `cd frontend && flutter analyze`
- **Frontend run**: `cd frontend && flutter run`
- **Code gen (Flutter)**: `cd frontend && dart run build_runner build`

## Architecture
- **Backend**: Python FastAPI + SQLAlchemy + aiosqlite (in `backend/app/`)
- **Frontend**: Flutter with Riverpod, go_router, freezed (in `frontend/lib/`)
- **Database**: SQLite (WAL mode) at `data/vaultstream.db`
- **Media storage**: Local filesystem with SHA256 content-addressing at `data/media/`
- **Adapters**: Platform parsers in `backend/app/adapters/` (Bilibili, Twitter, etc.)

## Code Style
- **Python**: Use async/await, type hints, Pydantic for schemas, Loguru for logging
- **Flutter**: Riverpod for state, freezed for models, flutter_lints rules
- **Naming**: snake_case (Python), camelCase (Dart), PascalCase (classes)
- **Error handling**: Use FastAPI HTTPException, proper async exception handling
- **Imports**: Group stdlib, third-party, local imports; relative imports within app/
- **Design patterns**: Material 3 expressive, adaptive layouts, Clean Architecture for features