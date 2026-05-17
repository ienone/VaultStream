# Root command shortcuts for VaultStream.

.DEFAULT_GOAL := help

BACKEND_DIR := backend
FRONTEND_DIR := frontend

ifeq ($(OS),Windows_NT)
SHELL := cmd.exe
.SHELLFLAGS := /C
PYTHON ?= .venv/Scripts/python.exe
BACKEND_START ?= powershell -NoProfile -ExecutionPolicy Bypass -File $(BACKEND_DIR)/start.ps1
else
PYTHON ?= .venv/bin/python
BACKEND_START ?= cd $(BACKEND_DIR) && ./start.sh
endif

PIP ?= $(PYTHON) -m pip
PYTEST ?= $(PYTHON) -m pytest
FLUTTER ?= flutter
DART ?= dart
DOCKER_COMPOSE ?= docker compose

.PHONY: help install backend-install frontend-install dev-backend dev-frontend \
	test test-backend test-backend-fast test-frontend frontend-check frontend-analyze \
	codegen build-web docker-up docker-down docker-logs check-openapi check-schema

help:
	@echo VaultStream make targets:
	@echo Setup:
	@echo   make install             Install backend and frontend dependencies
	@echo   make backend-install     Install backend dev dependencies with the repo venv
	@echo   make frontend-install    Run flutter pub get
	@echo Development:
	@echo   make dev-backend         Start the FastAPI backend
	@echo   make dev-frontend        Run the Flutter web app in Chrome
	@echo   make codegen             Run Flutter/Dart code generation
	@echo   make build-web           Build the Flutter web release bundle
	@echo Verification:
	@echo   make test                Run backend and frontend tests
	@echo   make test-backend        Run all backend pytest tests
	@echo   make test-backend-fast   Run backend tests excluding integration tests
	@echo   make frontend-check      Run flutter analyze and flutter test
	@echo Deployment:
	@echo   make docker-up           Start backend/docker-compose.yml services
	@echo   make docker-down         Stop backend/docker-compose.yml services
	@echo   make docker-logs         Follow Docker compose logs

install: backend-install frontend-install

backend-install:
	$(PIP) install -r $(BACKEND_DIR)/requirements-dev.txt

frontend-install:
	cd $(FRONTEND_DIR) && $(FLUTTER) pub get

dev-backend:
	$(BACKEND_START)

dev-frontend:
	cd $(FRONTEND_DIR) && $(FLUTTER) run -d chrome

test: test-backend test-frontend

test-backend:
	$(PYTEST) $(BACKEND_DIR)/tests -q

test-backend-fast:
	$(PYTEST) $(BACKEND_DIR)/tests -q -m "not integration"

test-frontend:
	cd $(FRONTEND_DIR) && $(FLUTTER) test

frontend-check: frontend-analyze test-frontend

frontend-analyze:
	cd $(FRONTEND_DIR) && $(FLUTTER) analyze

codegen:
	cd $(FRONTEND_DIR) && $(DART) run build_runner build --delete-conflicting-outputs

build-web:
	cd $(FRONTEND_DIR) && $(FLUTTER) build web --release

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
