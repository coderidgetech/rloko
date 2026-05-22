# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

Polyglot monorepo: `backend` (Go API), `frontend` (Vite/React), `mobile-app` (Flutter). All three are git submodules. API contracts must stay coordinated across all clients when shipping features.

## Commands

### Backend (`cd backend`)
```bash
make run          # Run dev server (localhost:8080)
make build        # Compile binary to bin/server
make test         # Run all Go tests
go test ./internal/handlers/...  # Run a single package's tests
make seed         # Seed MongoDB with categories, products, admin user
make docker-up    # Start MongoDB + MinIO via Docker
```

### Frontend (`cd frontend`)
```bash
pnpm dev          # Dev server (localhost:5173)
pnpm build        # Production build to dist/
pnpm fresh        # Clear Vite cache + dev
pnpm build:mobile # Build + Capacitor sync (for native app targets)
```

### Mobile (`cd mobile-app`)
```bash
flutter pub get   # Install dependencies
flutter run       # Run on connected device/emulator
flutter test      # Run widget/unit tests
```

### Droplet deploy (`cd deploy/droplet`)
```bash
./deploy.sh               # Pull GHCR images + restart stack (standard update)
./deploy.sh env           # Restart api with updated .env only (no image pull)
./deploy.sh quick         # Restart without git pull or image pull
./deploy.sh build         # Compile on server (slow fallback)
```

## Architecture

### Backend (`backend/`)
Standard Go layered architecture via `backend/internal/`:
- **`handlers/`** — Gin HTTP handlers (one file per domain: `auth_handler.go`, `product_handler.go`, etc.)
- **`services/`** — Business logic, called by handlers
- **`repositories/`** — MongoDB query layer, called by services
- **`models/`** — Shared data structs (BSON/JSON tags)
- **`middleware/`** — JWT auth, CORS, rate limiting
- **`config/`** — Env-based configuration

Entry point: `cmd/server/main.go`. The API refuses to start in production if `CORS_ALLOWED_ORIGINS` is unset.

### Frontend (`frontend/`)
React 18 + TypeScript + Vite. Path alias `@/` → `frontend/src/`.
- **`src/app/pages/`** — Full page components
- **`src/app/components/`** — Shared components; `ui/` for Radix + Tailwind primitives; `admin/` for admin views
- **`src/app/services/`** — Axios API call wrappers
- **`src/app/context/`** — Global state via React Context: `UserContext`, `CartContext`, `WishlistContext`, `AdminContext`, `SiteConfigContext`, `CurrencyContext`
- **`src/app/lib/api.ts`** — Axios base config (base URL, interceptors)
- **`src/styles/theme.css`** — Tailwind custom theme

The frontend also has Capacitor integration (`pnpm build:mobile`) for packaging as a native iOS/Android app — separate from the Flutter `mobile-app`.

### Mobile app (`mobile-app/`)
Flutter app using **BLoC + Clean Architecture**. Consumer shopping flows only — admin and vendor flows are out of scope.

Feature structure under `lib/features/<feature>/`:
- `data/` — API clients, DTOs, repository implementations
- `domain/` — Entities, use cases, repository interfaces
- `presentation/` — BLoC/Cubit, pages, widgets

Shared infrastructure in `lib/core/`:
- `di/injection.dart` — GetIt dependency injection setup
- `network/` — Dio HTTP client configuration
- `theme/`, `widgets/`, `utils/`, `models/` — Shared utilities

Features: `address`, `auth`, `cart`, `config`, `home`, `onboarding`, `order`, `payment`, `product`, `promotion`, `return_order`, `review`, `rewards`, `shipping`, `video`, `wishlist`.

### Deployment
- **DigitalOcean App Platform**: spec in `app.yaml`. `VITE_*` vars are BUILD_TIME; redeploy the web component after changing them.
- **Droplet**: Docker Compose + Caddy (`deploy/droplet/`). Pre-built GHCR images are the standard path; on-server compilation is a slow fallback.
- CI builds GHCR images `rloco-api` and `rloco-web` on push to `main`.

## Code Style

From `guidelines/Guidelines.md`:
- Small files; extract helpers/components
- Flexbox/Grid by default; avoid absolute positioning unless needed
- Functional React components; custom hooks for reuse
- Colocate styles with components
- One concern per change; skip unrelated refactors

## Environment Setup

Backend `.env` minimum for local dev:
```
PORT=8080
MONGODB_URI=mongodb://admin:password@localhost:27017/rloco?authSource=admin
JWT_SECRET=dev-secret
```

Frontend `.env`:
```
VITE_API_URL=http://localhost:8080/api
```

Copy `.env.example` files in each subproject for the full variable list.
