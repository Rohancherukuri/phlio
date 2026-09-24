# Phlio — convenience commands for the whole monorepo.
# Run `make help` to see everything.

.PHONY: help \
	core-build core-test core-run \
	backend-install backend-run backend-test backend-lint \
	frontend-get frontend-run frontend-analyze \
	docker-up docker-up-full docker-down \
	dev

help:
	@echo "Phlio monorepo — common commands"
	@echo ""
	@echo "  Rust core engine (phlio_core/):"
	@echo "    make core-build       cargo build --release"
	@echo "    make core-test        cargo test"
	@echo ""
	@echo "  Backend (backend/, Python 3.12 + uv):"
	@echo "    make backend-install  uv sync"
	@echo "    make backend-run      uv run uvicorn app.main:app --reload"
	@echo "    make backend-test     uv run pytest"
	@echo "    make backend-lint     uv run ruff check ."
	@echo ""
	@echo "  Frontend (frontend/ui/, Flutter):"
	@echo "    make frontend-get     flutter pub get"
	@echo "    make frontend-run     flutter run"
	@echo "    make frontend-analyze flutter analyze"
	@echo ""
	@echo "  Docker:"
	@echo "    make docker-up        backend only, in-memory database"
	@echo "    make docker-up-full   backend + SurrealDB + Redis"
	@echo "    make docker-down      stop everything"
	@echo ""
	@echo "  make dev               build the core engine, then run the backend"
	@echo "                         with reload — the fastest path to a working API"

# -- Rust core engine ---------------------------------------------------------
core-build:
	cd phlio_core && cargo build --release

core-test:
	cd phlio_core && cargo test

core-run:
	cd phlio_core && cargo run --release --bin phlio-core -- $(ARGS)

# -- Backend --------------------------------------------------------------------
backend-install:
	cd backend && uv sync

backend-run:
	cd backend && uv run uvicorn app.main:app --reload --port 8000

backend-test:
	cd backend && uv run pytest -v

backend-lint:
	cd backend && uv run ruff check .

# -- Frontend ---------------------------------------------------------------------
frontend-get:
	cd frontend/ui && flutter pub get

frontend-run:
	cd frontend/ui && flutter run

frontend-analyze:
	cd frontend/ui && flutter analyze

# -- Docker -----------------------------------------------------------------------
docker-up:
	docker compose up --build

docker-up-full:
	docker compose --profile full up --build

docker-down:
	docker compose --profile full down

# -- One-shot local dev ------------------------------------------------------------
dev: core-build backend-install backend-run
