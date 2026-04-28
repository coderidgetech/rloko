#!/usr/bin/env bash
# R-Loko Droplet — one-command deploy from this directory.
# Usage: ./deploy.sh              # fast path: all images from GHCR
#        ./deploy.sh build-web  # only rebuild frontend (Vite) here — keep api from GHCR (preferred for small VMs)
#        ./deploy.sh build      # compile Go api + Vite web on the server (very slow / may OOM on 1 vCPU/1GB)
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
RLOKO_ROOT="$(cd "$DIR/../.." && pwd)"
export DOCKER_BUILDKIT=1
# Slow pulls / large image layers on small links (default 300s can be tight)
export DOCKER_CLIENT_TIMEOUT="${DOCKER_CLIENT_TIMEOUT:-600}"

MODE="ghcr"
SKIP_GIT=0
SKIP_LOGIN=0
NO_PULL=0
LOGFILE=""
PUBLIC_HOST="${PUBLIC_HOST:-dev.rloko.com}"

usage() {
  cat <<'EOF'
Usage: deploy.sh [ghcr|build-web|build] [options]

  ghcr (default)  git pull → pull GHCR → up (no compile on the Droplet)
  build-web       same + build ONLY the web (Vite) image from .env; api/mongo stay GHCR — use for VITE_GOOGLE_*
  build           build api (Go) + web (Vite) on the Droplet — can take 30–90+ min on a small plan or run out of RAM

Options:
  --skip-git     Skip git pull and submodule update
  --skip-login   (ghcr) Skip docker login (use if already logged in, or public images)
  --no-pull      (ghcr / build-web) Skip image pull
  --log FILE     Append all output to FILE (use if SSH may drop — you can tail -f FILE)
  -h, --help     This help

Environment (optional, ghcr):
  GHCR_PAT or GHCR_TOKEN  Personal access token; if set, runs docker login before pull
  GHCR_USER or GITHUB_USER  Your GitHub username (not org name, not email)
  PUBLIC_HOST  Hostname in Caddy for the local /health check (default: dev.rloko.com)

Prerequisites: .env in this directory.
  • ghcr:     API_IMAGE and WEB_IMAGE
  • build-web: API_IMAGE (WEB_IMAGE not used); VITE_* baked from .env
  • build:    VITE_* from .env; no GHCR image tags required for local build
EOF
}

while [ $# -gt 0 ]; do
  case "$1" in
    ghcr|build|build-web) MODE="$1"; shift ;;
    --skip-git)   SKIP_GIT=1;   shift ;;
    --skip-login) SKIP_LOGIN=1; shift ;;
    --no-pull)    NO_PULL=1;    shift ;;
    --log)
      if [ $# -lt 2 ] || [ -z "${2:-}" ]; then echo "--log needs a file path" >&2; exit 1; fi
      LOGFILE="$2"
      shift 2
      ;;
    -h|--help)  usage; exit 0 ;;
    *)
      if [ "${1#-}" != "$1" ]; then echo "Unknown option: $1" >&2; usage; exit 1; fi
      echo "Unknown argument: $1 (use ghcr, build-web, or build — update script: git pull in repo root)" >&2
      usage
      exit 1
      ;;
  esac
done

if [ -n "$LOGFILE" ]; then
  # shellcheck disable=SC2094
  exec > >(tee -a "$LOGFILE") 2>&1
  echo "==> Logging to $LOGFILE (start: $(date -Iseconds 2>/dev/null || date))"
fi

if [ ! -f "$DIR/.env" ]; then
  echo "No $DIR/.env — run: cp .env.example .env && edit .env" >&2
  exit 1
fi

cd "$DIR"

# Pre-built web images ignore VITE_* in .env; bake with build-web, full build, or GitHub Actions.
if [ "$MODE" = "ghcr" ] && grep -qE '^[[:space:]]*VITE_GOOGLE_CLIENT_ID=[^#[:space:]]' .env 2>/dev/null; then
  echo "NOTE: VITE_GOOGLE_CLIENT_ID in .env is not used in ghcr mode. Use:  ./deploy.sh build-web" >&2
  echo "      (or GitHub secret VITE_GOOGLE_CLIENT_ID + Publish Droplet images)." >&2
fi

if [ "$MODE" = "ghcr" ] || [ "$MODE" = "build-web" ]; then
  if ! grep -qE '^[[:space:]]*API_IMAGE=.[[:alnum:]:._/-]+' .env; then
    echo "In .env, set API_IMAGE=, e.g. ghcr.io/org/rloco-api:latest" >&2
    exit 1
  fi
  if [ "$MODE" = "ghcr" ] && ! grep -qE '^[[:space:]]*WEB_IMAGE=.[[:alnum:]:._/-]+' .env; then
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
COMPOSE_WEB_BAKE=(docker compose --env-file "$DIR/.env" -f "$DIR/docker-compose.ghcr.yml" -f "$DIR/docker-compose.ghcr-web-build.yml")
# --env-file forces substitution for build.args (VITE_*) from this file even if cwd were wrong
COMPOSE_BUILD=(docker compose --env-file "$DIR/.env" -f "$DIR/docker-compose.yml")

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

elif [ "$MODE" = "build-web" ]; then
  echo "==> build-web: pull api (GHCR) + build only the web (Vite) from $DIR/.env (small VM–friendly)"
  if ! grep -qE '^[[:space:]]*VITE_GOOGLE_CLIENT_ID=[^#[:space:]]' .env; then
    echo "WARNING: VITE_GOOGLE_CLIENT_ID empty in .env — Google Sign-In may show 'not configured'." >&2
  fi
  PAT="${GHCR_PAT:-${GHCR_TOKEN:-}}"
  if [ -n "$PAT" ] && [ "$SKIP_LOGIN" -eq 0 ]; then
    GUSER="${GHCR_USER:-${GITHUB_USER:-}}"
    if [ -n "$GUSER" ]; then
      echo "==> docker login ghcr.io (user: $GUSER)"
      echo "$PAT" | docker login ghcr.io -u "$GUSER" --password-stdin
    fi
  fi
  if [ "$NO_PULL" -eq 0 ]; then
    echo "==> pull api image from GHCR (web is built locally, not pulled)"
    "${COMPOSE_GHCR[@]}" pull api
  fi
  cat <<'EOT' >&2

-- build-web can take 15–45+ minutes on a 1 vCPU/1GB Droplet. If your SSH client times out, the
   build is killed and containers may not start. Use ONE of:
   • tmux:   sudo apt install -y tmux 2>/dev/null; tmux new -s deploy   # then run this script again
   • log:    ./deploy.sh build-web --log /tmp/rloko-deploy.log --skip-git
   • nohup:  nohup ./deploy.sh build-web --skip-git --log /tmp/rloko-deploy.log </dev/null & disown
   Reconnect, then: tail -f /tmp/rloko-deploy.log
   If build already finished and only 'up' is missing, from deploy/droplet:
   docker compose --env-file .env -f docker-compose.ghcr.yml -f docker-compose.ghcr-web-build.yml up -d

EOT
  echo "==> docker compose build web (uses BuildKit cache; 5–20+ min on first run)"
  "${COMPOSE_WEB_BAKE[@]}" build web
  echo "==> docker compose up -d"
  "${COMPOSE_WEB_BAKE[@]}" up -d
  PS_CMD=("${COMPOSE_WEB_BAKE[@]}")

else
  echo "==> full build: Go api + Vite web on this host (use tmux; or ./deploy.sh build-web)" >&2
  if ! grep -qE '^[[:space:]]*VITE_GOOGLE_CLIENT_ID=[^#[:space:]]' .env; then
    echo "WARNING: VITE_GOOGLE_CLIENT_ID is missing or empty in .env — Google Sign-In will stay 'not configured'." >&2
  fi
  "${COMPOSE_BUILD[@]}" up -d --build
  PS_CMD=("${COMPOSE_BUILD[@]}")
fi

echo "==> Services"
"${PS_CMD[@]}" ps

echo "==> Health (Host: $PUBLIC_HOST → http://127.0.0.1/health)"
if code=$(curl -sfS --connect-timeout 3 --max-time 12 -o /dev/null -w '%{http_code}' -H "Host: $PUBLIC_HOST" "http://127.0.0.1/health" 2>/dev/null); then
  echo "    /health => HTTP $code"
else
  echo "    /health check failed (wrong PUBLIC_HOST? try: PUBLIC_HOST=your.caddy.host ./deploy.sh)" >&2
fi

echo "==> curl (from this host or your laptop; health is /health, not /api/health)"
echo "    curl -sS -H \"Host: $PUBLIC_HOST\" http://127.0.0.1/health"
echo "    curl -sS https://$PUBLIC_HOST/health"
echo "    curl -sS https://$PUBLIC_HOST/api/config   # needs Mongo + seed"

echo "==> Done ($MODE)."
