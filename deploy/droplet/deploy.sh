#!/usr/bin/env bash
# R-Loko Droplet — one-command deploy from this directory.
#
# Usage: ./deploy.sh [ghcr|quick|env|build-web|build] --env dev|prod [options]
#
# Environments:
#   --env dev    use .env.dev  → deploys to dev.rloko.com   (default)
#   --env prod   use .env.prod → deploys to rloko.com
#
# Modes:
#   ghcr (default)  git pull → pull api+web images from GHCR → up
#   quick           no git, no pull — restart with existing images (~1 min)
#   env             apply .env changes to api only, no image pull (~30 s)
#   build-web       build Vite on the Droplet (bakes VITE_* from env file); 15-45+ min — use tmux
#   build           compile Go + Vite on Droplet (very slow; use CI images instead)
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
RLOKO_ROOT="$(cd "$DIR/../.." && pwd)"
export DOCKER_BUILDKIT=1
export DOCKER_CLIENT_TIMEOUT="${DOCKER_CLIENT_TIMEOUT:-600}"

MODE="ghcr"
MODE_LABEL="ghcr"
DEPLOY_ENV="dev"
SKIP_GIT=0
SKIP_LOGIN=0
NO_PULL=0
LOGFILE=""
QUICK=0
INIT_SUBMODULES=0

usage() {
  cat <<'EOF'
Usage: deploy.sh [ghcr|quick|env|build-web|build] --env dev|prod [options]

Environments:
  --env dev   (default) uses .env.dev  → dev.rloko.com
  --env prod            uses .env.prod → rloko.com

Modes:
  ghcr (default)  git pull → GHCR pull api+web → up
  quick           no git, no pull — restart with existing images
  env             apply .env changes to api only (no pull, ~30 s)
  build-web       pull api (GHCR) + build Vite on Droplet from env file
  build           compile Go + Vite on Droplet (not recommended; use CI images)

Typical use:
  ./deploy.sh --env dev          New release to dev
  ./deploy.sh --env prod         New release to prod
  ./deploy.sh env --env dev      Apply .env.dev changes to api only
  ./deploy.sh build-web --env prod  Build prod web image on-server

Options:
  --init-submodules   Run submodule update after git pull (for build/build-web)
  --skip-git          Skip git pull
  --skip-login        Skip docker login (use if already logged in)
  --no-pull           Skip docker pull of images
  --log FILE          Append all output to FILE
  -h, --help          This help

Prerequisites: .env.dev and .env.prod in this directory (cp .env.dev.example .env.dev).
EOF
}

while [ $# -gt 0 ]; do
  case "$1" in
    ghcr|build|build-web) MODE="$1"; MODE_LABEL="$1"; shift ;;
    quick) MODE=ghcr; QUICK=1; SKIP_GIT=1; NO_PULL=1; MODE_LABEL=quick; shift ;;
    env)   MODE=env; MODE_LABEL=env; shift ;;
    --env)
      if [ $# -lt 2 ] || [ -z "${2:-}" ]; then echo "--env needs dev or prod" >&2; exit 1; fi
      DEPLOY_ENV="$2"; shift 2
      ;;
    --init-submodules) INIT_SUBMODULES=1; shift ;;
    --skip-git)   SKIP_GIT=1;   shift ;;
    --skip-login) SKIP_LOGIN=1; shift ;;
    --no-pull)    NO_PULL=1;    shift ;;
    --log)
      if [ $# -lt 2 ] || [ -z "${2:-}" ]; then echo "--log needs a file path" >&2; exit 1; fi
      LOGFILE="$2"; shift 2
      ;;
    -h|--help)  usage; exit 0 ;;
    *)
      if [ "${1#-}" != "$1" ]; then echo "Unknown option: $1" >&2; usage; exit 1; fi
      echo "Unknown argument: $1" >&2; usage; exit 1
      ;;
  esac
done

# Resolve env file
ENV_FILE="$DIR/.env.${DEPLOY_ENV}"
if [ ! -f "$ENV_FILE" ]; then
  echo "Missing $ENV_FILE — run: cp .env.${DEPLOY_ENV}.example .env.${DEPLOY_ENV}" >&2
  exit 1
fi

# Derive PUBLIC_HOST from env file for health check URL
PUBLIC_HOST=$(grep -E '^[[:space:]]*PUBLIC_DOMAIN=' "$ENV_FILE" 2>/dev/null \
  | sed 's/.*PUBLIC_DOMAIN=//' | tr -d '"'"'" | head -1)
PUBLIC_HOST="${PUBLIC_HOST:-${DEPLOY_ENV}.rloko.com}"

echo "==> Environment: ${DEPLOY_ENV} (${ENV_FILE}), host: ${PUBLIC_HOST}"

if [ -n "$LOGFILE" ]; then
  # shellcheck disable=SC2094
  exec > >(tee -a "$LOGFILE") 2>&1
  echo "==> Logging to $LOGFILE (start: $(date -Iseconds 2>/dev/null || date))"
fi

cd "$DIR"

COMPOSE_GHCR=(docker compose --env-file "$ENV_FILE" -f "$DIR/docker-compose.ghcr.yml")
COMPOSE_WEB_BAKE=(docker compose --env-file "$ENV_FILE" -f "$DIR/docker-compose.ghcr.yml" -f "$DIR/docker-compose.ghcr-web-build.yml")
COMPOSE_BUILD=(docker compose --env-file "$ENV_FILE" -f "$DIR/docker-compose.yml")

# --- env: apply env file to api, nothing else (fast) ---
if [ "$MODE" = "env" ]; then
  if ! grep -qE '^[[:space:]]*API_IMAGE=.[[:alnum:]:._/-]+' "$ENV_FILE"; then
    echo "In $ENV_FILE, set API_IMAGE=, e.g. ghcr.io/org/rloco-api:latest" >&2
    exit 1
  fi
  echo "==> env: recreate **api** from $ENV_FILE (no git, no docker pull) — $(date -Iseconds 2>/dev/null || true)"
  "${COMPOSE_GHCR[@]}" up -d --force-recreate --no-deps api
  echo "    Tip: edited Caddyfile?  ${COMPOSE_GHCR[*]} up -d --force-recreate caddy"
  PS_CMD=("${COMPOSE_GHCR[@]}")
  echo "==> Services"
  "${PS_CMD[@]}" ps
  echo "==> Health (Host: $PUBLIC_HOST → http://127.0.0.1/health)"
  if code=$(curl -sfS --connect-timeout 3 --max-time 12 -o /dev/null -w '%{http_code}' -H "Host: $PUBLIC_HOST" "http://127.0.0.1/health" 2>/dev/null); then
    echo "    /health => HTTP $code"
  else
    echo "    /health check failed" >&2
  fi
  echo "==> Done (env / ${DEPLOY_ENV})."
  exit 0
fi

# Pre-built web images ignore VITE_* in env file; bake with build-web, full build, or GitHub Actions.
if [ "$MODE" = "ghcr" ] && [ "$QUICK" -eq 0 ] && grep -qE '^[[:space:]]*VITE_GOOGLE_CLIENT_ID=[^#[:space:]]' "$ENV_FILE" 2>/dev/null; then
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

# Git: for ghcr/quick, skip heavy submodule fetch unless --init-submodules (not needed to run pre-built images)
DO_SUB=0
if [ "$MODE" = "build" ] || [ "$MODE" = "build-web" ]; then
  DO_SUB=1
fi
if [ "$INIT_SUBMODULES" -eq 1 ]; then
  DO_SUB=1
fi

if [ "$SKIP_GIT" -eq 0 ]; then
  if [ "$DO_SUB" -eq 1 ]; then sub_note="run"; else sub_note="skip (not required for pre-built images)"; fi
  echo "==> Git: pull in $RLOKO_ROOT (submodules: $sub_note)"
  if ! { git -C "$RLOKO_ROOT" pull --rebase 2>/dev/null || git -C "$RLOKO_ROOT" pull; }; then
    cat <<'EOT' >&2
Git pull failed. If you see "Could not resolve host: github.com", fix DNS on this machine.
  • Try:  getent hosts github.com
  • Often works:  sudo resolvectl dns eth0 1.1.1.1 8.8.8.8   (replace eth0: ip -br a)
  • Or add in /etc/netplan/ under ethernets:→YOUR_IFACE:  nameservers: { addresses: [1.1.1.1,8.8.8.8] }  then  sudo netplan apply
  • Deploy without updating repo:  ./deploy.sh ghcr --skip-git
EOT
    exit 1
  fi
  if [ "$DO_SUB" -eq 1 ]; then
    echo "==> git submodule update --init --recursive (build / build-web need this)"
    git -C "$RLOKO_ROOT" submodule update --init --recursive
  else
    echo "==> skipping git submodule (ghcr: deploy uses Docker images only; for build-web first run, use:  ./deploy.sh --init-submodules  or  git submodule update --init --recursive)"
  fi
fi

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
  • Fine-grained token: allow "read" for packages of the org/user that owns the image
  • Organization with SAML/SSO: enable SSO for your token
  • Or:  ./deploy.sh --skip-login  (after: docker login ghcr.io -u YOUR_USER)

EOT
      exit 1
    fi
  elif [ -n "$PAT" ] && [ "$SKIP_LOGIN" -ne 0 ]; then
    echo "==> skipping docker login (--skip-login); using existing registry auth"
  fi

  if [ "$NO_PULL" -eq 0 ]; then
    echo "==> docker compose pull api web (not mongo/caddy; faster than full pull all)"
    "${COMPOSE_GHCR[@]}" pull api web
  else
    echo "==> skipping docker pull (--no-pull) — using images already on this host"
  fi

  if [ "$QUICK" -eq 1 ]; then
    echo "==> quick: docker compose up -d (no re-pull of layers)"
  else
    echo "==> docker compose up -d (ghcr)"
  fi
  "${COMPOSE_GHCR[@]}" up -d
  PS_CMD=("${COMPOSE_GHCR[@]}")

elif [ "$MODE" = "build-web" ]; then
  echo "==> build-web: pull api (GHCR) + build only the web (Vite) from $ENV_FILE (small VM–friendly)"
  if ! grep -qE '^[[:space:]]*VITE_GOOGLE_CLIENT_ID=[^#[:space:]]' "$ENV_FILE"; then
    echo "WARNING: VITE_GOOGLE_CLIENT_ID empty in $ENV_FILE — Google Sign-In may show 'not configured'." >&2
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

-- build-web can take 15–45+ minutes on a 1 vCPU/1GB Droplet. Prefer CI "Publish Droplet images" to bake Vite.
   • tmux:  tmux new -s deploy
   • log:   ./deploy.sh build-web --log /tmp/rloko-deploy.log --skip-git

EOT
  echo "==> docker compose build web (uses BuildKit cache)"
  "${COMPOSE_WEB_BAKE[@]}" build web
  echo "==> docker compose up -d"
  "${COMPOSE_WEB_BAKE[@]}" up -d
  PS_CMD=("${COMPOSE_WEB_BAKE[@]}")

else
  echo "==> full build: Go api + Vite web on this host (use tmux; or CI + ./deploy.sh)" >&2
  if ! grep -qE '^[[:space:]]*VITE_GOOGLE_CLIENT_ID=[^#[:space:]]' "$ENV_FILE"; then
    echo "WARNING: VITE_GOOGLE_CLIENT_ID is missing or empty in $ENV_FILE" >&2
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
  echo "    /health check failed" >&2
fi

echo "==> curl (from this host or your laptop)"
echo "    curl -sS -H \"Host: $PUBLIC_HOST\" http://127.0.0.1/health"
echo "    curl -sS https://$PUBLIC_HOST/health"
echo "    curl -sS https://$PUBLIC_HOST/api/config"

echo "==> Done ($MODE_LABEL / ${DEPLOY_ENV})."
