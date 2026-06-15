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

## Cross-cutting systems (read before touching commerce features)

These span backend + both clients; understanding them requires reading multiple files.

### Region / market model
The app is multi-market (**IN** / **US**), driving both currency and catalog visibility.
- Products are filtered by a `?market=` query param (`IN`/`US`) on the product endpoints; clients derive market from the user's region/pincode, not a manual currency toggle.
- `GET /api/region/resolve?pincode=&country=&city=` maps a pincode/ZIP → market + currency + availability (6-digit→IN, 5/5+4→US). It also returns `enabled` / `comingSoonMessage` from the live site config (`general.regions`), so clients can gate "coming soon" markets at entry.
- Region availability is admin-config (`general.regions[market].enabled/comingSoonMessage`), read by the order flow and the resolver via a shared helper. A market with no config row defaults to enabled.
- **Contract coordination:** market/region behavior must stay aligned across backend, `frontend`, and Flutter `mobile-app`.

### Shipping & order tracking
- **Provider split by region:** India → **Shiprocket**, everything else → **Shippo** (`services/shipping_service.go`). Shippo returns a label URL; Shiprocket does not.
- Fulfilling an order (`POST /orders/:id/fulfill`) buys a label, stores `tracking_number`, and moves status to `shipped`.
- **Tracking is webhook-driven, not polled.** `POST /api/webhooks/{shippo,shiprocket}` match the order by tracking number, append to `order_tracking_updates`, and auto-advance status (`TRANSIT`→shipped, `DELIVERED`→delivered). There is **no reconciliation cron** — a missed webhook is never retried. `FAILURE`/`RETURNED`/`EXCEPTION` currently only email; they don't change status.
- Shippo webhook delivery requires the endpoint be **registered in the Shippo dashboard** (not done in code). `SHIPPO_WEBHOOK_SECRET`: the handler verifies an HMAC `Shippo-Webhook-Signature`; standard Shippo does **not** send that header, so leaving the secret unset (skips verification) is currently required or real webhooks 401.

### Payments & tax
- Stripe for cards/UPI (`services/payment_service.go`). US sales tax uses the **Stripe Tax Calculation API** (`services/stripe_us_tax.go`) — it requires either `STRIPE_TAX_PRODUCT_CODE` (a `txcd_…` code; clothing is `txcd_30011000`) or a **default tax code set in the Stripe dashboard**, else checkout 400s on `line_items[0][tax_code]`. India uses a GST path (`OrderIndiaDefaultGSTPercent`).

### Transactional email
- **Resend** (`services/email_service.go`, `https://api.resend.com/emails`). Requires **both** `RESEND_API_KEY` and `SMTP_FROM`, and the `SMTP_FROM` domain must be **verified in Resend** or sends 403. If unset, emails are silently skipped with a startup warning.

## Non-obvious gotchas

- **`rloco` vs `rloko`:** the product rebranded to **Rloko** but many identifiers still use the old **`rloco`** spelling — the Mongo database name is hardcoded `client.Database("rloco")` (`repositories/mongodb.go`), GHCR images are `rloco-api`/`rloco-web`, and default sender/emails use `@rloco.com`. Expect both spellings; don't "fix" one assuming it's a typo.
- **Mongo in prod is a managed cluster**, not the `mongo` container in the droplet compose (that container is unused by the API). The API connects via `MONGODB_URI` (DigitalOcean managed Mongo); DB name is `rloco`.
- **Droplet env layering:** the API container loads its runtime env from the **literal `.env`** file (`env_file: - .env`). The `.env.dev` / `.env.prod` files are only used by `deploy.sh --env dev|prod` for compose interpolation (image tags, `PUBLIC_DOMAIN`) — they are **not** injected into the container. Put runtime secrets in `.env`. `./deploy.sh env` **recreates** the api (a plain `docker compose restart` won't reload `env_file`).
- **Live backend host:** `dev.rloko.com` (the droplet, behind Caddy) is the reachable API; `rloko.com` is currently a parked page, not the app.
- **Mobile flavors:** the app selects its env at runtime from `APP_FLAVOR` (a dart-define, default `local`) → loads `assets/env/app.$flavor.env`. Android has real Gradle product flavors (`dev`/`local` with `.dev` suffix), but **iOS flavors are incomplete** — `flutter run --flavor dev` fails because `Debug-dev`/`Release-dev` build configs don't exist. On iOS, run without `--flavor`: `flutter run --dart-define-from-file=assets/env/app.dev.env` (or `--dart-define=APP_FLAVOR=dev --dart-define=API_BASE_URL=…`). Mobile API base URL resolves via `core/network/base_url_resolver.dart` (dart-define → env file → emulator localhost default).

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
