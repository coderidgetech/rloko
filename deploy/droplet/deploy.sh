#!/usr/bin/env bash
# R-Loko Droplet — one-command deploy from this directory.
# Usage: ./deploy.sh          # fast path: GHCR images
#        ./deploy.sh build    # slow: compile api+web on the server
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
RLOKO_ROOT="$(cd "$DIR/../.." && pwd)"
export DOCKER_BUILDKIT=1

MODE="ghcr"
SKIP_GIT=0
SKIP_LOGIN=0
NO_PULL=0
PUBLIC_HOST="${PUBLIC_HOST:-dev.rloko.com}"

usage() {
  cat <<'EOF'
Usage: deploy.sh [ghcr|build] [options]

  ghcr   (default)  git pull → docker login (optional) → pull images → up -d
  build             git pull → docker compose build on this Droplet (slow)

Options:
  --skip-git     Skip git pull and submodule update
  --skip-login   (ghcr) Skip docker login (use if already logged in, or public images)
  --no-pull      (ghcr only) Skip "docker compose pull" (only recreate containers)
  -h, --help     This help

Environment (optional, ghcr):
  GHCR_PAT or GHCR_TOKEN  Personal access token; if set, runs docker login before pull
  GHCR_USER or GITHUB_USER  Your GitHub username (not org name, not email)
  PUBLIC_HOST  Hostname in Caddy for the local /health check (default: dev.rloko.com)

Prerequisites: .env in this directory; for ghcr, set API_IMAGE and WEB_IMAGE in .env.
EOF
}

while [ $# -gt 0 ]; do
  case "$1" in
    ghcr|build) MODE="$1"; shift ;;
    --skip-git)   SKIP_GIT=1;   shift ;;
    --skip-login) SKIP_LOGIN=1; shift ;;
    --no-pull)    NO_PULL=1;    shift ;;
    -h|--help)  usage; exit 0 ;;
    *)
      if [ "${1#-}" != "$1" ]; then echo "Unknown option: $1" >&2; usage; exit 1; fi
      echo "Unknown argument: $1 (use ghcr or build)" >&2
      usage
      exit 1
      ;;
  esac
done

if [ ! -f "$DIR/.env" ]; then
  echo "No $DIR/.env — run: cp .env.example .env && edit .env" >&2
  exit 1
fi

cd "$DIR"

if [ "$MODE" = "ghcr" ]; then
  if ! grep -qE '^[[:space:]]*API_IMAGE=.[[:alnum:]:._/-]+' .env; then
    echo "In .env, set API_IMAGE= (and WEB_IMAGE=), e.g. ghcr.io/org/rloco-api:latest" >&2
    exit 1
  fi
  if ! grep -qE '^[[:space:]]*WEB_IMAGE=.[[:alnum:]:._/-]+' .env; then
    echo "In .env, set WEB_IMAGE= (e.g. ghcr.io/org/rloco-web:latest)" >&2
    exit 1
  fi
fi

if [ "$SKIP_GIT" -eq 0 ]; then
  echo "==> Git: pull + submodules (repo: $RLOKO_ROOT)"
  git -C "$RLOKO_ROOT" pull --rebase 2>/dev/null || git -C "$RLOKO_ROOT" pull
  git -C "$RLOKO_ROOT" submodule update --init --recursive
fi

COMPOSE_GHCR=(docker compose -f "$DIR/docker-compose.ghcr.yml")
COMPOSE_BUILD=(docker compose -f "$DIR/docker-compose.yml")

if [ "$MODE" = "ghcr" ]; then
  PAT="${GHCR_PAT:-${GHCR_TOKEN:-}}"
  if [ -n "$PAT" ] && [ "$SKIP_LOGIN" -eq 0 ]; then
    GUSER="${GHCR_USER:-${GITHUB_USER:-}}"
    if [ -z "$GUSER" ]; then
      echo "Set GHCR_USER or GITHUB_USER to log in to ghcr.io" >&2
      exit 1
    fi
    echo "==> docker login ghcr.io (user: $GUSER)"
    if ! echo "$PAT" | docker login ghcr.io -u "$GUSER" --password-stdin; then
      cat <<'EOT' >&2

GHCR login failed (denied). Fix one of:
  • Create a new classic PAT: https://github.com/settings/tokens — scope: read:packages
    (use write:packages only if this machine pushes images)
  • Fine-grained token: allow "read" for packages of the org/user that owns the image
  • Organization with SAML/SSO: GitHub → org → Settings → Personal access tokens → Enable SSO for your token
  • Username must be your GitHub username (the account that owns the PAT), not the org name
  • Or skip automated login:  unset GHCR_PAT  and  ./deploy.sh --skip-login  (after: docker login ghcr.io -u YOUR_USER)
  • Public packages: unset GHCR_PAT; pull may work without login

EOT
      exit 1
    fi
  elif [ -n "$PAT" ] && [ "$SKIP_LOGIN" -ne 0 ]; then
    echo "==> skipping docker login (--skip-login); using existing registry auth"
  fi

  if [ "$NO_PULL" -eq 0 ]; then
    echo "==> docker compose pull (ghcr images)"
    "${COMPOSE_GHCR[@]}" pull
  else
    echo "==> skipping docker pull (--no-pull)"
  fi

  echo "==> docker compose up -d (ghcr)"
  "${COMPOSE_GHCR[@]}" up -d
  PS_CMD=("${COMPOSE_GHCR[@]}")
else
  echo "==> docker compose up -d --build (local build, may take a long time)"
  "${COMPOSE_BUILD[@]}" up -d --build
  PS_CMD=("${COMPOSE_BUILD[@]}")
fi

echo "==> Services"
"${PS_CMD[@]}" ps

echo "==> Health (Host: $PUBLIC_HOST → http://127.0.0.1/health)"
if code=$(curl -sfS -o /dev/null -w '%{http_code}' -H "Host: $PUBLIC_HOST" "http://127.0.0.1/health" 2>/dev/null); then
  echo "    /health => HTTP $code"
else
  echo "    /health check failed (wrong PUBLIC_HOST? try: PUBLIC_HOST=your.caddy.host ./deploy.sh)" >&2
fi

echo "==> curl (from this host or your laptop; health is /health, not /api/health)"
echo "    curl -sS -H \"Host: $PUBLIC_HOST\" http://127.0.0.1/health"
echo "    curl -sS https://$PUBLIC_HOST/health"
echo "    curl -sS https://$PUBLIC_HOST/api/config   # needs Mongo + seed"

echo "==> Done ($MODE)."
