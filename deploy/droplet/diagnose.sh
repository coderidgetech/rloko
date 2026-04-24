#!/usr/bin/env bash
# Run on the Droplet from deploy/droplet when you see 502/503 on /api/*.
set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
cd "$DIR"
COMPOSE=(docker compose -f "$DIR/docker-compose.ghcr.yml")

echo "=== $(date) — project: $DIR"
echo "=== docker compose ps"
"${COMPOSE[@]}" ps -a

echo ""
echo "=== api container (last 120 lines — look for FATAL / Failed to connect to database)"
if "${COMPOSE[@]}" ps -q api 2>/dev/null | grep -q .; then
  "${COMPOSE[@]}" logs api --tail 120 2>&1
else
  echo "(no api container — was it ever started?)"
fi

echo ""
echo "=== mongo container (last 30 lines)"
"${COMPOSE[@]}" logs mongo --tail 30 2>&1 || true

echo ""
echo "=== /health from inside api container (needs wget in image — republish API if this fails)"
if "${COMPOSE[@]}" ps -q api 2>/dev/null | grep -q .; then
  if "${COMPOSE[@]}" exec -T api sh -c 'command -v wget >/dev/null 2>&1' 2>/dev/null; then
    "${COMPOSE[@]}" exec -T api wget -q -O- "http://127.0.0.1:8080/health" 2>&1 || true
  else
    echo "(old API image: no wget — use api logs above; republish 'Publish Droplet images' and pull api)"
  fi
else
  echo "skip (no api)"
fi

echo ""
echo "=== Caddy (last 40 lines)"
"${COMPOSE[@]}" logs caddy --tail 40 2>&1 || true

echo ""
echo "=== hints"
echo "  • 502 on /api: almost always api container exited or never bound :8080 — read api logs above."
echo "  • 'Failed to connect to database': fix MONGODB_URI / MONGO_ROOT_PASSWORD in .env"
echo "  • 'CORS_ALLOWED_ORIGINS must be set': set CORS_ALLOWED_ORIGINS in .env for ENV=production"
echo "  • 'JWT_SECRET': production needs a non-default JWT_SECRET in .env"
echo "  • After changing .env:  ${COMPOSE[*]} up -d api"
echo "  • New API code: run GitHub 'Publish Droplet images' then:  ./deploy.sh"
