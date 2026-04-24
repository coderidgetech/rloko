#!/usr/bin/env bash
# Run the Go seed (admin, categories, videos, products) against Mongo used by docker compose.
# Requires: stack up (mongo healthy), backend/ at monorepo root, Docker, internet (go modules on first run).
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
RLOKO_ROOT="$(cd "$DIR/../.." && pwd)"
BACKEND="$RLOKO_ROOT/backend"
COMPOSE=(docker compose -f "$DIR/docker-compose.ghcr.yml")

if [ ! -f "$DIR/.env" ]; then
  echo "No $DIR/.env" >&2
  exit 1
fi
if [ ! -d "$BACKEND/migrations" ]; then
  echo "No backend at $BACKEND (clone rloko with submodules)" >&2
  exit 1
fi

# MONGODB_URI=... (single line, not commented)
MONGODB_URI=$(grep -E '^[[:space:]]*MONGODB_URI=' "$DIR/.env" | head -1 | cut -d= -f2- | tr -d '\r' | sed 's/^[[:space:]]"//;s/"[[:space:]]*$//')
if [ -z "$MONGODB_URI" ]; then
  echo "Set MONGODB_URI= in $DIR/.env" >&2
  exit 1
fi

MONGO_CID=$("${COMPOSE[@]}" ps -q mongo 2>/dev/null | head -1)
if [ -z "${MONGO_CID:-}" ]; then
  echo "Mongo container not running. Start: cd $DIR && ./deploy.sh" >&2
  exit 1
fi

NET=$(docker inspect -f '{{range $k, $v := .NetworkSettings.Networks}}{{$k}} {{end}}' "$MONGO_CID" | awk '{print $1; exit}')
if [ -z "$NET" ]; then
  echo "Could not detect docker network for mongo" >&2
  exit 1
fi

echo "==> Seed via golang image (first run downloads modules; may take a few minutes)"
echo "    network=$NET  db URI host must be reachable (e.g. mongo:27017 in .env)"
exec docker run --rm \
  --network "$NET" \
  -v "$BACKEND:/work" \
  -w /work \
  -e MONGODB_URI="$MONGODB_URI" \
  -e CGO_ENABLED=0 \
  golang:1.24-alpine \
  sh -c 'go run ./migrations/seed.go'
