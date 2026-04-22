#!/usr/bin/env bash
# Deploy to DigitalOcean App Platform using app.yaml at the repository root.
# Prereq: doctl auth init   (or export DIGITALOCEAN_ACCESS_TOKEN)
#
# First time:  ./scripts/deploy-app-platform.sh
# If you get "App name already exists" (409), the app was created already — update it:
#   doctl apps list
#   DO_APP_ID=<copy the ID for rloko-app> ./scripts/deploy-app-platform.sh
#
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SPEC="${ROOT}/app.yaml"
cd "$ROOT"

if ! command -v doctl >/dev/null; then
  echo "Install doctl: https://docs.digitalocean.com/reference/doctl/how-to/install/"
  exit 1
fi
if ! doctl account get >/dev/null 2>&1; then
  echo "Authenticate first:  doctl auth init"
  echo "or:  export DIGITALOCEAN_ACCESS_TOKEN=your_token"
  exit 1
fi

if [[ -n "${DO_APP_ID:-}" ]]; then
  echo "Updating app ${DO_APP_ID} from ${SPEC}"
  doctl apps update "$DO_APP_ID" --spec "$SPEC"
else
  echo "Creating app from ${SPEC}"
  if ! doctl apps create --spec "$SPEC"; then
    echo ""
    echo "If the error was 'App name already exists' (409), update the existing app instead:"
    echo "  doctl apps list"
    echo "  DO_APP_ID=<id-from-list> ./scripts/deploy-app-platform.sh"
    exit 1
  fi
fi
