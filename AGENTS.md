# AGENTS Guide

This repository is a polyglot monorepo with Go backend APIs, React web frontend, and a Flutter mobile app.
Coordinate API contracts across `backend`, `frontend`, and `mobile-app` when shipping features.

| Area | Path | Role |
|---|---|---|
| API service | `backend/` | REST API, auth, business logic |
| Web client | `frontend/` | E-commerce web UI |
| Mobile client | `mobile-app/` | Flutter mobile experience |

## Key Paths

| Concern | Path |
|---|---|
| Backend handlers | `backend/internal/handlers` |
| Backend services | `backend/internal/services` |
| Frontend pages | `frontend/src/app/pages` |
| Frontend components | `frontend/src/app/components` |
| Frontend services | `frontend/src/app/services` |
| Mobile features | `mobile-app/lib/features` |

## Build/Run

- Backend: `cd backend && make run`
- Frontend: `cd frontend && pnpm dev`
- Mobile: `cd mobile-app && flutter run`
