# Root command shortcuts for VaultStream.

.DEFAULT_GOAL := help

BACKEND_DIR := backend
FRONTEND_DIR := frontend

ifeq ($(OS),Windows_NT)
SHELL := cmd.exe
.SHELLFLAGS := /C
PYTHON ?= .venv/Scripts/python.exe
else
PYTHON ?= .venv/bin/python
endif

PIP ?= $(PYTHON) -m pip
PYTEST ?= $(PYTHON) -m pytest
FLUTTER ?= flutter
DART ?= dart
DOCKER_COMPOSE ?= docker compose
BACKEND_PYTHON := $(abspath $(PYTHON))
FRONTEND_ADAPT := tool/dependencies/ensure_inactive_branch_back_navigation.dart

.PHONY: help install backend-install frontend-install dev-backend dev-frontend \
	test test-backend test-frontend frontend-prepare frontend-check frontend-analyze \
	codegen build-web docker-up docker-down docker-logs check-openapi check-schema

help:
	@echo VaultStream make targets:
	@echo Setup:
	@echo   make install             Install backend and frontend dependencies
	@echo   make backend-install     Install backend dev dependencies with the repo venv
	@echo   make frontend-install    Resolve Flutter dependencies and apply router adaptation
	@echo Development:
	@echo   make dev-backend         Start the FastAPI backend
	@echo   make dev-frontend        Run the Flutter web app in Chrome
	@echo   make codegen             Run Flutter/Dart code generation
	@echo   make build-web           Build the Flutter web release bundle
	@echo Verification:
	@echo   make test                Run backend and frontend tests
	@echo   make test-backend        Run maintained backend regressions without external integration
	@echo   make test-frontend       Run maintained frontend regressions
	@echo   make frontend-prepare    Apply required adaptation to resolved dependencies
	@echo   make frontend-analyze    Run flutter analyze
	@echo   make frontend-check      Run flutter analyze and flutter test
	@echo   make check-openapi       Check endpoint docs and response contracts
	@echo   make check-schema        Check fresh database schema
	@echo Deployment:
	@echo   make docker-up           Start backend/docker-compose.yml services
	@echo   make docker-down         Stop backend/docker-compose.yml services
	@echo   make docker-logs         Follow Docker compose logs

install: backend-install frontend-install

backend-install:
	$(PIP) install -r $(BACKEND_DIR)/requirements-dev.txt

frontend-install:
	cd $(FRONTEND_DIR) && $(FLUTTER) pub get
	cd $(FRONTEND_DIR) && $(DART) run $(FRONTEND_ADAPT)

frontend-prepare:
	cd $(FRONTEND_DIR) && $(DART) run $(FRONTEND_ADAPT)

dev-backend:
	cd $(BACKEND_DIR) && "$(BACKEND_PYTHON)" -m app.main

dev-frontend: frontend-prepare
	cd $(FRONTEND_DIR) && $(FLUTTER) run -d chrome

test: test-backend test-frontend

test-backend:
	$(PYTEST) $(BACKEND_DIR)/tests -q

test-frontend: frontend-prepare
	cd $(FRONTEND_DIR) && $(FLUTTER) test

frontend-check: frontend-analyze test-frontend

frontend-analyze: frontend-prepare
	cd $(FRONTEND_DIR) && $(FLUTTER) analyze

codegen:
	cd $(FRONTEND_DIR) && $(DART) run build_runner build --delete-conflicting-outputs

build-web: frontend-prepare
	cd $(FRONTEND_DIR) && $(FLUTTER) build web --release --dart-define=DEBUG_LOG=false

docker-up:
	cd $(BACKEND_DIR) && $(DOCKER_COMPOSE) up -d

docker-down:
	cd $(BACKEND_DIR) && $(DOCKER_COMPOSE) down

docker-logs:
	cd $(BACKEND_DIR) && $(DOCKER_COMPOSE) logs -f

check-openapi:
	$(PYTHON) scripts/check_openapi_docs.py

check-schema:
	$(PYTHON) scripts/check_database_schema.py
