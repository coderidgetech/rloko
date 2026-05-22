# Rloko — top-level convenience targets. Run from the monorepo root.

LOCAL_COMPOSE = docker compose -f deploy/local/docker-compose.yml --env-file deploy/local/.env

.PHONY: help setup \
        local local-up local-down local-logs local-build local-restart \
        local-mobile local-mobile-dev local-mobile-prod \
        deploy-dev deploy-prod

help:
	@echo ""
	@echo "First-time setup"
	@echo "  make setup               Copy env templates and fill in secrets"
	@echo ""
	@echo "Local development  (everything in Docker)"
	@echo "  make local               Build + start all services (blocks, shows logs)"
	@echo "  make local-up            Build + start in background"
	@echo "  make local-down          Stop and remove containers"
	@echo "  make local-build         Rebuild images (after code changes)"
	@echo "  make local-restart       Rebuild + restart a single service: make local-restart svc=api"
	@echo "  make local-logs          Follow logs (all services)"
	@echo ""
	@echo "  Frontend → http://localhost:3000"
	@echo "  API      → http://localhost:8080"
	@echo "  MinIO    → http://localhost:9001  (admin console)"
	@echo ""
	@echo "Mobile"
	@echo "  make local-mobile        Flutter → local Docker API"
	@echo "  make local-mobile-dev    Flutter → dev.rloko.com"
	@echo "  make local-mobile-prod   Flutter → rloko.com"
	@echo ""
	@echo "Deploy  (run on the target server)"
	@echo "  make deploy-dev          Deploy to dev.rloko.com"
	@echo "  make deploy-prod         Deploy to rloko.com"
	@echo ""

# ── First-time setup ──────────────────────────────────────────────────────────
setup:
	@[ -f deploy/local/.env ] \
	  || (cp deploy/local/.env.example deploy/local/.env \
	      && echo "Created deploy/local/.env — fill in your secrets")
	@[ -f mobile-app/assets/env/app.env ] \
	  || (cp mobile-app/assets/env/app.local.env mobile-app/assets/env/app.env \
	      && echo "Created mobile-app/assets/env/app.env")
	@[ -f deploy/droplet/.env.dev ] \
	  || (cp deploy/droplet/.env.dev.example deploy/droplet/.env.dev \
	      && echo "Created deploy/droplet/.env.dev — fill in dev secrets")
	@[ -f deploy/droplet/.env.prod ] \
	  || (cp deploy/droplet/.env.prod.example deploy/droplet/.env.prod \
	      && echo "Created deploy/droplet/.env.prod — fill in prod secrets")
	@echo ""
	@echo "Next: edit deploy/local/.env with your real API keys, then: make local"

# ── Local development (Docker) ────────────────────────────────────────────────
local:
	$(LOCAL_COMPOSE) up --build

local-up:
	$(LOCAL_COMPOSE) up --build -d

local-down:
	$(LOCAL_COMPOSE) down

local-build:
	$(LOCAL_COMPOSE) build

local-restart:
	$(LOCAL_COMPOSE) up --build -d --no-deps $(svc)

local-logs:
	$(LOCAL_COMPOSE) logs -f

# ── Mobile ────────────────────────────────────────────────────────────────────
local-mobile:
	cd mobile-app && flutter run --dart-define-from-file=assets/env/app.env

local-mobile-dev:
	cd mobile-app && flutter run --dart-define-from-file=assets/env/app.dev.env

local-mobile-prod:
	cd mobile-app && flutter run --dart-define-from-file=assets/env/app.prod.env

# ── Deploy (run on the target server) ────────────────────────────────────────
deploy-dev:
	cd deploy/droplet && ./deploy.sh ghcr --env dev

deploy-prod:
	cd deploy/droplet && ./deploy.sh ghcr --env prod
